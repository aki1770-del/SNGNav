/// JmaAdvisoryProvider — `AdvisoryProvider` adapter for the JMA
/// **windowless per-prefecture warning JSON**.
///
/// Resolves the caller's lat/lon to **every** catalogued snow-zone
/// prefecture (office) code whose bounding box contains the point — one
/// for an interior point, or the full containing set at a border (the
/// boxes overlap along every shared border) — fetches each prefecture's
/// `warning/{areacode}.json` **concurrently**, parses the current in-force
/// warnings, filters to the surfaced classes (`kJmaWarningCodes` — the
/// snow / blizzard / icing classes plus, from 0.4.0, the downpour /
/// typhoon-wind / thunder / fog turmoil classes), maps each to
/// a source-neutral `Advisory`, and returns the **deduplicated union**.
/// This is the conservative, over-warn handling of border ambiguity: a
/// border driver never misses a neighbouring prefecture's warning because
/// the resolver guessed a single side (0.3.0). When the union is non-empty
/// but a containing prefecture could not be fetched, the partial read is
/// signalled in-band (see `fetchActiveAdvisoriesAtPoint`).
///
/// ## Why the warning JSON (replaces the 0.1.x atom-feed path)
///
/// Through 0.1.x the adapter read the JMA disaster-info atom feed
/// (`extra.xml`) and walked each linked per-prefecture report XML. An
/// independent safety audit found a **window / scroll-off
/// false-negative**: the atom feed is a recent-publication *window*, so
/// a still-in-force warning that was last re-issued before the window
/// opens scrolls off and is silently missed — a false-negative for a
/// snow-WARNING package. The windowless `warning/{areacode}.json` has no
/// window to scroll off (and is ~7 KB vs ~0.6 MB for the atom feed) — but
/// windowless is NOT live: measured 2026-08-16 this path was frozen
/// nationwide since late May. Feed liveness is surfaced separately, in band;
/// see [JmaAdvisoryProvider.staleFeedThreshold].
///
/// Construction discipline (per condition_aggregator interface
/// contract):
/// - configuration is constructor-injected;
/// - `init()` is invoked exactly once before any
///   `fetchActiveAdvisoriesAtPoint` call;
/// - configuration change → new adapter instance.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:http/http.dart' as http;

import 'jma_advisory_mapper.dart';
import 'jma_r8_warning_mapper.dart';

/// Base URL for the JMA windowless per-prefecture warning JSON. The
/// provider appends `{areacode}.json` (e.g. `050000.json` for Akita).
///
/// This endpoint is **windowless** — there is no publication window to scroll
/// off, which is the false-negative the 0.1.x atom-feed path could not avoid.
///
/// ⚑ **Windowless is not the same as live, and this note used to conflate
/// them.** It previously read "always reflects the prefecture's CURRENT
/// in-force warning state". Measured 2026-08-16: every document on this path
/// was frozen nationwide in late May — Akita still serving a 2026-05-28
/// 雷注意報 as `status=発表`, ~80 days on — while the sibling
/// `bosai/forecast/` path on the same host and CDN was minutes old, and JMA's
/// official developer feed (`www.data.jma.go.jp/developer/xml/feed/extra.xml`)
/// carried 515 live 警報・注意報 entries the same minute. So the document has
/// no scroll-off window AND can still be arbitrarily old. Callers MUST judge
/// liveness from the document's own `reportDatetime` — see [parseJmaFeed] and
/// [JmaAdvisoryProvider.staleFeedThreshold]. **A publisher path being
/// windowless says nothing about whether anyone is still writing to it.**
const String kJmaWarningJsonBaseUrl =
    'https://www.jma.go.jp/bosai/warning/data/r8/';

