import 'dart:math';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';

void main() {
  group('SafetyScoreSimulator.runOnce', () {
    const simulator = SafetyScoreSimulator();

    test('returns bounded score components', () {
      final score = simulator.runOnce(
        speed: 60,
        gripFactor: 0.7,
        surface: RoadSurfaceState.wet,
        visibilityMeters: 800,
        random: Random(1),
      );

      expect(score.overall, inInclusiveRange(0.0, 1.0));
      expect(score.gripScore, inInclusiveRange(0.0, 1.0));
      expect(score.visibilityScore, inInclusiveRange(0.0, 1.0));
      expect(score.fleetConfidenceScore, 0.8);
    });

    test('higher speed reduces overall score', () {
      final lowSpeed = simulator.runOnce(
        speed: 20,
        gripFactor: 1.0,
        surface: RoadSurfaceState.dry,
        visibilityMeters: 1000,
        random: Random(7),
      );
      final highSpeed = simulator.runOnce(
        speed: 120,
        gripFactor: 1.0,
        surface: RoadSurfaceState.dry,
        visibilityMeters: 1000,
        random: Random(7),
      );

      expect(highSpeed.gripScore, lessThan(lowSpeed.gripScore));
      expect(highSpeed.overall, lessThan(lowSpeed.overall));
    });
  });

  group('SafetyScoreSimulator.simulate', () {
    const simulator = SafetyScoreSimulator();

    test('deterministic with seed', () {
      final a = simulator.simulate(
        runs: 200,
        speed: 50,
        gripFactor: 0.7,
        surface: RoadSurfaceState.wet,
        visibilityMeters: 700,
        seed: 42,
      );
      final b = simulator.simulate(
        runs: 200,
        speed: 50,
        gripFactor: 0.7,
        surface: RoadSurfaceState.wet,
        visibilityMeters: 700,
        seed: 42,
      );

      expect(a, b);
    });

    test('worse conditions reduce overall score', () {
      final good = simulator.simulate(
        runs: 200,
        speed: 40,
        gripFactor: 1.0,
        surface: RoadSurfaceState.dry,
        visibilityMeters: 1000,
        seed: 10,
      );
      final poor = simulator.simulate(
        runs: 200,
        speed: 90,
        gripFactor: 0.15,
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 100,
        seed: 10,
      );

      expect(poor.overall, lessThan(good.overall));
      expect(poor.gripScore, lessThan(good.gripScore));
      expect(poor.visibilityScore, lessThan(good.visibilityScore));
    });

    test('single run is supported', () {
      final score = simulator.simulate(
        runs: 1,
        speed: 50,
        gripFactor: 0.5,
        surface: RoadSurfaceState.slush,
        visibilityMeters: 500,
        seed: 3,
      );

      expect(score.overall, inInclusiveRange(0.0, 1.0));
    });

    test('default run count returns stable average', () {
      final score = simulator.simulate(
        speed: 60,
        gripFactor: 0.6,
        surface: RoadSurfaceState.standingWater,
        visibilityMeters: 600,
        seed: 9,
      );

      expect(score.overall, inInclusiveRange(0.0, 1.0));
      expect(score.fleetConfidenceScore, closeTo(0.8, 1e-9));
    });
  });
}