/// Configuration for a safety score simulation run.
library;

import 'package:equatable/equatable.dart';

import 'simulation_backend.dart';

/// Options controlling how [SafetyScoreSimulationEngine] runs a simulation.
///
/// All fields have sensible defaults for production use.
/// Provide [seed] for deterministic results (required for testing).
class SimulationOptions extends Equatable {
  /// Creates simulation options.
  ///
  /// Defaults: [backend] = [SimulationBackend.auto], [runs] = 1000,
  /// [seed] = null (non-deterministic).
  const SimulationOptions({
    this.backend = SimulationBackend.auto,
    this.seed,
    this.runs = 1000,
  });

  /// Which compute backend to use.
  final SimulationBackend backend;

  /// Random seed for deterministic results. Null = non-deterministic.
  final int? seed;

  /// Number of Monte Carlo iterations.
  final int runs;

  @override
  List<Object?> get props => [backend, seed, runs];
}
