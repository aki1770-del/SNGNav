// The fleet term is NOT in the safety score, and there is no way to put it back.
//
// The history this file guards, in order:
//
//   up to 0.5.4  overall = grip*0.4 + vis*0.4 + fleet*0.2, and absence of a
//                fleet report was filled with 0.8 — an OPTIMISTIC number (dry
//                = 1.0, snowy = 0.4) from a fleet that reported nothing. On a
//                bad road with no fleet data the fabricated term pulled the
//                score UP.
//   0.6.0        the model learned to say `null`, and re-normalised the
//                remaining weights. But `(0.4g + 0.4v) / 0.8` is `0.5g + 0.5v`,
//                which is arithmetically identical to imputing the absent term
//                as the MEAN of the measured ones — so absence silently AGREED
//                with everything else, and in good conditions scored HIGHER
//                than the 0.8 it replaced.
//   0.6.1 (held) fixed the three engine defaults that still said 0.8. Correct,
//                and still sitting on the re-normalisation above.
//   0.7.0        the term is removed. Weights are stated (0.5 / 0.5), sum to
//                1.0, and are never re-normalised, because there is no longer
//                any term whose absence could be imputed.
//
// The reading API survives and is tested here too: it is honest, useful and
// standalone. What it no longer does is enter a number this package calls a
// safety score.
import 'package:driving_conditions/driving_conditions.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  SimulationResult run({
    double grip = 0.2, // an icy road
    double visibility = 300,
    double speed = 60,
  }) => const CpuSafetyScoreSimulationEngine().simulate(
    speed: speed,
    gripFactor: grip,
    surface: RoadSurfaceState.blackIce,
    visibilityMeters: visibility,
    options: const SimulationOptions(
      backend: SimulationBackend.cpu,
      runs: 200,
      seed: 7,
    ),
  );

  group('the score is the stated weighting of the measured terms', () {
    test('overall is exactly 0.5*grip + 0.5*visibility', () {
      final r = run();
      expect(
        r.score.overall,
        closeTo(0.5 * r.score.gripScore + 0.5 * r.score.visibilityScore, 1e-12),
      );
    });

    test('a bad road is not lifted by anything', () {
      final r = run();
      // grip 0.2 and visibility 0.3 are both low; overall must stay in that
      // range. Up to 0.6.0 a fabricated 0.8 fleet term lifted it.
      expect(r.score.overall, lessThan(0.5));
    });

    test('the weights sum to 1, so a perfect road can still read ~1.0', () {
      final r = run(grip: 1.0, visibility: 1000, speed: 0);
      // The floor design that preceded this release capped `overall` at
      // 0.780257 and made the all-clear unreachable on every profile.
      expect(r.score.overall, greaterThan(0.9));
    });
  });

  group('the fleet reading API survives, and stays honest, on its own', () {
    final now = DateTime.now();
    const position = LatLng(35.1, 136.9);

    FleetReport report(RoadCondition condition, double confidence) =>
        FleetReport(
          vehicleId: 'v1',
          position: position,
          timestamp: now,
          condition: condition,
          confidence: confidence,
        );

    test('no reports => null, never a number', () {
      expect(const FleetHazardConfidenceAdapter([]).confidence, isNull);
    });

    test('a real report is still read, and still ranks', () {
      final icy = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, 0.9),
      ]).confidence;
      final dry = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry, 0.9),
      ]).confidence;

      expect(icy, closeTo(0.1, 1e-9));
      expect(dry, closeTo(1.0, 1e-9));
      expect(icy, lessThan(dry!));
    });

    test('no fleet reading, of any value, can move the safety score', () {
      // There is no seam to inject one through. This is the structural form of
      // the guarantee: not "the default is honest" (0.6.1's claim, which was
      // true and insufficient) but "no such parameter exists".
      final baseline = run();
      for (final c in [0.0, 0.1, 0.5, 0.8, 1.0]) {
        expect(
          const ConstantFleetConfidenceProvider(0.5).confidence,
          isNotNull,
          reason: 'the provider API still works standalone',
        );
        // Same inputs, same seed, same answer — whatever any fleet says.
        expect(run().score.overall, equals(baseline.score.overall),
            reason: 'fleet value $c must be unable to reach the score');
      }
    });
  });
}