/// The path this package read from 0.2.0 through 0.6.0, retained ONLY so a
/// reader can see what was replaced and why. **Do not fetch it.**
///
/// It was retired by JMA's 2026-05-29 防災気象情報 restructure and has served a
/// frozen 2026-05-28 document ever since — answering `200`, well-formed,
/// indefinitely. Re-measured 2026-08-24: `reportDatetime`
/// `2026-05-28T06:11:00+09:00` for Akita, ~88 days.
const String kJmaRetiredWarningJsonBaseUrl =
    'https://www.jma.go.jp/bosai/warning/data/warning/';

/// The single per-prefecture fetch budget — also reused as the outer batch
/// backstop — bounding network I/O so a hung or runaway publisher response
/// cannot exhaust integrator memory or stall the driver-facing UI.
///
/// EVERY per-prefecture fetch uses this as its OWN per-request timeout — an
/// interior single fetch and each border sibling alike. There is deliberately
/// **no shorter border budget**: a single budget everywhere never times out
/// HER OWN slow-but-valid warning arriving late on a marginal snow-link
/// (whether interior or at a border). The same value is also the OUTER **batch
/// backstop** for the whole concurrent border fetch — only reached in the
/// theoretical case where the `Future.wait` combinator machinery itself stalls
/// (in normal operation each sibling self-bounds at its per-request timeout
/// first).
///
/// Per-prefecture isolation (each `_fetchPrefecture` always resolves to a
/// captured result) already prevents a hung sibling from blocking or
/// discarding a fast sibling's success; the only cost of a single budget is
/// latency — a hung border neighbour can make the union take up to this budget
/// before it returns (carrying the in-band incomplete-read notice). That
/// latency is preferred over ever dropping HER own slow-but-valid warning.
const Duration kJmaFetchWallClockBudget = Duration(seconds: 30);

/// Per-prefecture warning JSON byte cap. The live response is tiny
/// (Akita observed 2026-06-26 at 7,424 bytes); 256 KiB gives ample
/// headroom for a prefecture under many simultaneous warnings while
/// still bounding a runaway response. This is ~16x smaller than the
/// old atom-feed cap — the windowless JSON is per-prefecture, not a
/// national feed of every recent report.
const int kJmaWarningJsonMaxBytes = 256 * 1024;

/// Thrown when the provider cannot reach the JMA endpoint, the
/// response exceeds a documented byte cap, or the wall-clock budget
/// is exhausted before a successful parse.
class JmaAdvisoryFetchException implements Exception {
  final String message;
  final Uri? uri;
  final int? statusCode;
  const JmaAdvisoryFetchException(this.message, {this.uri, this.statusCode});

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (status $statusCode)';
    final u = uri == null ? '' : ' [$uri]';
    return 'JmaAdvisoryFetchException: $message$code$u';
  }
}

/// Default [JmaAdvisoryProvider.staleFeedThreshold] — six hours.
///
/// Chosen against the measurement that motivated it: on 2026-08-16 the JMA
/// `bosai/warning/data/warning/` documents were frozen nationwide since late
/// May, i.e. ~80 days, while the sibling `bosai/forecast/` path on the same
/// host was minutes old. Six hours is far inside that, and matches the
/// threshold this unit's winter instrument arrived at independently.
const Duration kJmaDefaultStaleFeedThreshold = Duration(hours: 6);

