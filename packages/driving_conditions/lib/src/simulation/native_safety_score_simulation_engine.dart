/// Native (C FFI) implementation of [SafetyScoreSimulationEngine].
///
/// Delegates Monte Carlo safety-score simulation to a compiled C library
/// for higher throughput than the pure-Dart [CpuSafetyScoreSimulationEngine].
library;

import 'package:navigation_safety/navigation_safety_core.dart';

import '../models/road_surface_state.dart';
import 'constant_fleet_confidence_provider.dart';
import 'fleet_confidence_provider.dart';
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
/// native engine. Defaults to [ConstantFleetConfidenceProvider] (0.8).
class NativeSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  /// Creates an engine backed by [bindings] (defaults to platform library).
  NativeSafetyScoreSimulationEngine({
    NativeSimulationBindings? bindings,
    FleetConfidenceProvider provider = const ConstantFleetConfidenceProvider(),
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
    final response = _bindings.runBatch(
      runs: options.runs,
      seed: options.seed ?? 0,
      speed: speed,
      gripFactor: gripFactor,
      surfaceCode: surface.index,
      visibilityMeters: visibilityMeters,
      fleetConfidence: _provider.confidence,
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