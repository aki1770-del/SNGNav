/// FROZEN FEED — a source that ANSWERS but has stopped MOVING.
///
/// ## The defect this file exists to catch
///
/// `canAssertNoAdvisory` is the one predicate in this package that gates a
/// positive all-clear. Its contract, verbatim from
/// `lib/src/advisory_aggregator.dart`:
///
/// > `true` only when **every source answered** — the one condition under which
/// > you may honestly tell a driver *"no advisory is in force."*
/// > […] If this is `false`, tell her *what you do not know*. Do not tell her
/// > nothing, and never tell her it is clear.
///
/// **Answering is exactly what a frozen feed does.** A publisher whose pipeline
/// has stalled serves HTTP 200, valid JSON, and an empty warning list, forever.
/// `providerErrors` is empty because nothing failed. `sourcesQueried` is 1
/// because the source was asked and replied. So `canAssertNoAdvisory` returns
/// `true`, `fold` takes the `complete` branch, `toLookup` returns
/// `AdvisoryLookupComplete`, `requireCompleteLookup` does not throw — and the
/// integrator renders a measured calm over a document that stopped being
/// written months ago.
///
/// The predicate is defined over **reachability**. The hazard is **recency**.
///
/// ## This is not hypothetical — it is the live state of the stack
///
/// Measured 2026-08-16 by the unit's own winter instrument
/// (`outputs/shadow-watch/records/2026-08.jsonl`, run `2026-08-16T02:07:02Z`),
/// judging the PUBLISHED packages `condition_aggregator 0.0.9` /
/// `condition_aggregator_jma 0.3.1` / `driving_weather 0.5.0` /
/// `compound_failure_advisor 0.1.2`:
///
/// * Niigata prefecture document `150000` — `reportDatetime`
///   **2026-05-26T15:45+09:00**, age **1963.37 h (81.8 days)**, zero warnings.
///   The record carries two branches and instructs that neither be quoted
///   alone: `drive` = **heightenedCaution** (`staleVisibility`,
///   `highSpeedInDegradedConditions`; unknown `visibilityReadingIsStale`);
///   `driveOnboard` = **continueDriving, empty reasons, empty unknowns**.
///   **What survives BOTH: every reason names the VISIBILITY reading's age.
///   Neither branch says one word about the advisory feed being 81 days
///   dead.** An earlier draft quoted the onboard branch alone — the more
///   dramatic one — against the record's own instruction. Caught by AAA.
/// * Akita `050000` — **2026-05-28T06:11+09:00**, age **1924.93 h**.
/// * Yamagata `060000` — **2026-05-28T09:48+09:00**, age **1921.32 h**.
///   The feeds did not freeze in lockstep, so no single "frozen at T" holds.
///
/// The instrument could only see this because it reads `reportDatetime`
/// **out of band**, straight from the JMA JSON, bypassing this interface. Its
/// own note, verbatim from the record: *"The adapter cannot express feed
/// freshness when the warning list is empty (no Advisory, so no effective
/// timestamp) — a frozen feed with zero warnings is indistinguishable from a
/// calm day."*
///
/// ## Why the per-advisory freshness machinery does not reach it
///
/// `Advisory.effective` / `stalenessAt` / `isStaleAt` already exist and are
/// correct. They are **per-advisory**. When the frozen document lists zero
/// warnings there is no `Advisory` object to hang a timestamp on, so every one
/// of them is structurally unreachable in precisely the case that matters. The
/// missing primitive is a freshness channel on the **source**, not on the event.
///
/// ## Scope
///
/// `condition_aggregator_jma 0.5.0` closes this at the JMA adapter by appending
/// an in-band stale-feed notice. That fix is real and it is not this one: it
/// protects one adapter, and an integrator who filters the minor-severity
/// notice out and then asks `canAssertNoAdvisory` still gets a measured calm.
/// Five adapter packages implement `AdvisoryProvider` on this interface — jma,
/// nws, met_norway, digitraffic, owm_road_risk. (`driving_weather` and
/// `drive_situation_fusion` consume the interface but do not implement the
/// provider contract; an earlier draft miscounted them as adapters.) The guard
/// they all share is here.
///
/// ## Where the RED proof lives — read this before quoting it
///
/// **This file cannot demonstrate the defect.** Five of its eight tests
/// reference symbols 0.0.10 introduced (`AdvisoryFeedFreshnessReporting`,
/// `AdvisoryFeedStaleness`, `staleSources`, `hasStaleSource`), so against 0.0.9
/// it does not fail — **it fails to LOAD**, which demonstrates nothing.
///
/// The re-derivable proof is `tool/red_proof/`: a reproduction written against
/// 0.0.9's symbol set only, plus `run_red_proof.sh`, which rebuilds the
/// pristine package **from the pub-cache tarball** (what an edge developer
/// actually downloads) and asserts the tests FAIL there. Verified 2026-08-16:
/// 4/4 red, exit 0.
///
/// *This note exists because the first draft claimed "proven RED 4/4 against
/// unmodified 0.0.9" while leaving nothing on disk that could reproduce it.
/// DIA caught it in audit and was right: a proof that exists only in the
/// author's session is an assertion wearing the clothes of evidence.*
///
/// Author: FSE (functional-safety-engineer). SOTIF row SOTIF-CA-001.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

