/// Driving conditions — pure Dart computation models for weather-based
/// driving safety assessment.
///
/// Provides road surface classification, precipitation parameters,
/// visibility degradation, combined assessment, and Monte Carlo
/// safety score simulation.
///
/// No Flutter dependency — safe to use from any Dart environment.
library;

export 'src/assessment/driving_condition_assessment.dart';
export 'src/models/precipitation_config.dart';
export 'src/models/road_surface_state.dart';
export 'src/models/visibility_degradation.dart';
export 'src/simulation/cpu_safety_score_simulation_engine.dart';
export 'src/simulation/safety_score_simulation_engine.dart';
export 'src/simulation/safety_score_simulator.dart';
export 'src/simulation/simulation_backend.dart';
export 'src/simulation/simulation_options.dart';
