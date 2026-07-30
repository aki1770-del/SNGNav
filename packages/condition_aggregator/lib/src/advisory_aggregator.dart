/// AdvisoryAggregator — multi-source advisory aggregation primitive.
///
/// Fans a single point query out across registered [AdvisoryProvider]s,
/// returning the sealed [AdvisoryLookup]: the merged list of active advisories
/// **plus the truth about which sources could not be read**.
///
/// ## Read this before you trust an empty list
///
/// A per-provider failure is recorded and the aggregator continues with the
/// surviving providers. Getting advisories from N−1 providers when the Nth is
/// down beats getting none. **But that is only half of honest.**
///
/// The other half: when every provider fails, the advisory list in hand is
/// **empty** — the exact same value it holds when the sky is genuinely clear
/// and no advisory is in force. Those are different facts. One of them is a
/// weather-service outage during a blizzard.
///
/// Up to 0.0.7, the only way to tell them apart was to remember to read
/// `providerErrors` — and a field you *can* ignore *will* be ignored. That is
/// precisely how this shipped. 0.0.8 added the question you can no longer
/// skip cheaply (`canAssertNoAdvisory`, `fold`, `requireCompleteLookup`)
/// without breaking the return type. Since 0.1.0 the return type is the
/// sealed [AdvisoryLookup] and an exhaustive `switch` refuses a caller who
/// never handled "could not look" — the **compiler** asks the question for
/// you.
library;

import 'dart:async' show TimeoutException;

import 'advisory.dart';
import 'advisory_absence.dart';
import 'advisory_coverage.dart';
import 'advisory_lookup.dart';
import 'advisory_provider.dart';

/// The 0.0.8 result object, retained for source compatibility.
///
/// Through 0.0.8, `AdvisoryAggregator.fetchActiveAdvisoriesAtPoint` returned
/// this type; since 0.1.0 it returns the sealed [AdvisoryLookup]. This class
/// remains — with the full 0.0.8 surface: [canAssertNoAdvisory], [seen],
/// [unreachable], [isUnavailable], [fold], [requireCompleteLookup] — so that
/// hand-built results (test fakes, fixtures, adapters' own aggregation shims)
/// written against 0.0.8 keep compiling and keep their meaning.
///
/// ## The asymmetry (caution-add-only)
///
/// A hazard **seen** is a hazard **real**, even when some source was
/// unreachable — act on [advisories] regardless. But *"no advisory is in
/// force"* is a claim about **completeness**, and you may only make it when the
/// lookup was complete.
///
/// Positive evidence fires on partial knowledge. A negative conclusion requires
/// whole knowledge. That asymmetry is what lets a system be honest without
/// crying wolf.
class AdvisoryAggregateResult {
  /// All advisories from providers that responded successfully.
  ///
  /// **Safe to act on.** Not the whole picture unless [canAssertNoAdvisory].
  ///
  /// An **empty** list here is NOT an all-clear on its own — it is also what you
  /// get when every source was unreachable. Gate any "nothing is in force"
  /// message on [canAssertNoAdvisory].
  final List<Advisory> advisories;

  /// One entry per provider that errored.
  ///
  /// Reading this is optional and therefore easy to skip — which is why
  /// [canAssertNoAdvisory] exists. Prefer it.
  final List<AdvisoryProviderError> providerErrors;

  /// How many sources were asked, when known.
  ///
  /// It is optional only so that this constructor stays source-compatible with
  /// 0.0.7 callers (test fakes, etc.).
  ///
  /// **If you construct this object yourself, pass it.** When it is `null` we do
  /// not know whether every source answered, so [canAssertNoAdvisory] is `false`
  /// — we will not claim completeness on your behalf.
  final int? sourcesQueried;

  const AdvisoryAggregateResult({
    required this.advisories,
    required this.providerErrors,
    this.sourcesQueried,
  });

