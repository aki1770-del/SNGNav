/// Pure Dart CPU implementation of [SafetyScoreSimulationEngine].
///
/// Contains the original Monte Carlo logic extracted from
/// [SafetyScoreSimulator]. This is the production-quality fallback
/// that is always available regardless of platform.
library;

import 'dart:math';

import 'package:navigation_safety/navigation_safety_core.dart';

import '../models/road_surface_state.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_backend.dart';
import 'simulation_options.dart';

/// CPU (pure Dart) Monte Carlo safety score engine.
///
/// Runs N stochastic simulations with jittered inputs to produce
/// a probabilistic [SafetyScore]. Deterministic seeding for tests.
///
/// Performance gate: 1,000 runs < 200ms in `dart test`.
class CpuSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates a CPU simulation engine.
  const CpuSafetyScoreSimulationEngine();

  /// Run a single simulation with stochastic perturbation.
  ///
  /// Jitter (±10%) is applied to grip and visibility inputs
  /// to model real-world sensor noise.
  SafetyScore runOnce({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required Random random,
  }) {
    final gripJitter = random.nextDouble() * 0.1;
    final visJitter = random.nextDouble() * 0.1;

    // Speed factor: higher speed reduces safety. Normalise to 0–1 range
    // assuming 130 km/h as maximum reference speed.
    final speedFactor = (speed / 130.0).clamp(0.0, 1.0);

    final gripScore =
        (gripFactor * (1.0 - gripJitter) * (1.0 - speedFactor * 0.3))
            .clamp(0.0, 1.0);

    final visNorm = (visibilityMeters / 1000.0).clamp(0.0, 1.0);
    final visibilityScore = (visNorm * (1.0 - visJitter)).clamp(0.0, 1.0);

    // Fleet confidence placeholder — real fleet data is L2 scope.
    const fleetConfidenceScore = 0.8;

    // Weighted mean: grip 0.4, visibility 0.4, fleet 0.2.
    final overall =
        gripScore * 0.4 + visibilityScore * 0.4 + fleetConfidenceScore * 0.2;

    return SafetyScore(
      overall: overall,
      gripScore: gripScore,
      visibilityScore: visibilityScore,
      fleetConfidenceScore: fleetConfidenceScore,
    );
  }

  @override
  SafetyScore simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  }) {
    if (options.backend == SimulationBackend.gpu) {
      throw UnsupportedError(
        'GPU backend is not available in CpuSafetyScoreSimulationEngine.',
      );
    }

    final random = options.seed != null ? Random(options.seed) : Random();

    var totalOverall = 0.0;
    var totalGrip = 0.0;
    var totalVis = 0.0;
    var totalFleet = 0.0;

    for (var i = 0; i < options.runs; i++) {
      final score = runOnce(
        speed: speed,
        gripFactor: gripFactor,
        surface: surface,
        visibilityMeters: visibilityMeters,
        random: random,
      );
      totalOverall += score.overall;
      totalGrip += score.gripScore;
      totalVis += score.visibilityScore;
      totalFleet += score.fleetConfidenceScore;
    }

    return SafetyScore(
      overall: totalOverall / options.runs,
      gripScore: totalGrip / options.runs,
      visibilityScore: totalVis / options.runs,
      fleetConfidenceScore: totalFleet / options.runs,
    );
  }
}
