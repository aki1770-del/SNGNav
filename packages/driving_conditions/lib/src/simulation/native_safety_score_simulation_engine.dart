/// Native (C FFI) implementation of [SafetyScoreSimulationEngine].
///
/// Delegates Monte Carlo safety-score simulation to a compiled C library
/// for higher throughput than the pure-Dart [CpuSafetyScoreSimulationEngine].
library;

import 'package:navigation_safety/navigation_safety_core.dart';

import '../models/road_surface_state.dart';
import 'native_simulation_bindings.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_options.dart';
import 'simulation_result.dart';

/// Runs safety-score Monte Carlo simulation via a native C library.
///
/// Uses [NativeSimulationBindings] to call the compiled
/// `simulation_run_batch` function through `dart:ffi`.
///
/// Provides variance, incident count, and execution time in addition
/// to the mean [SafetyScore] — data that the C engine computes at
/// no extra cost and that [CpuSafetyScoreSimulationEngine] also now exposes.
class NativeSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates an engine backed by [bindings] (defaults to platform library).
  NativeSafetyScoreSimulationEngine({NativeSimulationBindings? bindings})
    : _bindings = bindings ?? NativeSimulationBindings();

  final NativeSimulationBindings _bindings;

  @override
  SimulationResult simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  }) {
    final response = _bindings.runBatch(
      runs: options.runs,
      seed: options.seed ?? 0,
      speed: speed,
      gripFactor: gripFactor,
      surfaceCode: surface.index,
      visibilityMeters: visibilityMeters,
    );

    return SimulationResult(
      score: SafetyScore(
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