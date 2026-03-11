/// Abstract interface for safety score simulation engines.
///
/// Implementations provide the compute strategy (CPU, GPU, etc.)
/// while the public [SafetyScoreSimulator] handles backend selection.
library;

import 'package:navigation_safety/navigation_safety_core.dart';

import '../models/road_surface_state.dart';
import 'simulation_options.dart';

/// Engine contract for safety score Monte Carlo simulation.
///
/// The Dart API must NOT expose GPU buffer IDs, shader identifiers,
/// engine scenes, native pointers, or platform channels (A306 §5.3).
abstract interface class SafetyScoreSimulationEngine {
  /// Run a Monte Carlo simulation and return the mean [SafetyScore].
  SafetyScore simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  });
}