/// Adapter implementing [AdvisoryProvider] against the JMA windowless
/// per-prefecture warning JSON.
class JmaAdvisoryProvider
    implements AdvisoryProvider, AdvisoryFeedFreshnessReporting {
  /// Base URL for the per-prefecture warning JSON. Default points at
  /// the public JMA bosai endpoint; injectable for testing or for an
  /// integrator-side mirror.
  final String warningJsonBaseUrl;

  /// User-Agent string. JMA does not require auth, but a contactable
  /// User-Agent is best practice so the publisher can reach the
  /// integrator if a request shape misbehaves at scale.
  final String userAgent;

  /// HTTP client — injectable for testing.
  final http.Client _http;

  /// Clock — injectable so feed-staleness is testable without waiting 80 days.
  final DateTime Function() _now;

  /// The staleness measured during the most recent point query, or `null` when
  /// that document was current. Backs [feedStaleness].
  ///
  /// ⚑ RESTORED IN 0.7.0. 0.3.2 implemented [AdvisoryFeedFreshnessReporting];
  /// 0.5.0 and 0.6.0 dropped it while keeping the in-band notice, and the
  /// interface's own doc names the consequence: an adapter that does not
  /// implement it "can still serve a frozen document and still satisfy
  /// `canAssertNoAdvisory`". The in-band notice is for a human reading a list;
  /// this getter is for the aggregator deciding whether it may assert a calm
  /// road. They are not substitutes and 0.5.0 traded the second for the first.
  AdvisoryFeedStaleness? _feedStaleness;

  /// How old a JMA warning document may be before this adapter adds an in-band
  /// [buildStaleFeedNotice] to the returned list.
  ///
  /// **Why there is a default at all**, when the parent package deliberately
  /// declines to pick a staleness threshold and leaves that policy to the
  /// integrator: the parent's position is right for *rendering* policy, and it
  /// is what `Advisory.isStaleAt` implements — the integrator supplies the
  /// threshold. But a policy an integrator must remember to apply is a policy
  /// that will not be applied, and the failure mode here is silence: a feed
  /// that has stopped moving produces an empty list, which is the same value a
  /// clear sky produces. So this adapter ships a conservative default that
  /// makes the fact *available in band*, at `minor` severity, filterable and
  /// non-blocking. The integrator still owns what to render.
  ///
  /// The default is 6 hours, matching the threshold our own winter instrument
  /// arrived at independently (`feedStaleThresholdHours: 6`). JMA rewrites a
  /// prefecture's warning document many times a day in active weather; six
  /// hours of silence is already anomalous, and the documents this default was
  /// chosen against were **eighty days** old.
  ///
  /// Pass `Duration.zero` to have every read flagged, or a very large duration
  /// to opt out of the notice entirely (the fact remains readable through
  /// [JmaFeedSnapshot] via [parseJmaFeed]).
  final Duration staleFeedThreshold;

  /// Age at or beyond which the feed is reported as a **possible path
  /// retirement** rather than merely stale.
  ///
  /// See [kJmaPathRetirementEventClass] for why this is a different message
  /// and not just a bigger number: the 0.5.0 stale notice fired correctly for
  /// 87 days and nothing moved, because it named the wrong cause.
  final Duration pathRetirementThreshold;

  /// Whether [init] has been called.
  bool _initialized = false;

  JmaAdvisoryProvider({
    this.warningJsonBaseUrl = kJmaWarningJsonBaseUrl,
    this.userAgent =
        '(sngnav-class app, https://github.com/aki1770-del/sngnav)',
    this.staleFeedThreshold = kJmaDefaultStaleFeedThreshold,
    this.pathRetirementThreshold = kJmaDefaultPathRetirementThreshold,
    http.Client? client,
    DateTime Function()? now,
  }) : _http = client ?? http.Client(),
       _now = now ?? DateTime.now;

  /// Releases the underlying HTTP client. Safe to call once after the
  /// provider's last fetch.
  void close() => _http.close();

  /// Snapshot semantics: read immediately after awaiting the corresponding
  /// fetch on this instance. `null` means "not stale, or not measured" — never
  /// proof of freshness.
  @override
  AdvisoryFeedStaleness? get feedStaleness => _feedStaleness;

  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

  @override
  Future<void> init() async {
    if (userAgent.trim().isEmpty) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.jmaJapan,
        message:
            'JmaAdvisoryProvider requires a non-empty User-Agent so the '
            'publisher can reach the integrator if a request misbehaves.',
      );
    }
    _initialized = true;
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.jmaJapan,
        message:
            'JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint called before '
            'init(); the AdvisoryProvider contract requires init exactly '
            'once before any fetch.',
      );
    }

    // Snapshot semantics: this query's answer only. A stale reading from a
    // previous point must not survive into this one.
    _feedStaleness = null;

    final prefectureCodes = prefectureCodesForPoint(
      latitude: latitude,
      longitude: longitude,
    );
    if (prefectureCodes.isEmpty) {
      // The point is outside the bounding-box catalogue this adapter ships
      // (13 of the 58 offices JMA publishes).
      //
      // ⚑ This branch used to `return const <Advisory>[]` — THE SAME VALUE
      // returned for a covered prefecture, fetched successfully, with no
      // warnings in force. For 45 of 58 offices, "we do not cover this place"
      // and "nothing is wrong" were byte-identical, and a driver in a Nagano
      // blizzard was told the road was clear.
      //
      // The comment that stood here justified the empty list by saying the
      // aggregator's other providers "(e.g. NWS)" cover points outside the
      // catalog. That is false for Japan and was never measured:
      // `condition_aggregator_nws` wraps NOAA/NWS (United States),
      // Digitraffic is Finland, MET Norway is Norway. No sibling provider
      // covers those 45 offices — the empty list was her whole answer.
      //
      // So the absence is now SPOKEN, in-band, as the fourth member of the
      // honest-absence family. There is no error channel available here: no
      // fetch failed, because none could be attempted, so an exception would
      // be a lie about what happened. The notice is `minor`, carries no
      // 警報 / 注意報 suffix, and can never be graded as a hazard.
      return <Advisory>[
        buildOutsideCoverageNotice(latitude: latitude, longitude: longitude),
      ];
    }

    // Border zones: the catalogued bounding boxes are crude rectangles
    // that overlap along every shared border, so a point can fall inside
    // MORE THAN ONE prefecture box. Fetch EVERY containing prefecture
    // concurrently and surface the deduplicated union of their in-force
    // warnings — the conservative (over-warn) handling of border
    // ambiguity: a border driver never misses a neighbouring prefecture's
    // warning because the resolver guessed a single side. An interior
    // point has exactly one containing box, so this is a single fetch.

    // Every per-prefecture fetch — interior single fetch and each border
    // sibling alike — uses the SINGLE [kJmaFetchWallClockBudget] (30 s) as its
    // per-request timeout. There is deliberately NO shorter border budget: a
    // shorter cap would time out HER OWN slow-but-valid warning arriving late
    // on a marginal snow-link at a border — the near side answering a real
    // 大雪警報 on a 10–30 s link while the other containing prefecture answers
    // fast-empty — turning a real warning into a captured failure → empty union
    // + a failure → incomplete-read throw → she gets NOTHING. Per-prefecture
    // isolation (each [_fetchPrefecture] always resolves to a captured result)
    // already stops a hung sibling from blocking or discarding a fast sibling's
    // success; the only cost of the single budget is latency — a hung border
    // neighbour can make the union take up to the budget before it returns
    // (carrying the in-band incomplete-read notice). That latency is preferred
    // over ever dropping HER own slow-but-valid warning.

    final batch = Future.wait(<Future<_PrefectureFetchResult>>[
      for (final code in prefectureCodes) _fetchPrefecture(code),
    ]);

    // Each per-prefecture fetch ALWAYS RESOLVES to a captured result (it
    // carries its OWN per-request timeout + a broad catch — see
    // [_fetchPrefecture]), so `Future.wait` never blocks indefinitely on one
    // hung sibling and never has a sibling throw into it: a successful
    // sibling's warnings survive even if another endpoint hangs or errors. A
    // hung sibling self-bounds at the per-request budget, so the worst-case
    // border latency is that budget (bounded, and not multiplied by the number
    // of siblings — the fetches run concurrently). A slow-but-valid warning
    // arriving before the budget is in the returned union; nothing valid is
    // dropped.
    //
    // The batch-level timeout below is only a BACKSTOP for the theoretical
    // case where the combinator machinery itself stalls; in normal operation
    // each per-request timeout fires first and this is never reached. No
    // single `uri` is meaningful for a backstop that spans every containing
    // prefecture, so it names the prefecture codes instead (the per-request
    // and all-failed paths DO carry a uri).
    final results = await batch.timeout(
      kJmaFetchWallClockBudget,
      onTimeout: () {
        final seconds = kJmaFetchWallClockBudget.inSeconds;
        throw JmaAdvisoryFetchException(
          'Wall-clock backstop $seconds seconds exhausted before the '
          'prefecture fetch batch (${prefectureCodes.join(', ')}) '
          'completed.',
        );
      },
    );

    // Partial-failure policy (conservative — over-warn on resolution; a
    // partial read is always SIGNALLED, never silently presented as complete).
    // The signal invariant is UNCONDITIONAL: whenever a containing border
    // prefecture was not successfully checked, the caller (and the aggregator)
    // ALWAYS learns it — either by a thrown exception (the aggregator records a
    // providerError) or, when warnings ARE returned, by an in-band
    // incomplete-read notice in the returned list. (The package guarantees the
    // CALLER learns; whether the minor-severity notice is rendered to the
    // driver is the integrator's rendering choice.) (Honest bound: a warning
    // held by an UNREACHABLE prefecture cannot be surfaced — only flagged.)
    //   * collect the union of EVERY prefecture that SUCCEEDED — a warning
    //     we successfully fetched is NEVER withheld because a sibling fetch
    //     failed;
    //   * if EVERY prefecture fetch failed, throw (preserving the first
    //     failure's shape: uri / statusCode / message);
    //   * if the union is EMPTY but at least one containing prefecture
    //     FAILED, throw an incomplete-read exception rather than return [] —
    //     an empty list would be a FALSE 'no warnings' all-clear for a
    //     border where the unreachable prefecture could hold an active
    //     大雪警報. We cannot surface what we could not fetch, so the
    //     least-bad option is to declare the read incomplete;
    //   * if the union is NON-empty AND at least one containing prefecture
    //     FAILED, return the real warnings PLUS a synthetic, clearly-marked,
    //     LOW-severity incomplete-read notice naming the unreachable
    //     prefecture(s). Previously the captured failure was silently
    //     discarded here, so a partial border read landed as a COMPLETE,
    //     fully-successful result with no staleness signal — a silent
    //     under-warn at the exact scenario this border-union exists for.
    final merged = <Advisory>[];
    JmaAdvisoryFetchException? firstFailure;
    final failedPrefectureCodes = <String>[];
    var anySuccess = false;
    for (final r in results) {
      final failure = r.failure;
      if (failure != null) {
        firstFailure ??= failure;
        // Results are in `prefectureCodes` (catalog) order, so the collected
        // failed codes are deterministic — the notice names them in a stable
        // order.
        failedPrefectureCodes.add(r.prefectureCode);
        continue;
      }
      anySuccess = true;
      merged.addAll(r.advisories);
    }

    final deduped = mergeDedupedAdvisories(merged);

    if (!anySuccess) {
      // Every containing prefecture failed.
      throw firstFailure ??
          const JmaAdvisoryFetchException(
            'All prefecture fetches failed with no recorded cause.',
          );
    }

    if (deduped.isEmpty && firstFailure != null) {
      // At least one prefecture succeeded-EMPTY and at least one FAILED: the
      // union is empty but the read is INCOMPLETE. Returning [] would be a
      // false all-clear; surface the incomplete read so the integrator
      // treats it as 'could not fully determine', not 'all clear'. (Nothing
      // to return on this path, so throwing is correct — the non-empty case
      // below carries the in-band notice instead.)
      throw JmaAdvisoryFetchException(
        'Incomplete border read for prefectures '
        '(${prefectureCodes.join(', ')}): a containing prefecture fetch '
        'failed and the reachable prefecture(s) reported no in-force '
        'surfaced warning, so the result cannot be presented as an '
        'all-clear.',
        uri: firstFailure.uri,
        statusCode: firstFailure.statusCode,
      );
    }

    // FEED-LIVENESS. Every prefecture that ANSWERED is checked against its own
    // document age. This is deliberately independent of whether `deduped` is
    // empty: the two failure shapes of a frozen feed are (a) it keeps serving a
    // warning that ended months ago, and (b) it serves nothing, which reads as
    // a clear road. (b) is the worse one and it is invisible in an empty list,
    // so the notice must be able to be the ONLY thing returned.
    final staleCodes = <String>[];
    Duration worstAge = Duration.zero;
    String? worstCode;
    DateTime? worstDocumentTime;
    for (final r in results) {
      final snap = r.snapshot;
      if (snap == null) continue; // failed fetch — already handled above
      if (!snap.isStaleAt(_now(), staleFeedThreshold)) continue;
      staleCodes.add(r.prefectureCode);
      final age = snap.ageAt(_now());
      if (age != null && age > worstAge) {
        worstAge = age;
        worstCode = r.prefectureCode;
        worstDocumentTime = snap.reportDateTime;
      }
    }
    // The aggregator's channel, distinct from the in-band notice built below.
    if (staleCodes.isNotEmpty) {
      final days = worstAge.inDays;
      final hours = worstAge.inHours;
      _feedStaleness = AdvisoryFeedStaleness(
        source: AdvisorySource.jmaJapan,
        documentTime: worstDocumentTime,
        age: worstAge,
        detail:
            'JMA warning document for '
            '${staleCodes.join(', ')} last written '
            '${days >= 1 ? '$days d' : '$hours h'} ago; exceeds the '
            '${staleFeedThreshold.inHours} h threshold this adapter owns. '
            'Any "no warnings" from this read is NOT evidence of a calm road.',
      );
    }
    // Past the retirement threshold the message CHANGES, not just its
    // magnitude: "this configured path may no longer be served" points at a
    // one-line fix, where "the data is old" points at waiting. That
    // distinction is the whole reason this branch exists — see
    // [kJmaPathRetirementEventClass].
    final Advisory? staleNotice;
    if (staleCodes.isEmpty) {
      staleNotice = null;
    } else if (worstAge >= pathRetirementThreshold && worstCode != null) {
      staleNotice = buildPathRetirementNotice(
        prefectureCode: worstCode,
        age: worstAge,
        sourceUrl: warningJsonBaseUrl,
      );
    } else {
      staleNotice = buildStaleFeedNotice(
        prefectureCodes: staleCodes,
        age: worstAge,
        asOf: _now(),
      );
    }

    if (failedPrefectureCodes.isNotEmpty) {
      // Non-empty union with at least one unreachable containing prefecture:
      // return the real warnings AND a synthetic incomplete-read notice so the
      // partial read is never presented as complete. (The empty-union case
      // threw above, so `deduped` is non-empty here.) The notice carries the
      // lowest severity + a distinct event identity, so it cannot masquerade
      // as — or be deduped against — a real warning (see
      // [buildIncompleteReadNotice]).
      return <Advisory>[
        ...deduped,
        buildIncompleteReadNotice(failedPrefectureCodes),
        if (staleNotice != null) staleNotice,
      ];
    }

    if (staleNotice != null) {
      return <Advisory>[...deduped, staleNotice];
    }

    return deduped;
  }

  /// Fetches + parses a single prefecture's warning JSON, ALWAYS RESOLVING
  /// to a captured [_PrefectureFetchResult] — it NEVER throws into the
  /// concurrent [Future.wait] batch. Two guards make this total, so a hung
  /// or malformed sibling can never discard a successful sibling's warnings:
  ///   * an OWN per-request `.timeout([kJmaFetchWallClockBudget])` whose
  ///     onTimeout is converted (by the catch below) to a captured FAILURE, so
  ///     one hung endpoint self-bounds at the per-request budget instead of
  ///     blocking the whole `Future.wait` (which only resolves once EVERY
  ///     sibling resolves). The SAME budget is used for an interior single
  ///     fetch and for every border sibling — there is deliberately no shorter
  ///     border budget, which would only time out HER OWN slow-but-valid
  ///     marginal-link warning into a false 'unavailable';
  ///   * a broad `catch (Object)` so even a non-[JmaAdvisoryFetchException]
  ///     (e.g. a raw `FormatException` escaping `utf8.decode` of malformed
  ///     bytes) is captured here rather than escaping into the batch.
  /// The captured result carries the [prefectureCode] (so the non-empty-union
  /// path can name an unreachable prefecture in the in-band incomplete-read
  /// notice) and the failure preserves the prefecture's `uri` (so the
  /// all-failed / incomplete-read rethrow carries a meaningful source URL).
  Future<_PrefectureFetchResult> _fetchPrefecture(String prefectureCode) async {
    final uri = Uri.parse('$warningJsonBaseUrl$prefectureCode.json');
    try {
      final snapshot = await _fetchAndParse(uri, prefectureCode).timeout(
        kJmaFetchWallClockBudget,
        onTimeout: () {
          final seconds = kJmaFetchWallClockBudget.inSeconds;
          // The throw is local to this method — the catch below converts it
          // to a captured FAILURE, so it never reaches `Future.wait`.
          throw JmaAdvisoryFetchException(
            'Per-request budget $seconds seconds exhausted before the '
            'prefecture $prefectureCode warning JSON fetch completed.',
            uri: uri,
          );
        },
      );
      return _PrefectureFetchResult.success(prefectureCode, snapshot);
    } on JmaAdvisoryFetchException catch (e) {
      return _PrefectureFetchResult.failure(prefectureCode, e);
    } catch (e) {
      // Broaden beyond JmaAdvisoryFetchException so a raw FormatException
      // (from utf8.decode of malformed bytes) or any other unexpected throw
      // is captured here rather than escaping into Future.wait and
      // discarding a successfully-fetched sibling's warnings.
      return _PrefectureFetchResult.failure(
        prefectureCode,
        JmaAdvisoryFetchException(
          'Prefecture $prefectureCode fetch failed: $e',
          uri: uri,
        ),
      );
    }
  }

  Future<JmaFeedSnapshot> _fetchAndParse(Uri uri, String prefectureCode) async {
    final body = await _httpGet(uri, kJmaWarningJsonMaxBytes);
    try {
      return parseJmaR8Feed(body, prefectureCode: prefectureCode);
    } on FormatException catch (e) {
      throw JmaAdvisoryFetchException(
        'JMA warning JSON parse failed: $e',
        uri: uri,
      );
    }
  }

  Future<String> _httpGet(Uri uri, int maxBytes) async {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': 'application/json',
    };
    http.Response response;
    try {
      response = await _http.get(uri, headers: headers);
    } on SocketException catch (e) {
      throw JmaAdvisoryFetchException(
        'Transport failure contacting JMA: $e',
        uri: uri,
      );
    } catch (e) {
      throw JmaAdvisoryFetchException(
        'Transport failure contacting JMA: $e',
        uri: uri,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JmaAdvisoryFetchException(
        'JMA returned non-2xx',
        uri: uri,
        statusCode: response.statusCode,
      );
    }
    if (response.bodyBytes.length > maxBytes) {
      throw JmaAdvisoryFetchException(
        'JMA response exceeded $maxBytes-byte cap '
        '(${response.bodyBytes.length} bytes received).',
        uri: uri,
      );
    }
    // The warning JSON is utf-8. `response.body` defaults to latin-1
    // unless the Content-Type carries an explicit charset; explicitly
    // decode utf-8 to preserve JA characters across HTTP layers that
    // strip the charset hint.
    return utf8.decode(response.bodyBytes, allowMalformed: false);
  }
}