/// The measured Niigata freeze, to the hour.
const kNiigataFrozenAge = Duration(hours: 1963, minutes: 22);

/// A source that is UP, ANSWERING, and DEAD.
///
/// It models the measured behaviour of `bosai/warning/data/warning/150000.json`
/// on 2026-08-16: a successful fetch, a well-formed document, zero warnings,
/// and a publisher timestamp 81 days in the past. Nothing here throws, because
/// nothing upstream failed — that is the entire difficulty.
class FrozenFeedProvider
    implements AdvisoryProvider, AdvisoryFeedFreshnessReporting {
  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

  @override
  Future<void> init() async {}

  /// The adapter ALWAYS knew this. `condition_aggregator_jma` parses
  /// `reportDatetime` out of the warning JSON and maps it to
  /// `Advisory.effective` — so on a frozen document it holds the very
  /// timestamp that proves the document is dead, and then, finding no warnings
  /// to attach it to, drops it. The defect was never missing knowledge. It was
  /// a contract with nowhere to put it.
  @override
  AdvisoryFeedStaleness? get feedStaleness => AdvisoryFeedStaleness(
    source: source,
    documentTime: DateTime.parse('2026-05-26T15:45:00+09:00'),
    age: kNiigataFrozenAge,
    detail: 'prefecture 150000; no update in 6 h publisher cadence',
  );

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => const <Advisory>[];
}

/// A legacy adapter — one of the five that have not opted in. Behaviour for
/// these MUST be byte-identical to 0.0.9, or the fix breaks working
/// integrations to score a point.
class LegacyQuietProvider implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;

  @override
  Future<void> init() async {}

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => const <Advisory>[];
}