  /// `true` only when **every source answered** — the one condition under which
  /// you may honestly tell a driver *"no advisory is in force."*
  ///
  /// It is `false` whenever any source could not be reached, and `false` when no
  /// source was asked at all. Silence from a source you could not reach is not
  /// an all-clear; it is a gap.
  ///
  /// If this is `false`, tell her *what you do not know*. Do not tell her
  /// nothing, and never tell her it is clear.
  bool get canAssertNoAdvisory {
    if (providerErrors.isNotEmpty) return false;
    final n = sourcesQueried;
    if (n == null) return false; // unknown provenance — we will not claim it
    return n > 0; // zero sources asked is not an all-clear either
  }

  /// The sources we could not read, and why — typed in
  /// [AdvisoryProviderError.reason], so the reason survives into whatever
  /// language the driver reads.
  ///
  /// Same list as [providerErrors]; same name as [AdvisoryLookup.unreachable],
  /// so the migration is a rename you can make today.
  List<AdvisoryProviderError> get unreachable => providerErrors;

  /// What we actually saw. Same list as [advisories]; same name as
  /// [AdvisoryLookup.seen].
  List<Advisory> get seen => advisories;

  /// `true` when **no source answered** — we did not look, and we know nothing.
  ///
  /// This is not "clear". Show the driver that the feed is down. She can decide
  /// what to do with a gap; she can decide nothing about a silence she was never
  /// told about.
  bool get isUnavailable {
    final n = sourcesQueried;
    if (n == null) return false; // unknown provenance — cannot say
    return n - providerErrors.length <= 0;
  }

  /// Handle every case, or do not compile.
  ///
  /// The three callbacks are `required`, so — unlike a field you can skip —
  /// `fold` will not let you forget the case where we could not look. It is the
  /// same fold as [AdvisoryLookup.fold], on the 0.0.8 result shape.
  ///
  /// ```dart
  /// // oracle:placeholders r
  /// final banner = r.fold(
  ///   complete: (a) => a.isEmpty ? '警報なし' : a.first.headline,
  ///   partial: (seen, down) => seen.isEmpty
  ///       ? '一部の気象情報を取得できません'   // NOT "no advisory"
  ///       : seen.first.headline,
  ///   unavailable: (down) => '気象情報を取得できません',  // NOT "clear"
  /// );
  /// ```
  ///
  /// * [complete] — every source answered. An empty list here genuinely means
  ///   *no advisory in force*. This is the only shape in which that is true.
  /// * [partial] — act on what was seen; you may **not** conclude "nothing is in
  ///   force", because the warning you are missing may be in the source that did
  ///   not answer.
  /// * [unavailable] — we did not look. Not clear.
  T fold<T>({
    required T Function(List<Advisory> advisories) complete,
    required T Function(
      List<Advisory> seen,
      List<AdvisoryProviderError> unreachable,
    )
    partial,
    required T Function(List<AdvisoryProviderError> unreachable) unavailable,
  }) {
    if (canAssertNoAdvisory) return complete(advisories);
    if (isUnavailable) return unavailable(providerErrors);
    return partial(advisories, providerErrors);
  }

  /// The loud stop, opt-in: throws [AdvisoryLookupIncompleteException] unless
  /// every source answered.
  ///
  /// Call this before any code path that would tell a driver the road is clear.
  /// Nothing throws it unless you ask — 0.0.7-shaped callers are untouched.
  ///
  /// A stop with no restart is a wall, not a loom, so the exception says what
  /// broke, why we refuse to guess, and the way forward.
  void requireCompleteLookup() {
    if (canAssertNoAdvisory) return;
    final down = providerErrors
        .map((e) => '${e.source.name} (${e.reason.name})')
        .join(', ');
    throw AdvisoryLookupIncompleteException(
      unreachable: providerErrors,
      message: providerErrors.isEmpty
          ? 'No advisory source was asked (sourcesQueried='
                '${sourcesQueried ?? "unknown"}), so the empty advisory list is '
                'not an all-clear — it is an absence of any lookup. We will not '
                'guess. Forward: register at least one AdvisoryProvider, or '
                'handle this and tell the driver the advisory feed is '
                'unavailable rather than clear.'
          : 'Could not read $down, so the advisory list may be missing a '
                'warning that is really in force. We will not report an '
                'all-clear we did not earn. Forward: act on the advisories you '
                'did get (a hazard seen is a hazard real), tell the driver which '
                'sources are down instead of telling her it is clear, or switch '
                'on the sealed AdvisoryLookup returned by '
                'AdvisoryAggregator.fetchActiveAdvisoriesAtPoint, where the '
                'compiler asks this question for you.',
    );
  }
}

