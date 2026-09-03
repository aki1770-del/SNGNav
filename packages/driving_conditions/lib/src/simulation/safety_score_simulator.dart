/// Monte Carlo safety score simulator — pure Dart computation.
///
/// Runs N stochastic simulations with jittered inputs to produce
/// a probabilistic [SimulatedSafetyScore]. Deterministic seeding for tests.
///
/// Performance gate: 1,000 runs < 200ms in `dart test`.
///
/// Delegates to a [SafetyScoreSimulationEngine] for compute.
/// Defaults to [CpuSafetyScoreSimulationEngine] when no engine is provided.
library;

import 'dart:math';

import '../models/road_surface_state.dart';
import 'cpu_safety_score_simulation_engine.dart';
import 'safety_score_simulation_engine.dart';
import 'simulated_safety_score.dart';
import 'simulation_backend.dart';
import 'simulation_options.dart';
import 'simulation_result.dart';

/// Front door to the simulation lane.
///
/// **0.7.0 removed the `provider:` parameter.** The score has no fleet term —
/// see [SimulatedSafetyScore]. A consumer with a real fleet source reads it
/// directly through `FleetHazardConfidenceAdapter`, which is still exported and
/// still returns `null` when the fleet said nothing.
class SafetyScoreSimulator {
  /// Creates a simulator, optionally over a specific [engine].
  const SafetyScoreSimulator({SafetyScoreSimulationEngine? engine})
    : _engine = engine;

  final SafetyScoreSimulationEngine? _engine;

  SafetyScoreSimulationEngine get _effectiveEngine =>
      _engine ?? const CpuSafetyScoreSimulationEngine();

  /// Run a single simulation with stochastic perturbation.
  ///
  /// Jitter (±10%) is applied to grip and visibility inputs
  /// to model real-world sensor noise.
  ///
  /// Throws [ArgumentError] if [speed], [gripFactor] or [visibilityMeters] is
  /// non-finite.
  SimulatedSafetyScore runOnce({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required Random random,
  }) {
    // Delegate to simulate(runs: 1) — uses the engine's simulate() contract
    // which all implementations provide, rather than a runOnce() method that
    // only CpuSafetyScoreSimulationEngine exposes directly.
    final result = _effectiveEngine.simulate(
      speed: speed,
      gripFactor: gripFactor,
      surface: surface,
      visibilityMeters: visibilityMeters,
      options: SimulationOptions(
        backend: SimulationBackend.auto,
        runs: 1,
        seed: random.nextInt(0x7FFFFFFF),
      ),
    );
    return result.score;
  }

  /// Run N Monte Carlo simulations and return a [SimulationResult].
  ///
  /// [SimulationResult] includes the mean [SimulatedSafetyScore] plus variance,
  /// incident count, and (when using the native engine) execution time.
  ///
  /// [runs] defaults to 1000. Provide [seed] for deterministic results
  /// (required for testing).
  ///
  /// Throws [ArgumentError] if [speed], [gripFactor] or [visibilityMeters] is
  /// non-finite.
  SimulationResult simulate({
    int runs = 1000,
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    int? seed,
  }) {
    return _effectiveEngine.simulate(
      speed: speed,
      gripFactor: gripFactor,
      surface: surface,
      visibilityMeters: visibilityMeters,
      options: SimulationOptions(
        backend: SimulationBackend.auto,
        runs: runs,
        seed: seed,
      ),
    );
  }
}
