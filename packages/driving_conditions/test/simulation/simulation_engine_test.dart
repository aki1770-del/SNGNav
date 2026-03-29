import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';

void main() {
  group('CpuSafetyScoreSimulationEngine', () {
    const engine = CpuSafetyScoreSimulationEngine();

    test('is deterministic with the same seed', () {
      const options = SimulationOptions(runs: 200, seed: 42);

      final first = engine.simulate(
        speed: 55,
        gripFactor: 0.7,
        surface: RoadSurfaceState.wet,
        visibilityMeters: 700,
        options: options,
      );
      final second = engine.simulate(
        speed: 55,
        gripFactor: 0.7,
        surface: RoadSurfaceState.wet,
        visibilityMeters: 700,
        options: options,
      );

      expect(first, second);
    });

    test('accepts auto backend as CPU fallback', () {
      final result = engine.simulate(
        speed: 60,
        gripFactor: 0.8,
        surface: RoadSurfaceState.dry,
        visibilityMeters: 1000,
        options: const SimulationOptions(
          backend: SimulationBackend.auto,
          runs: 50,
          seed: 11,
        ),
      );

      expect(result.score.overall, inInclusiveRange(0.0, 1.0));
      expect(result.variance, isNonNegative);
      expect(result.incidentCount, greaterThanOrEqualTo(0));
      expect(result.executionMs, isNull);
    });

    test('rejects gpu backend explicitly', () {
      expect(
        () => engine.simulate(
          speed: 60,
          gripFactor: 0.8,
          surface: RoadSurfaceState.dry,
          visibilityMeters: 1000,
          options: const SimulationOptions(
            backend: SimulationBackend.gpu,
            runs: 50,
            seed: 11,
          ),
        ),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });

  group('SafetyScoreSimulator engine delegation', () {
    const cpuEngine = CpuSafetyScoreSimulationEngine();
    const injectedSimulator = SafetyScoreSimulator(engine: cpuEngine);
    const defaultSimulator = SafetyScoreSimulator();

    test('explicit CPU engine matches default simulator for same seed', () {
      final injected = injectedSimulator.simulate(
        runs: 200,
        speed: 45,
        gripFactor: 0.75,
        surface: RoadSurfaceState.slush,
        visibilityMeters: 650,
        seed: 7,
      );
      final defaulted = defaultSimulator.simulate(
        runs: 200,
        speed: 45,
        gripFactor: 0.75,
        surface: RoadSurfaceState.slush,
        visibilityMeters: 650,
        seed: 7,
      );

      expect(injected, defaulted);
    });

    test('default simulator still returns bounded averages', () {
      final result = defaultSimulator.simulate(
        runs: 100,
        speed: 65,
        gripFactor: 0.6,
        surface: RoadSurfaceState.standingWater,
        visibilityMeters: 500,
        seed: 19,
      );

      expect(result.score.overall, inInclusiveRange(0.0, 1.0));
      expect(result.score.gripScore, inInclusiveRange(0.0, 1.0));
      expect(result.score.visibilityScore, inInclusiveRange(0.0, 1.0));
      expect(result.score.fleetConfidenceScore, closeTo(0.8, 1e-9));
      expect(result.variance, isNonNegative);
      expect(result.incidentCount, greaterThanOrEqualTo(0));
    });
  });

  group('SimulationOptions', () {
    test('has value semantics', () {
      const first = SimulationOptions(
        backend: SimulationBackend.cpu,
        seed: 5,
        runs: 250,
      );
      const second = SimulationOptions(
        backend: SimulationBackend.cpu,
        seed: 5,
        runs: 250,
      );
      const different = SimulationOptions(
        backend: SimulationBackend.auto,
        seed: 5,
        runs: 250,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first, isNot(different));
    });
  });
}