/// Multi-source aggregator. Holds N providers; init's them all; queries
/// them all on each `fetch…` call.
class AdvisoryAggregator {
  final List<AdvisoryProvider> _providers;
  bool _initialized = false;

  /// Refuse to call a lookup complete while any consulted provider's coverage
  /// is **unknown**. Default `false` — today's behaviour, unchanged.
  ///
  /// The sealed [AdvisoryLookup] closes the *failure* path: a provider that
  /// throws can no longer be mistaken for a clear sky. It does not close the
  /// **silent-coverage-gap** path: a provider that returns an empty list
  /// *without failing*, because the point is outside the area it ships, is
  /// counted as asked-and-answered though it never sent a request. See
  /// [AdvisoryCoverage].
  ///
  /// An adapter that implements [AdvisoryCoverage] answers that question for
  /// itself and is handled precisely, whatever this flag says. This flag is for
  /// the rest: set it `true` and any provider whose coverage is undeclared
  /// contributes an [AdvisoryUnavailableReason.coverageUndeclared] failure, so
  /// the lookup can never be [AdvisoryLookupComplete] while we cannot prove we
  /// looked.
  ///
  /// **It is opt-in for a reason, and the reason is not comfort.** No adapter
  /// published today declares coverage, so with `true` a lookup will be
  /// `Partial` or `Unavailable` every time — which is the truth, and is also
  /// useless as a default: making it the default would put
  /// [AdvisoryLookupComplete] out of reach for every existing consumer, a
  /// reversal of this release's central type rather than a guard on it.
  /// Advisories seen are still returned and still safe to act on
  /// (caution-add-only) — what is withheld is only the all-clear.
  final bool requireDeclaredCoverage;

  AdvisoryAggregator({
    required List<AdvisoryProvider> providers,
    this.requireDeclaredCoverage = false,
  }) : _providers = List<AdvisoryProvider>.unmodifiable(providers);

  /// Read-only view of registered providers.
  List<AdvisoryProvider> get providers => _providers;

  /// True once [init] has completed for every provider.
  bool get isInitialized => _initialized;

  /// Initializes all registered providers. Failure of any one provider
  /// raises [AdvisoryProviderInitException] (adapter's own subclass
  /// allowed); the aggregator does NOT swallow init failures since init
  /// is the canonical surface for surfacing schema-drift / configuration
  /// errors before any caller depends on the broken provider.
  ///
  /// Idempotent: calling twice is a no-op after the first success.
  Future<void> init() async {
    if (_initialized) return;
    for (final p in _providers) {
      await p.init();
    }
    _initialized = true;
  }

