import 'package:driving_conditions/driving_conditions.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('ConstantFleetConfidenceProvider', () {
    // 0.7.0: `value` is REQUIRED. Up to 0.6.1 it defaulted to 0.8, and the
    // engines' own defaults leaned on that default, so an absence became an
    // assertion nobody had typed. `ConstantFleetConfidenceProvider()` no longer
    // compiles — which is the point, and is why this test asserts the honest
    // absence form instead.
    test('there is no default value — absence has its own constructor', () {
      const absent = ConstantFleetConfidenceProvider.unavailable();
      expect(absent.confidence, isNull);
      const asserted = ConstantFleetConfidenceProvider(0.8);
      expect(asserted.confidence, 0.8);
    });

    test('returns the provided value', () {
      const provider = ConstantFleetConfidenceProvider(0.5);
      expect(provider.confidence, 0.5);
    });

    test('accepts 0.0 and 1.0 boundary values', () {
      const low = ConstantFleetConfidenceProvider(0.0);
      const high = ConstantFleetConfidenceProvider(1.0);
      expect(low.confidence, 0.0);
      expect(high.confidence, 1.0);
    });
  });

  group('FleetHazardConfidenceAdapter', () {
    final now = DateTime.now();
    final position = const LatLng(35.1, 136.9);

    FleetReport report(
      RoadCondition condition, {
      double confidence = 1.0,
      Duration age = Duration.zero,
    }) => FleetReport(
      vehicleId: 'v1',
      position: position,
      timestamp: now.subtract(age),
      condition: condition,
      confidence: confidence,
    );

    // These four tests CERTIFIED the defect up to 0.5.4: they asserted that
    // silence from the fleet returns 0.8 — a number weighted at 0.2 into the
    // overall safety score, so no-fleet-data RAISED it. They are inverted here,
    // which is itself the proof that this release is breaking.
    test('NO reports => null (the fleet said nothing), never 0.8', () {
      const adapter = FleetHazardConfidenceAdapter([]);
      expect(adapter.confidence, isNull);
    });

    test('all reports STALE => null, never 0.8', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, age: const Duration(hours: 1)),
      ]);
      expect(adapter.confidence, isNull);
    });

    test('dry report returns 1.0', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry),
      ]);
      expect(adapter.confidence, closeTo(1.0, 1e-9));
    });

    test('wet report returns 0.7', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.wet),
      ]);
      expect(adapter.confidence, closeTo(0.7, 1e-9));
    });

    test('snowy report returns 0.4', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.snowy),
      ]);
      expect(adapter.confidence, closeTo(0.4, 1e-9));
    });

    test('icy report returns 0.1', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy),
      ]);
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('an EXPLICITLY unknown report carries no weight => null', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.unknown),
      ]);
      // A driver reporting "I don't know" used to nudge the score UPWARD (0.8,
      // versus 0.4 for `snowy`). It now tells us nothing, which is the truth.
      expect(adapter.confidence, isNull);
    });

    test('an unknown report does not dilute a real one', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy),
        report(RoadCondition.unknown),
      ]);
      // Only the icy report carries information.
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('icy conditions produce lower confidence than snowy', () {
      final icy = FleetHazardConfidenceAdapter([report(RoadCondition.icy)]);
      final snowy =
          FleetHazardConfidenceAdapter([report(RoadCondition.snowy)]);
      expect(icy.confidence!, lessThan(snowy.confidence!));
    });

    test('mixed dry and icy reports are weighted by observation confidence',
        () {
      // dry report weight 0.8, icy report weight 0.2
      // expected = (1.0 * 0.8 + 0.1 * 0.2) / (0.8 + 0.2) = 0.82
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry, confidence: 0.8),
        report(RoadCondition.icy, confidence: 0.2),
      ]);
      expect(adapter.confidence, closeTo(0.82, 1e-9));
    });

    test('only recent reports are used', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy),                               // recent
        report(RoadCondition.dry, age: const Duration(hours: 1)), // stale
      ]);
      // Only the icy report counts → 0.1
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('custom maxAge is respected', () {
      final adapter = FleetHazardConfidenceAdapter(
        [report(RoadCondition.dry, age: const Duration(minutes: 5))],
        maxAge: const Duration(minutes: 3),
      );
      // 5-minute-old report is stale at a 3-minute window → no fleet data.
      expect(adapter.confidence, isNull);
    });

    // 0.7.0 replaced the trailing `.clamp(0.0, 1.0)` with explicit bounds —
    // `num.clamp` mapped a non-finite mean to 1.0. The GUARANTEE is unchanged
    // and still asserted here; only the mechanism behind it moved.
    test('result stays within [0.0, 1.0]', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry),
      ]);
      expect(adapter.confidence, inInclusiveRange(0.0, 1.0));
    });
  });

  // 0.7.0: the injection seam is GONE. These two cases used to prove that an
  // icy adapter lowered `overall` and a dry one raised it — i.e. that a fleet
  // reading moved the safety score. That is exactly what no longer happens, and
  // what must not silently come back. They are re-authored to assert the two
  // halves separately: the adapter still RANKS road conditions correctly, and
  // the score is INDIFFERENT to it.
  group('the adapter ranks conditions; the score does not consume it', () {
    final position = const LatLng(35.1, 136.9);
    FleetReport report(RoadCondition condition, double confidence) =>
        FleetReport(
          vehicleId: 'v1',
          position: position,
          timestamp: DateTime.now(),
          condition: condition,
          confidence: confidence,
        );

    test('icy reads lower than dry — the reading is still correct', () {
      final icy = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, 0.8),
      ]).confidence;
      final dry = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry, 0.8),
      ]).confidence;

      expect(icy, isNotNull);
      expect(dry, isNotNull);
      expect(icy!, lessThan(dry!));
      expect(dry, closeTo(1.0, 1e-9));
    });

    test('the safety score is byte-identical whatever the fleet says', () {
      SimulationResult score() => const SafetyScoreSimulator().simulate(
        runs: 200,
        speed: 60,
        gripFactor: 0.7,
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 500,
        seed: 42,
      );

      // Read three very different fleet answers, then compute the score. There
      // is no parameter to pass them through, and the score does not change.
      final answers = [
        FleetHazardConfidenceAdapter([
          report(RoadCondition.icy, 0.8),
        ]).confidence,
        FleetHazardConfidenceAdapter([
          report(RoadCondition.dry, 0.8),
        ]).confidence,
        const FleetHazardConfidenceAdapter([]).confidence,
      ];
      expect(answers[0], isNot(equals(answers[1])));
      expect(answers[2], isNull);

      expect(score().score.overall, equals(score().score.overall));
      expect(
        score().score.overall,
        closeTo(
          0.5 * score().score.gripScore + 0.5 * score().score.visibilityScore,
          1e-12,
        ),
      );
    });
  });
}
