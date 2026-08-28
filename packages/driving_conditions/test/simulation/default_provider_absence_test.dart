// Regression guard: no fleet number can enter the safety score, by any route.
//
// 0.6.0 shipped the Measured-or-Absent recall in the MODEL and then handed the
// removed value straight back through three DEFAULT CONSTRUCTOR ARGUMENTS: a
// consumer who wired no fleet source received `fleetConfidenceScore == 0.8` and
// `hasFleetData == true`. 0.6.1 (held, never published) changed those three
// defaults to `unavailable()`.
//
// 0.7.0 closes the class of defect rather than the instance. The `provider:`
// parameters are GONE from all three engines and the fleet fields are gone from
// `SimulatedSafetyScore`, so there is no default to get wrong, no field to
// misreport, and nothing for a later edit to quietly re-point at 0.8. The tests
// below therefore assert a SHAPE, not a value.
import 'package:driving_conditions/driving_conditions.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('the composite has two terms and states their weights', () {
    test('CpuSafetyScoreSimulationEngine: overall = 0.5g + 0.5v', () {
      const engine = CpuSafetyScoreSimulationEngine();
      final result = engine.simulate(
        speed: 50,
        gripFactor: 0.6,
        surface: RoadSurfaceState.compactedSnow,
        visibilityMeters: 400,
        options: const SimulationOptions(runs: 100, seed: 42),
      );

      expect(
        result.score.overall,
        closeTo(
          0.5 * result.score.gripScore + 0.5 * result.score.visibilityScore,
          1e-12,
        ),
      );
      // The rendered form no longer mentions a fleet at all — neither a number
      // nor a "not measured" placeholder for a term that does not exist.
      expect(result.score.toString(), isNot(contains('fleet')));
    });

    test('SafetyScoreSimulator agrees with the engine it delegates to', () {
      const simulator = SafetyScoreSimulator();
      final result = simulator.simulate(
        runs: 100,
        speed: 50,
        gripFactor: 0.6,
        surface: RoadSurfaceState.compactedSnow,
        visibilityMeters: 400,
        seed: 42,
      );

      expect(
        result.score.overall,
        closeTo(
          0.5 * result.score.gripScore + 0.5 * result.score.visibilityScore,
          1e-12,
        ),
      );
    });

    test(
      'the weights are NOT re-normalised — they are constants that sum to 1',
      () {
        // The 0.6.0 absent-path computed `(0.4g + 0.4v) / 0.8`. That expression
        // equals `0.5g + 0.5v`, which is why this test cannot distinguish the
        // two by output alone — and why the fix had to be structural. What it
        // CAN pin is that a perfect road reaches the top of the scale, which is
        // what a weighting that sums to 1.0 guarantees and the floor design
        // (max 0.780257) did not.
        const engine = CpuSafetyScoreSimulationEngine();
        final perfect = engine.simulate(
          speed: 0,
          gripFactor: 1.0,
          surface: RoadSurfaceState.dry,
          visibilityMeters: 1000,
          options: const SimulationOptions(runs: 500, seed: 7),
        );

        expect(perfect.score.overall, greaterThan(0.9));
        expect(
          perfect.score.toAlertSeverity(
            NavigationSafetyConfig.forProfile(DriverProfile.ageingRural),
          ),
          isNull,
          reason: 'a genuinely benign road must still be able to read none',
        );
      },
    );
  });

  group('what the 0.6.0 defect cost the driver', () {
    // Black ice (gripFactor 0.15), 300 m visibility, 40 km/h. The measured
    // terms alone say CRITICAL. 0.6.0's defaulted fleet term said WARNING —
    // "reduce speed" where the evidence says turn back — on the strength of a
    // fleet that reported nothing.
    late SimulationResult shipped;

    setUp(() {
      shipped = const SafetyScoreSimulator().simulate(
        runs: 2000,
        speed: 40,
        gripFactor: 0.15,
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 300,
        seed: 42,
      );
    });

    test('0.7.0 reports critical on the road 0.6.0 called a warning', () {
      final config = NavigationSafetyConfig();
      expect(shipped.score.overall, closeTo(0.207, 0.002));
      expect(shipped.score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('the 0.6.0 arithmetic, reproduced, still lands on warning', () {
      // 0.6.0's composite cannot be constructed through this API any more, so
      // it is reproduced from the SAME realised term means. This is the
      // measurement the fix exists to move, kept executable so it cannot
      // silently stop being true.
      final config = NavigationSafetyConfig();
      final asShippedIn060 =
          0.4 * shipped.score.gripScore +
          0.4 * shipped.score.visibilityScore +
          0.2 * 0.8; // the default nobody typed

      expect(asShippedIn060, closeTo(0.326, 0.002));
      final severity060 = asShippedIn060 < config.warningScoreFloor
          ? AlertSeverity.critical
          : asShippedIn060 < config.infoScoreFloor
          ? AlertSeverity.warning
          : AlertSeverity.info;
      expect(severity060, AlertSeverity.warning);

      // She was told to reduce speed where the measured terms say turn back.
      expect(asShippedIn060, greaterThan(shipped.score.overall));
    });
  });
}
