/// Abstract interface for fleet-derived safety confidence.
library;

/// Provider of a fleet confidence score used in safety score simulation.
///
/// Implementations derive a confidence value from real or synthetic fleet data.
/// The score represents how safe road conditions are according to fleet telemetry:
/// 1.0 = fleet reports consistently safe conditions, 0.0 = fleet reports danger.
///
/// Inject an implementation into [CpuSafetyScoreSimulationEngine],
/// [NativeSafetyScoreSimulationEngine], or [SafetyScoreSimulator].
/// The default is [ConstantFleetConfidenceProvider] (0.8) — the L1 baseline.
abstract interface class FleetConfidenceProvider {
  /// Fleet-derived safety confidence in the inclusive range [0.0, 1.0].
  ///
  /// Higher = fleet data indicates safe road conditions.
  /// Lower = fleet data indicates hazardous conditions (ice, snow).
  double get confidence;
}
