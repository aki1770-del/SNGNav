/// Native (C FFI) implementation of [SafetyScoreSimulationEngine].
///
/// Delegates Monte Carlo safety-score simulation to a compiled C library
/// for higher throughput than the pure-Dart [CpuSafetyScoreSimulationEngine].
library;


import '../models/road_surface_state.dart';
import 'constant_fleet_confidence_provider.dart';
import 'cpu_safety_score_simulation_engine.dart';
import 'fleet_confidence_provider.dart';
import 'simulated_safety_score.dart';
import 'native_simulation_bindings.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_options.dart';
import 'simulation_result.dart';

/// Runs safety-score Monte Carlo simulation via a native C library.
///
/// Uses [NativeSimulationBindings] to call the compiled
/// `simulation_run_batch` function through `dart:ffi`.
///
/// Inject a [FleetConfidenceProvider] to supply real fleet data to the
/// native engine. Defaults to [ConstantFleetConfidenceProvider.unavailable] —
/// NO fleet data.
///
/// **With the default, [simulate] takes the honest CPU path and never enters
/// the FFI kernel** (and [SimulationResult.executionMs] is therefore `null`).
/// The native kernel's weighted mean takes a non-nullable fleet term, so it
/// cannot express an absent one; it is skipped rather than fed a number nobody
/// measured. Inject a provider that returns a value to reach the kernel.
class NativeSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates an engine backed by [bindings] (defaults to platform library).
  NativeSafetyScoreSimulationEngine({
    NativeSimulationBindings? bindings,
    FleetConfidenceProvider provider =
        const ConstantFleetConfidenceProvider.unavailable(),
  }) : _bindings = bindings ?? NativeSimulationBindings(),
       _provider = provider;

  final NativeSimulationBindings _bindings;
  final FleetConfidenceProvider _provider;

  @override
  SimulationResult simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  }) {
    final fleetConfidence = _provider.confidence;

    // The native kernel's weighted mean takes a NON-nullable fleet term: it has
    // no way to express "no fleet data", and passing any number would fabricate
    // one (0.8 up to 0.5.4 — which raised the score on fleet silence). When the
    // fleet said nothing, we run the honest CPU path, which re-normalises the
    // weights over the terms that were measured. Correctness before throughput.
    if (fleetConfidence == null) {
      return CpuSafetyScoreSimulationEngine(provider: _provider).simulate(
        speed: speed,
        gripFactor: gripFactor,
        surface: surface,
        visibilityMeters: visibilityMeters,
        options: options,
      );
    }

    final response = _bindings.runBatch(
      runs: options.runs,
      seed: options.seed ?? 0,
      speed: speed,
      gripFactor: gripFactor,
      surfaceCode: surface.index,
      visibilityMeters: visibilityMeters,
      fleetConfidence: fleetConfidence,
    );

    return SimulationResult(
      score: SimulatedSafetyScore(
        overall: response.overallMean,
        gripScore: response.gripMean,
        visibilityScore: response.visibilityMean,
        fleetConfidenceScore: response.fleetMean,
      ),
      variance: response.overallVariance,
      incidentCount: response.incidentCount,
      executionMs: response.executionMs,
    );
  }
}