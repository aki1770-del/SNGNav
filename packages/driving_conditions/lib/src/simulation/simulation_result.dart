/// Result of a Monte Carlo safety score simulation run.
library;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety/navigation_safety_core.dart';

/// The full output of a [SafetyScoreSimulationEngine.simulate] call.
///
/// Wraps the mean [SafetyScore] and adds statistical measures that a
/// single-point score cannot express: variance across runs, incident
/// count (runs where overall score fell below the danger threshold),
/// and — for the native engine — wall-clock execution time.
class SimulationResult extends Equatable {
  /// Creates a simulation result.
  const SimulationResult({
    required this.score,
    required this.variance,
    required this.incidentCount,
    this.executionMs,
  });

  /// Mean [SafetyScore] across all Monte Carlo runs.
  final SafetyScore score;

  /// Variance of the overall score across all runs.
  ///
  /// Low variance: conditions are consistently dangerous or consistently safe.
  /// High variance: conditions are mixed — sensor noise or edge-case surfaces.
  final double variance;

  /// Number of runs where the overall score fell below 0.4 (danger threshold).
  ///
  /// Divide by the run count to get incident probability.
  final int incidentCount;

  /// Wall-clock execution time in milliseconds.
  ///
  /// Non-null only when the native engine is used. Null for the CPU engine.
  final double? executionMs;

  @override
  List<Object?> get props => [score, variance, incidentCount, executionMs];
}
