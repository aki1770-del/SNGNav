library;

import 'package:navigation_safety/navigation_safety_core.dart';

import '../models/road_surface_state.dart';
import 'native_simulation_bindings.dart';
import 'safety_score_simulation_engine.dart';
import 'simulation_options.dart';

class NativeSafetyScoreSimulationEngine implements SafetyScoreSimulationEngine {
  NativeSafetyScoreSimulationEngine({NativeSimulationBindings? bindings})
    : _bindings = bindings ?? NativeSimulationBindings();

  final NativeSimulationBindings _bindings;

  @override
  SafetyScore simulate({
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

    return SafetyScore(
      overall: response.overallMean,
      gripScore: response.gripMean,
      visibilityScore: response.visibilityMean,
      fleetConfidenceScore: response.fleetMean,
    );
  }
}