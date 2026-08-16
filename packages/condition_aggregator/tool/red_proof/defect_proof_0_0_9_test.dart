/// THE RED PROOF — the frozen-feed defect, demonstrated against PRISTINE 0.0.9.
///
/// ## Why this file exists separately from `test/frozen_feed_test.dart`
///
/// `test/frozen_feed_test.dart` is the *guard*: it proves the defect is fixed,
/// and it references symbols that 0.0.10 introduced. It therefore **cannot be
/// compiled against 0.0.9 at all** — it fails to LOAD, and a load failure is
/// not a demonstration of anything.
///
/// So the sentence *"the guard was proven RED against unmodified 0.0.9"* was,
/// as first written, not re-derivable from anything left on disk. **DIA caught
/// that in audit on 2026-08-16 and it was the correct catch**: a proof that
/// exists only in the author's session is an assertion, not evidence.
///
/// This file is the repair. It uses **only the symbol set published in 0.0.9**,
/// so it compiles and runs against the pristine package, and it fails there —
/// four assertion failures, one per honesty surface. Run it with
/// `tool/red_proof/run_red_proof.sh`, which reconstructs 0.0.9 from the pub
/// cache (or from git history) and asserts that these tests **FAIL**.
///
/// A green run of this file means the defect is absent from whatever you
/// pointed it at. A red run is the point.
///
/// ## The defect
///
/// `AdvisoryAggregateResult.canAssertNoAdvisory` gates every positive
/// all-clear, and in 0.0.9 it is defined over **reachability**:
///
/// ```dart
/// if (providerErrors.isNotEmpty) return false;
/// final n = sourcesQueried;
/// if (n == null) return false;
/// return n > 0;
/// ```
///
/// A frozen publisher is reachable. It serves HTTP 200, valid JSON and an
/// empty warning list indefinitely, so nothing lands in `providerErrors` and
/// the predicate returns `true` over a document 81 days dead.
///
/// Measured live 2026-08-16: JMA `bosai/warning/data/warning/150000.json`
/// (Niigata) last written **2026-05-26T15:45+09:00** — 1963.37 h — zero
/// warnings. The unit's winter instrument served that point as
/// `continueDriving` with an empty reasons list and an empty unknowns list.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:test/test.dart';

/// A source that is UP, ANSWERING, and DEAD.
///
/// Note what it does NOT do: it does not implement any freshness-reporting
/// interface, because in 0.0.9 none exists. That absence IS the defect — the
/// adapter parses `reportDatetime` and has nowhere to put it.
class FrozenFeedProvider implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

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
        latitude: 37.893333, // Niigata (54232) — the point that rendered clear
        longitude: 139.018333,
      );

  test(
    'RED 1/4 — canAssertNoAdvisory says "measured calm" over a dead document',
    () async {
      final r = await read();
      expect(
        r.canAssertNoAdvisory,
        isFalse,
        reason:
            'FAILS ON 0.0.9. The publisher answered, so providerErrors is empty '
            'and sourcesQueried is 1. The getter whose own doc says "never tell '
            'her it is clear" returns true over a document 81 days old.',
      );
    },
  );

  test(
    'RED 2/4 — fold() routes a frozen feed to the `complete` branch',
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
            'FAILS ON 0.0.9. fold() is the surface the package tells integrators '
            'to prefer because it "will not let you forget the case where we '
            'could not look" — and it sends this one to `complete`.',
      );
    },
  );

  test(
    'RED 3/4 — requireCompleteLookup(), "the loud stop", is silent',
    () async {
      final r = await read();
      expect(
        r.requireCompleteLookup,
        throwsA(isA<AdvisoryLookupIncompleteException>()),
        reason:
            'FAILS ON 0.0.9. Documented as the stop to call "before any code '
            'path that would tell a driver the road is clear."',
      );
    },
  );

  test('RED 4/4 — toLookup() classifies the frozen case as Complete', () async {
    final r = await read();
    expect(
      r.toLookup(),
      isNot(isA<AdvisoryLookupComplete>()),
      reason:
          'FAILS ON 0.0.9. An exhaustive switch cannot save a caller when the '
          'frozen case is typed Complete.',
    );
  });
}
