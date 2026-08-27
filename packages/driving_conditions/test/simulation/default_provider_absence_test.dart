// Regression guard for the 0.6.1 correction.
//
// 0.6.0 shipped the Measured-or-Absent recall in the MODEL —
// `FleetHazardConfidenceAdapter([]).confidence` is `null`, and
// `SimulatedSafetyScore` re-normalises the weights over the measured terms —
// and then handed the removed value straight back through three DEFAULT
// CONSTRUCTOR ARGUMENTS. A consumer who wired no fleet source received
// `fleetConfidenceScore == 0.8` and `hasFleetData == true`, and `toString()`
// printed `fleet: 0.80` where a real absence prints `not measured`. The
// package's own honest-absence flag was made to lie.
//
// Every test below FAILS against 0.6.0 and passes from 0.6.1.
import 'package:driving_conditions/driving_conditions.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('wiring no fleet source yields an ABSENT fleet term', () {
    test('CpuSafetyScoreSimulationEngine default provider is unavailable', () {
      const engine = CpuSafetyScoreSimulationEngine();
      final result = engine.simulate(
        speed: 50,
        gripFactor: 0.6,
        surface: RoadSurfaceState.compactedSnow,
        visibilityMeters: 400,
        options: const SimulationOptions(runs: 100, seed: 42),
      );

      expect(result.score.fleetConfidenceScore, isNull);
      expect(result.score.hasFleetData, isFalse);
      expect(result.score.toString(), contains('fleet: not measured'));
      expect(result.score.toString(), isNot(contains('fleet: 0.80')));
    });

    test('SafetyScoreSimulator default provider is unavailable', () {
      const simulator = SafetyScoreSimulator();
      final result = simulator.simulate(
        runs: 100,
        speed: 50,
        gripFactor: 0.6,
        surface: RoadSurfaceState.compactedSnow,
        visibilityMeters: 400,
        seed: 42,
      );

      expect(result.score.fleetConfidenceScore, isNull);
      expect(result.score.hasFleetData, isFalse);
    });

    test(
      'the default is re-normalised, not filled — grip+vis carry all weight',
      () {
        const simulator = SafetyScoreSimulator();
        final result = simulator.simulate(
          runs: 200,
          speed: 50,
          gripFactor: 0.6,
          surface: RoadSurfaceState.compactedSnow,
          visibilityMeters: 400,
          seed: 42,
        );

        final expected =
            (result.score.gripScore * 0.4 +
                result.score.visibilityScore * 0.4) /
            0.8;
        expect(result.score.overall, closeTo(expected, 1e-9));
      },
    );

    test('an ASSERTED constant is untouched — only the DEFAULT changed', () {
      const simulator = SafetyScoreSimulator(
        provider: ConstantFleetConfidenceProvider(0.8),
      );
      final result = simulator.simulate(
        runs: 100,
        speed: 50,
        gripFactor: 0.6,
        surface: RoadSurfaceState.compactedSnow,
        visibilityMeters: 400,
        seed: 42,
      );

      expect(result.score.fleetConfidenceScore, closeTo(0.8, 1e-9));
      expect(result.score.hasFleetData, isTrue);
    });
  });

  group('what the defect cost the driver', () {
    // Black ice (gripFactor 0.15), 300 m visibility, 40 km/h. The measured
    // terms alone say CRITICAL. 0.6.0's defaulted fleet term said WARNING —
    // "reduce speed" where the evidence says turn back — on the strength of a
    // fleet that reported nothing.
    SimulationResult run(FleetConfidenceProvider provider) =>
        SafetyScoreSimulator(provider: provider).simulate(
          runs: 2000,
          speed: 40,
          gripFactor: 0.15,
          surface: RoadSurfaceState.blackIce,
          visibilityMeters: 300,
          seed: 42,
        );

    test(
      'honest absence reports critical; a defaulted 0.8 reports warning',
      () {
        final config = NavigationSafetyConfig();

        final honest = run(const ConstantFleetConfidenceProvider.unavailable());
        final defaulted = run(const ConstantFleetConfidenceProvider(0.8));

        expect(honest.score.overall, closeTo(0.207, 0.002));
        expect(honest.score.toAlertSeverity(config), AlertSeverity.critical);

        expect(defaulted.score.overall, closeTo(0.326, 0.002));
        expect(defaulted.score.toAlertSeverity(config), AlertSeverity.warning);
      },
    );

    test('the shipped default now takes the honest branch', () {
      final config = NavigationSafetyConfig();
      const shipped = SafetyScoreSimulator();

      final result = shipped.simulate(
        runs: 2000,
        speed: 40,
        gripFactor: 0.15,
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 300,
        seed: 42,
      );

      expect(result.score.toAlertSeverity(config), AlertSeverity.critical);
    });
  });

  group('the fleet term never fabricates in the other direction either', () {
    test(
      'an absent fleet neither raises nor lowers relative to measured terms',
      () {
        // Re-normalisation means the absent term is not scored at all: the
        // honest overall is exactly the mean of the two measured terms.
        const engine = CpuSafetyScoreSimulationEngine();
        final r = engine.simulate(
          speed: 0,
          gripFactor: 1.0,
          surface: RoadSurfaceState.dry,
          visibilityMeters: 1000,
          options: const SimulationOptions(runs: 500, seed: 7),
        );

        expect(
          r.score.overall,
          closeTo((r.score.gripScore + r.score.visibilityScore) / 2, 1e-9),
        );
      },
    );
  });
}