  /// Fans the point query out across all registered providers.
  ///
  /// Per-provider transport / parse failures are caught and carried in the
  /// returned [AdvisoryLookup]'s failures; surviving providers' advisories
  /// appear in [AdvisoryLookup.seen]. Init failures are NOT caught here (they
  /// fire from [init], which the caller invokes explicitly).
  ///
  /// The whole point of the sealed type: an empty advisory list is only
  /// "no advisory in force" when the lookup is [AdvisoryLookupComplete] —
  /// which requires that at least one source was asked and every source
  /// answered. An aggregator with **zero registered providers** returns
  /// [AdvisoryLookupUnavailable]: a lookup that consulted nothing cannot
  /// claim completeness (caution-add-only; same verdict 0.0.8 gave that
  /// case via `canAssertNoAdvisory == false`).
  ///
  /// **What "every source answered" can and cannot see.** It sees a provider
  /// that *failed*. It does not, on its own, see a provider that returned an
  /// empty list *without failing* because the point lies outside the area it
  /// ships — that provider is counted as an answer though it never sent a
  /// request. A provider implementing [AdvisoryCoverage] is handled precisely:
  /// declared out-of-coverage means **not asked and not counted**, and when no
  /// provider covers the point the result is [AdvisoryLookupUnavailable] with
  /// [AdvisoryUnavailableReason.outOfCoverage] — a gap, never a clear sky. For
  /// providers that declare nothing, set [requireDeclaredCoverage] to refuse
  /// completeness rather than assume it.
  ///
  /// Throws [StateError] if called before [init].
  Future<AdvisoryLookup> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw StateError(
        'AdvisoryAggregator.fetchActiveAdvisoriesAtPoint called before init()',
      );
    }
    if (_providers.isEmpty) {
      // We did not look — nothing was there to ask. This is NOT clear.
      return const AdvisoryLookupUnavailable([]);
    }
    final advisories = <Advisory>[];
    final failures = <AdvisorySourceFailure>[];
    // Providers that declared, for THIS point, that they cover nothing here.
    // They are not failures — they have honestly nothing to say — so they leave
    // the completeness denominator instead of contributing a silent "answer".
    final outOfCoverage = <AdvisorySourceFailure>[];
    for (final p in _providers) {
      if (p is AdvisoryCoverage &&
          !(p as AdvisoryCoverage).coversPoint(
            latitude: latitude,
            longitude: longitude,
          )) {
        outOfCoverage.add(
          AdvisorySourceFailure(
            source: p.source,
            reason: AdvisoryUnavailableReason.outOfCoverage,
          ),
        );
        continue;
      }
      // Coverage unknown and the caller asked us not to assume it. We still ASK
      // — a hazard seen is a hazard real — but the answer cannot buy an
      // all-clear, because an empty list from an adapter that may never have
      // looked is exactly the silence this package exists to refuse.
      final undeclared = requireDeclaredCoverage && p is! AdvisoryCoverage;
      try {
        final found = await p.fetchActiveAdvisoriesAtPoint(
          latitude: latitude,
          longitude: longitude,
        );
        advisories.addAll(found);
        if (undeclared) {
          failures.add(
            AdvisorySourceFailure(
              source: p.source,
              reason: AdvisoryUnavailableReason.coverageUndeclared,
            ),
          );
        }
      } on Object catch (e) {
        // The lamp stays lit. Up to 0.0.7 this caught the adapter's honest
        // refusal, flattened it to a String, filed it in a `providerErrors` list
        // that NOTHING in the tree ever read, and returned the advisories list
        // anyway — so a JMA outage in a blizzard reached the integrator as `[]`,
        // the same value as a clear night. The failure is now part of the RESULT
        // TYPE and cannot be dropped on the floor.
        failures.add(
          AdvisorySourceFailure(
            source: p.source,
            reason: classifyAdvisoryFailure(e),
            cause: e,
          ),
        );
      }
    }

    // Every provider declared it covers nothing here. Nobody was asked, so
    // there is no all-clear to give — the same verdict as zero registered
    // providers, and the case a hand-drawn coverage box turns into a fabricated
    // clear (the founding sngnav-app defect: a Tokyo point where JMA ships no
    // catalog and NWS is a different hemisphere).
    final asked = _providers.length - outOfCoverage.length;
    if (asked == 0) {
      return AdvisoryLookupUnavailable(outOfCoverage);
    }

    // The whole point of the type: an empty list is only "no advisory in force"
    // when every source actually answered.
    if (failures.isEmpty) {
      return AdvisoryLookupComplete(advisories);
    }
    // `advisories.isEmpty` is a strict refinement, not a behaviour change: when
    // every failure is a THROWN one, a provider that failed contributed nothing,
    // so `failures.length == asked` already implied an empty list. It becomes
    // load-bearing only for the coverageUndeclared failure, which rides an
    // answer — and a hazard seen must never be demoted to "we know nothing".
    if (advisories.isEmpty && failures.length == asked) {
      // We did not look. We know nothing. This is NOT clear.
      return AdvisoryLookupUnavailable(failures);
    }
    return AdvisoryLookupPartial(advisories: advisories, unreachable: failures);
  }
}

