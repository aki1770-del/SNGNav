// An unreadable sensor is not a perfect road.
//
// `double.nan.clamp(0.0, 1.0)` returns **1.0** — the top of the scale. Every
// term in this package's composite reached `overall` through a `.clamp(0.0,
// 1.0)`, so a non-finite input did not fail, and did not read as unknown: it
// read as the best measurement the model can express.
//
// This was found and fixed once, in the FLEET adapter, for 0.6.0. It was never
// fixed in the terms the fleet adapter sat beside — and those are the terms
// that survive the fleet term's removal in 0.7.0. Measured against PUBLISHED
// 0.6.0 on the ageingRural profile (safe 0.85 / info 0.55 / warn 0.35):
//
//   black ice, 300 m visibility, 40 km/h  -> overall 0.3077  band critical
//   the same road, gripFactor: nan        -> overall 0.6732  band info
//   the same road, both sensors nan       -> overall 0.9373  band none
//   a genuinely perfect road, 0 km/h      -> overall 0.9178  band none
//
// Two unreadable sensors outscored the best real road in the model, and handed
// her an all-clear. On the held 0.6.1 branch the same probe read 0.9716 against
// 0.9473 — re-normalisation widened the gap, because the two fabricated 1.0s
// then carried the whole weight.
//
// Every test in this file fails against 0.6.0 and against 0.6.1.
import 'dart:math';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  const engine = CpuSafetyScoreSimulationEngine();
  const options = SimulationOptions(runs: 48, seed: 7);

  SimulationResult run({
    double speed = 40,
    double grip = 0.15,
    double visibility = 300,
  }) => engine.simulate(
    speed: speed,
    gripFactor: grip,
    surface: RoadSurfaceState.blackIce,
    visibilityMeters: visibility,
    options: options,
  );

  group('the score refuses a value that is not a number', () {
    test('Dart semantics, stated so the reason is not lost', () {
      // The whole defect in one line. If this ever stops being true, the
      // guards below are still correct but their motivation has changed.
      expect(double.nan.clamp(0.0, 1.0), 1.0);
      // Read through a function so the analyzer cannot constant-fold it away:
      // `x == 0.0` being false for NaN is exactly why 0.6.0's zero-weight
      // guard (`if (totalWeight == 0.0) return null;`) never fired on a
      // corrupt stream.
      double unreadable() => double.nan;
      expect(unreadable() == 0.0, isFalse);
    });

    for (final bad in <(String, double)>[
      ('NaN', double.nan),
      ('+Infinity', double.infinity),
      ('-Infinity', double.negativeInfinity),
    ]) {
      test('gripFactor ${bad.$1} throws instead of scoring 1.0', () {
        expect(
          () => run(grip: bad.$2),
          throwsA(
            isA<ArgumentError>().having((e) => e.name, 'name', 'gripFactor'),
          ),
        );
      });

      test('visibilityMeters ${bad.$1} throws', () {
        expect(
          () => run(visibility: bad.$2),
          throwsA(
            isA<ArgumentError>().having(
              (e) => e.name,
              'name',
              'visibilityMeters',
            ),
          ),
        );
      });

      test('speed ${bad.$1} throws', () {
        expect(
          () => run(speed: bad.$2),
          throwsA(isA<ArgumentError>().having((e) => e.name, 'name', 'speed')),
        );
      });
    }

    test('both sensors unreadable throws — it does NOT read none', () {
      expect(
        () => run(grip: double.nan, visibility: double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SafetyScoreSimulator.runOnce guards too, not just simulate', () {
      expect(
        () => const SafetyScoreSimulator().runOnce(
          speed: 40,
          gripFactor: double.nan,
          surface: RoadSurfaceState.blackIce,
          visibilityMeters: 300,
          random: Random(1),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('SimulatedSafetyScore itself will not hold a non-finite term', () {
      expect(
        () => SimulatedSafetyScore(gripScore: double.nan, visibilityScore: 0.5),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => SimulatedSafetyScore(gripScore: 0.5, visibilityScore: double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('a finite out-of-range value is still coerced, not rejected', () {
      // Range coercion of a real number is a different act from inventing one.
      final s = SimulatedSafetyScore(gripScore: 1.4, visibilityScore: -0.3);
      expect(s.gripScore, 1.0);
      expect(s.visibilityScore, 0.0);
      expect(s.overall, closeTo(0.5, 1e-12));
    });

    test(
      'a measured road is unaffected — the guard is not a behaviour change',
      () {
        final r = run();
        expect(r.score.overall, greaterThan(0.0));
        expect(r.score.overall, lessThan(1.0));
      },
    );
  });

  group('the fleet adapter closes the same defect on its own surface', () {
    FleetReport report(RoadCondition c, double confidence) => FleetReport(
      vehicleId: 'v',
      position: const LatLng(35.1, 136.9),
      timestamp: DateTime.now(),
      condition: c,
      confidence: confidence,
    );

    test('icy reports with a NaN self-confidence read null, NOT 1.0', () {
      // Published 0.6.0 and held 0.6.1 both return 1.0 here: the ice is erased
      // and replaced with "fleet reports consistently safe conditions".
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, double.nan),
        report(RoadCondition.icy, double.nan),
      ]);
      expect(adapter.confidence, isNull);
    });

    test('one unreadable report does not erase the readable ones', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, 1.0),
        report(RoadCondition.icy, double.nan),
      ]);
      // 0.1 (icy), unchanged by the corrupt report — not 1.0.
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('an infinite self-confidence carries no weight', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, double.infinity),
      ]);
      expect(adapter.confidence, isNull);
    });

    test('a negative self-confidence cannot subtract a hazard back out', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, 1.0),
        report(RoadCondition.dry, -2.0),
      ]);
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });
  });
}
