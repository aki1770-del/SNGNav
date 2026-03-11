/// Simulation backend selection for [SafetyScoreSimulationEngine].
///
/// Controls which compute implementation runs the Monte Carlo simulation.
library;

/// Backend preference for safety score simulation.
///
/// - [auto]: GPU when available, CPU fallback (default).
/// - [cpu]: Force pure Dart implementation.
/// - [gpu]: Force native GPU — fails if unavailable.
enum SimulationBackend {
  /// Choose GPU when available, CPU otherwise.
  auto,

  /// Pure Dart Monte Carlo (always available).
  cpu,

  /// Native GPU compute — fails explicitly if unavailable.
  gpu,
}