/// Outcome of one prefecture fetch within a (possibly multi-prefecture)
/// border batch: either the parsed [advisories] (success) or the captured
/// [failure]. Exactly one is meaningful — [failure] is null on success,
/// and [advisories] is empty on failure. The [prefectureCode] is carried on
/// BOTH outcomes so a captured FAILURE can be attributed to a named
/// prefecture in the in-band incomplete-read notice (the failing prefecture's
/// source URL is also on `failure.uri`).
class _PrefectureFetchResult {
  final String prefectureCode;
  final List<Advisory> advisories;
  final JmaAdvisoryFetchException? failure;

  /// The whole document read, including its own `reportDatetime` — carried
  /// even when [advisories] is empty, which is the entire point: an empty
  /// warning list from an 81-day-old document must not be indistinguishable
  /// from an empty list from a document written this hour.
  final JmaFeedSnapshot? snapshot;

  const _PrefectureFetchResult._(
    this.prefectureCode,
    this.advisories,
    this.failure,
    this.snapshot,
  );

  factory _PrefectureFetchResult.success(
    String prefectureCode,
    JmaFeedSnapshot snapshot,
  ) => _PrefectureFetchResult._(
    prefectureCode,
    snapshot.advisories,
    null,
    snapshot,
  );

  factory _PrefectureFetchResult.failure(
    String prefectureCode,
    JmaAdvisoryFetchException failure,
  ) => _PrefectureFetchResult._(
    prefectureCode,
    const <Advisory>[],
    failure,
    null,
  );
}