void main() {
  late AdvisoryAggregator aggregator;

  setUp(() async {
    aggregator = AdvisoryAggregator(
      providers: <AdvisoryProvider>[FrozenFeedProvider()],
    );
    await aggregator.init();
  });

  Future<AdvisoryAggregateResult> read() =>
      aggregator.fetchActiveAdvisoriesAtPoint(
        // Niigata (54232), the station that rendered as a clear road.
        latitude: 37.893333,
        longitude: 139.018333,
      );

  test('SOTIF-CA-001 — a source whose document is 81 days old must NOT satisfy '
      'canAssertNoAdvisory', () async {
    final r = await read();

    expect(
      r.canAssertNoAdvisory,
      isFalse,
      reason:
          'The publisher answered, so providerErrors is empty and '
          'sourcesQueried is 1 — and the predicate concludes "measured '
          'calm" over a document last written ${kNiigataFrozenAge.inDays} '
          'days ago. The package doc on this getter says "never tell her it '
          'is clear"; on a frozen feed it does exactly that.',
    );
  });

  test(
    'SOTIF-CA-001 — fold() must not take the `complete` branch on a frozen feed',
    () async {
      final r = await read();

      final rendered = r.fold(
        complete: (a) => a.isEmpty ? 'ALL-CLEAR' : 'HAZARD',
        partial: (seen, down) => 'PARTIAL',
        unavailable: (down) => 'FEED-DOWN',
      );

      expect(
        rendered,
        isNot('ALL-CLEAR'),
        reason:
            'fold() is the surface this package tells integrators to prefer '
            'because it "will not let you forget the case where we could not '
            'look". A frozen feed is a case where we could not look, and fold '
            'routes it to `complete` — the branch documented as "the only '
            'shape in which [no advisory in force] is true".',
      );
    },
  );

  test(
    'SOTIF-CA-001 — requireCompleteLookup() must throw on a frozen feed',
    () async {
      final r = await read();

      expect(
        r.requireCompleteLookup,
        throwsA(isA<AdvisoryLookupIncompleteException>()),
        reason:
            'requireCompleteLookup is documented as "the loud stop" to call '
            '"before any code path that would tell a driver the road is '
            'clear". It is silent here.',
      );
    },
  );

  test('SOTIF-CA-001 — toLookup() must not return AdvisoryLookupComplete on a '
      'frozen feed', () async {
    final r = await read();

    expect(
      r.toLookup(),
      isNot(isA<AdvisoryLookupComplete>()),
      reason:
          'The sealed type exists so that "omitting the feed-was-down branch '
          'is a compile error rather than a silent all-clear". An exhaustive '
          'switch does not help when the frozen case is classified Complete.',
    );
  });

  test('SOTIF-CA-001 — the integrator can tell her WHICH source went quiet and '
      'HOW LONG ago', () async {
    final r = await read();

    // A stop with no restart is a wall, not a loom. Refusing the all-clear
    // is only half the duty; the other half is giving her something to act
    // on. She is owed what we do not know, not an apology.
    expect(r.hasStaleSource, isTrue);
    expect(r.staleSources.single.source, AdvisorySource.jmaJapan);
    expect(r.staleSources.single.age!.inDays, greaterThanOrEqualTo(81));

    final lookup = r.toLookup();
    expect(lookup, isA<AdvisoryLookupPartial>());
    expect((lookup as AdvisoryLookupPartial).staleSources, hasLength(1));

    // The Partial is reachable with an EMPTY `unreachable` list — which is
    // exactly why staleSources had to be carried onto the sealed type. An
    // integrator handed Partial-with-nothing-unreachable could not have
    // explained the state to anyone.
    expect(lookup.unreachable, isEmpty);

    expect(
      () => r.requireCompleteLookup(),
      throwsA(
        isA<AdvisoryLookupIncompleteException>().having(
          (e) => e.toString(),
          'message',
          allOf(
            contains('stopped being updated'),
            contains('2026-05-26'),
            contains('81 d old'),
          ),
        ),
      ),
      reason:
          'The message must name the document and its age, not merely refuse.',
    );
  });

  group('no cry-wolf — the fix must not fire where nothing was measured', () {
    test(
      'a LEGACY adapter that never opted in behaves exactly as 0.0.9 did',
      () async {
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[LegacyQuietProvider()],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        );

        // NONE of the five AdvisoryProvider implementations have opted in. If this assertion ever flips, the fix started manufacturing
        // doubt on a clear day — which is the same class of lie as
        // manufacturing calm, pointed the other way.
        expect(r.canAssertNoAdvisory, isTrue);
        expect(r.hasStaleSource, isFalse);
        expect(r.toLookup(), isA<AdvisoryLookupComplete>());
        expect(r.requireCompleteLookup, returnsNormally);
      },
    );

    test(
      'an opted-in adapter reporting FRESH still yields a clean all-clear',
      () async {
        final agg = AdvisoryAggregator(
          providers: <AdvisoryProvider>[_FreshReportingProvider()],
        );
        await agg.init();
        final r = await agg.fetchActiveAdvisoriesAtPoint(
          latitude: 39.7186,
          longitude: 140.1024,
        );

        expect(r.canAssertNoAdvisory, isTrue);
        expect(r.staleSources, isEmpty);
      },
    );

    test('one frozen source among several kills the all-clear for the whole '
        'lookup', () async {
      final agg = AdvisoryAggregator(
        providers: <AdvisoryProvider>[
          LegacyQuietProvider(),
          FrozenFeedProvider(),
        ],
      );
      await agg.init();
      final r = await agg.fetchActiveAdvisoriesAtPoint(
        latitude: 37.893333,
        longitude: 139.018333,
      );

      // "No advisory is in force" is a claim about completeness. One dead
      // source is enough to make it unearned, exactly as one unreachable
      // source already was.
      expect(r.canAssertNoAdvisory, isFalse);
      expect(r.staleSources, hasLength(1));
    });
  });
}

/// An opted-in adapter whose document is current.
class _FreshReportingProvider
    implements AdvisoryProvider, AdvisoryFeedFreshnessReporting {
  @override
  AdvisorySource get source => AdvisorySource.metNorway;

  @override
  Future<void> init() async {}

  @override
  AdvisoryFeedStaleness? get feedStaleness => null;

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => const <Advisory>[];
}
