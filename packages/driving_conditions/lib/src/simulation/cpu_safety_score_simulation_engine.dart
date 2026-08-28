/// Pure Dart CPU implementation of [SafetyScoreSimulationEngine].
///
/// Contains the original Monte Carlo logic extracted from
/// [SafetyScoreSimulator]. This is the production-quality fallback
/// that is always available regardless of platform.
library;

import 'dart:math';

import '../models/road_surface_state.dart';
import 'measured_inputs.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_backend.dart';
import 'simulation_options.dart';
import 'simulated_safety_score.dart';
import 'simulation_result.dart';

/// CPU (pure Dart) Monte Carlo safety score engine.
///
/// Runs N stochastic simulations with jittered inputs to produce
/// a probabilistic [SimulatedSafetyScore]. Deterministic seeding for tests.
///
/// **0.7.0 removed the `provider:` parameter.** This engine no longer takes a
/// [FleetConfidenceProvider], because the score no longer has a fleet term —
/// see [SimulatedSafetyScore] for why. The parameter was removed rather than
/// accepted-and-ignored: a constructor that takes a fleet source, discards it,
/// and returns a safety score anyway is a worse lie than the 0.8 default it
/// would be replacing. The compile error is the notification.
///
/// A consumer who has a real fleet source still reads it, directly:
///
/// ```dart
/// final fleet = FleetHazardConfidenceAdapter(reports).confidence;
/// // null == the fleet said nothing. Render it, act on it, log it —
/// // it is simply not folded into `overall` by this package.
/// ```
///
/// Performance gate: 1,000 runs < 200ms in `dart test`.
class CpuSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates a CPU simulation engine.
  const CpuSafetyScoreSimulationEngine();

  /// Run a single simulation with stochastic perturbation.
  ///
  /// Jitter (±10%) is applied to grip and visibility inputs
  /// to model real-world sensor noise.
  ///
  /// Throws [ArgumentError] if [speed], [gripFactor] or [visibilityMeters] is
  /// non-finite — see `requireMeasured`.
  SimulatedSafetyScore runOnce({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required Random random,
  }) {
    // Checked BEFORE any arithmetic. `nan.clamp(0, 1)` is 1.0, so every clamp
    // below is a place an unreadable sensor could become a perfect reading.
    requireMeasured(speed, 'speed');
    requireMeasured(gripFactor, 'gripFactor');
    requireMeasured(visibilityMeters, 'visibilityMeters');

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

    return SimulatedSafetyScore(
      gripScore: gripScore,
      visibilityScore: visibilityScore,
    );
  }

  @override
  SimulationResult simulate({
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

    final effectiveRuns = options.runs < 1 ? 1 : options.runs;
    final random = options.seed != null ? Random(options.seed) : Random();

    var totalOverall = 0.0;
    var totalGrip = 0.0;
    var totalVis = 0.0;
    var totalOverallSquared = 0.0;
    var incidentCount = 0;

    for (var i = 0; i < effectiveRuns; i++) {
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
      totalOverallSquared += score.overall * score.overall;
      if (score.overall < 0.4) incidentCount++;
    }

    final mean = totalOverall / effectiveRuns;
    final variance = (totalOverallSquared / effectiveRuns) - (mean * mean);

    return SimulationResult(
      score: SimulatedSafetyScore(
        overall: mean,
        gripScore: totalGrip / effectiveRuns,
        visibilityScore: totalVis / effectiveRuns,
      ),
      variance: variance,
      incidentCount: incidentCount,
    );
  }
}
