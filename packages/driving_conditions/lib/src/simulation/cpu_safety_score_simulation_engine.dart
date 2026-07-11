/// Pure Dart CPU implementation of [SafetyScoreSimulationEngine].
///
/// Contains the original Monte Carlo logic extracted from
/// [SafetyScoreSimulator]. This is the production-quality fallback
/// that is always available regardless of platform.
library;

import 'dart:math';

import 'package:navigation_safety_core/navigation_safety_core.dart';

import '../models/road_surface_state.dart';
import 'constant_fleet_confidence_provider.dart';
import 'fleet_confidence_provider.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_backend.dart';
import 'simulation_options.dart';
import 'simulated_safety_score.dart';
import 'simulation_result.dart';

/// CPU (pure Dart) Monte Carlo safety score engine.
///
/// Runs N stochastic simulations with jittered inputs to produce
/// a probabilistic [SafetyScore]. Deterministic seeding for tests.
///
/// Inject a [FleetConfidenceProvider] to replace the pre-Sprint 91
/// hardcoded 0.8 fleet confidence baseline. Defaults to
/// [ConstantFleetConfidenceProvider] (0.8) — behavior unchanged for
/// existing call sites.
///
/// Performance gate: 1,000 runs < 200ms in `dart test`.
class CpuSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates a CPU simulation engine.
  ///
  /// [provider] supplies the fleet confidence score for each simulation.
  /// Defaults to [ConstantFleetConfidenceProvider] (0.8).
  const CpuSafetyScoreSimulationEngine({
    FleetConfidenceProvider provider = const ConstantFleetConfidenceProvider(),
  }) : _provider = provider;

  final FleetConfidenceProvider _provider;

  /// Run a single simulation with stochastic perturbation.
  ///
  /// Jitter (±10%) is applied to grip and visibility inputs
  /// to model real-world sensor noise.
  SimulatedSafetyScore runOnce({
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

    // NULLABLE. `null` = the fleet said nothing. It is NOT folded into the
    // overall score at any value: SimulatedSafetyScore re-normalises the
    // weights over the terms that were actually measured. Up to 0.5.4 absence
    // arrived here as 0.8 and was weighted at 0.2 — so fleet silence RAISED the
    // score.
    final fleetConfidenceScore = _provider.confidence;

    return SimulatedSafetyScore(
      gripScore: gripScore,
      visibilityScore: visibilityScore,
      fleetConfidenceScore: fleetConfidenceScore,
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
    var totalFleet = 0.0;
    var fleetSamples = 0;
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
      final fleet = score.fleetConfidenceScore;
      if (fleet != null) {
        totalFleet += fleet;
        fleetSamples++;
      }
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
        // No fleet sample in ANY run => no fleet term. Never an averaged
        // stand-in.
        fleetConfidenceScore: fleetSamples == 0 ? null : totalFleet / fleetSamples,
      ),
      variance: variance,
      incidentCount: incidentCount,
    );
  }
}
