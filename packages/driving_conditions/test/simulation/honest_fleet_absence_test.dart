// Fleet SILENCE must not raise the computed safety score.
//
// Up to 0.5.4:
//   FleetHazardConfidenceAdapter.confidence -> 0.8 ("neutral baseline") when
//     * no recent report arrived, OR
//     * the only reports carried RoadCondition.unknown, OR
//     * total observation weight was zero
//   CpuSafetyScoreSimulationEngine:
//     overall = grip*0.4 + visibility*0.4 + fleetConfidence*0.2
//
// 0.8 is not neutral (dry = 1.0, snowy = 0.4): it is an OPTIMISTIC report from
// a fleet that reported nothing, folded into the score at weight 0.2. On a bad
// road with no fleet data, the fabricated term pulled the score UP.
import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';

void main() {
  const options = SimulationOptions(
    backend: SimulationBackend.cpu,
    runs: 200,
    seed: 7,
  );

  SimulationResult run(FleetConfidenceProvider provider) =>
      CpuSafetyScoreSimulationEngine(provider: provider).simulate(
        speed: 60,
        gripFactor: 0.2, // an icy road
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 300,
        options: options,
      );

  group('an absent fleet term is not folded into the score', () {
    test('no fleet data => fleetConfidenceScore is null, never 0.8', () {
      final r = run(const FleetHazardConfidenceAdapter([]));

      expect(r.score.fleetConfidenceScore, isNull);
      expect(r.score.hasFleetData, isFalse);
    });

    test('no fleet data does NOT raise the score above the measured terms', () {
      final absent = run(const FleetHazardConfidenceAdapter([]));

      // With grip 0.2 and visibility 0.3, both measured terms are low. The
      // re-normalised overall must stay in that range — it must NOT be lifted
      // by a fabricated 0.8 fleet term.
      expect(absent.score.overall, lessThan(0.5));

      // The old behaviour, reproduced deliberately: an ASSERTED 0.8 (a
      // simulator declaring a scenario — legitimate, see
      // ConstantFleetConfidenceProvider) yields a HIGHER overall than honest
      // absence does. That gap is exactly the fabrication that used to be
      // applied silently whenever the fleet was quiet.
      final asserted = run(const ConstantFleetConfidenceProvider(0.8));
      expect(asserted.score.overall, greaterThan(absent.score.overall));
      expect(asserted.score.fleetConfidenceScore, isNotNull);
    });

    test('the re-normalised overall is the mean of the KNOWN terms', () {
      final r = run(const FleetHazardConfidenceAdapter([]));

      // weights re-normalised over grip (0.4) + visibility (0.4)
      final expected =
          (r.score.gripScore * 0.4 + r.score.visibilityScore * 0.4) / 0.8;
      expect(r.score.overall, closeTo(expected, 0.02));
    });

    test('an explicit no-data provider behaves the same as an empty fleet', () {
      final r = run(const ConstantFleetConfidenceProvider.unavailable());

      expect(r.score.fleetConfidenceScore, isNull);
      expect(r.score.overall, lessThan(0.5));
    });

    test('a REAL fleet report is still folded in, and still lowers the score',
        () {
      final icy = run(
        const ConstantFleetConfidenceProvider(0.1),
      );
      final good = run(const ConstantFleetConfidenceProvider(1.0));

      expect(icy.score.fleetConfidenceScore, closeTo(0.1, 1e-9));
      expect(icy.score.overall, lessThan(good.score.overall));
    });
  });
}