/// Merges advisories collected across one-or-more border prefectures into
/// the deduplicated union, preserving first-seen order.
///
/// Two advisories are treated as **the same warning** iff every identity
/// field matches — `source`, `eventClass`, `severity`, `certainty`,
/// `urgency`, `areaDescription`, `effective`, `expires`, `headline`,
/// `description` (the full [Advisory] value identity). The key is
/// deliberately **maximal** so the union NEVER collapses two genuinely
/// different warnings: a `大雪警報` labelled `Akita` and a `大雪警報`
/// labelled `Yamagata` differ in `areaDescription` and therefore **both
/// survive** (over-warn — a border driver sees both prefectures' warnings).
/// Only a byte-identical record appearing twice is collapsed to a single
/// entry, so the driver is never shown the literally-same warning line
/// twice.
///
/// (With the current adapter, `areaDescription` is the distinct prefecture
/// label, so two distinct prefectures cannot produce an identical record;
/// the dedup is a conservative safety-net against any future path — or a
/// repeated code — that yields a true duplicate.)
List<Advisory> mergeDedupedAdvisories(List<Advisory> advisories) {
  final seen = <String>{};
  final out = <Advisory>[];
  for (final advisory in advisories) {
    if (seen.add(_advisoryIdentityKey(advisory))) {
      out.add(advisory);
    }
  }
  return out;
}

/// Stable identity key for [mergeDedupedAdvisories] — the full [Advisory]
/// value identity joined on a NUL (`\u0000`) separator. The JMA snow
/// headline / event-name / prefecture-label text never contains a literal
/// NUL, so in practice distinct field tuples do not collide. (Theoretical
/// exception: JSON can *encode* a `\u0000` escape, so a NUL inside one field
/// could in principle shift the boundary — accepted here because the live
/// JMA warning text fields are human-readable Japanese that never carry one,
/// and a false collision would only ever drop a genuine byte-duplicate.)
String _advisoryIdentityKey(Advisory a) => <String>[
  a.source.name,
  a.eventClass,
  a.severity.name,
  a.certainty.name,
  a.urgency.name,
  a.areaDescription,
  a.effective?.toIso8601String() ?? '',
  a.expires?.toIso8601String() ?? '',
  a.headline,
  a.description,
].join('\u0000');