/// Best-effort classification of an adapter failure into a reason a driver can
/// be told about.
///
/// It is deliberately conservative: anything it cannot place becomes
/// [AdvisoryUnavailableReason.unclassified] rather than being guessed into a
/// specific reason. A wrong reason is worse than an honest "we don't know why" —
/// telling her "the network is down" when the source actually refused us sends
/// her looking for the wrong problem. In particular, a bare `StateError` is NOT
/// assumed to mean "not initialised": only the typed
/// [AdvisoryProviderInitException] earns that reason.
///
/// Typed exceptions are classified before message text, because a type is a
/// contract and a message is prose: `TimeoutException` → `timedOut`,
/// `FormatException` → `unparseable`, [AdvisoryProviderInitException] →
/// `notInitialised`, and the `dart:io` / `package:http` transport family
/// (matched by type name — this package is pure Dart and must stay web-safe)
/// → `networkUnreachable`. Message-text heuristics then cover adapters that
/// throw untyped errors.
///
/// Adapters SHOULD throw a typed exception carrying their own reason; this
/// exists so that an adapter which does not is still not silently swallowed.
AdvisoryUnavailableReason classifyAdvisoryFailure(Object error) {
  // Typed contracts beat prose.
  if (error is TimeoutException) return AdvisoryUnavailableReason.timedOut;
  if (error is FormatException) return AdvisoryUnavailableReason.unparseable;
  if (error is AdvisoryProviderInitException) {
    return AdvisoryUnavailableReason.notInitialised;
  }
  // dart:io / package:http types are not importable here (pure Dart, and this
  // package must stay web-safe), so the family is matched by type name.
  final typeName = error.runtimeType.toString();
  if (typeName.contains('SocketException') ||
      typeName.contains('HandshakeException') ||
      typeName.contains('ClientException') ||
      typeName.contains('HttpException')) {
    return AdvisoryUnavailableReason.networkUnreachable;
  }
  // Message-text heuristics for untyped throws — most specific first: a source
  // that answered for part of the area. The founding case ("Incomplete border
  // read for prefectures …") arrives as an untyped Exception, falls through
  // every typed check above, and is classified here.
  final text = error.toString().toLowerCase();
  if (text.contains('incomplete') || text.contains('coverage')) {
    return AdvisoryUnavailableReason.incompleteAreaCoverage;
  }
  if (text.contains('timeout') || text.contains('timed out')) {
    return AdvisoryUnavailableReason.timedOut;
  }
  if (text.contains('socket') ||
      text.contains('network') ||
      text.contains('connection') ||
      text.contains('failed host lookup')) {
    return AdvisoryUnavailableReason.networkUnreachable;
  }
  if (text.contains('format') ||
      text.contains('parse') ||
      text.contains('unexpected')) {
    return AdvisoryUnavailableReason.unparseable;
  }
  if (text.contains('403') ||
      text.contains('401') ||
      text.contains('429') ||
      text.contains('refused')) {
    return AdvisoryUnavailableReason.refused;
  }
  return AdvisoryUnavailableReason.unclassified;
}
