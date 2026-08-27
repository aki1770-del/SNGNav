/// Abstract interface for fleet-derived safety confidence.
library;

/// Provider of a fleet confidence score used in safety score simulation.
///
/// Implementations derive a confidence value from real or synthetic fleet data.
/// The score represents how safe road conditions are according to fleet telemetry:
/// 1.0 = fleet reports consistently safe conditions, 0.0 = fleet reports danger.
///
/// Inject an implementation into [CpuSafetyScoreSimulationEngine],
/// [NativeSafetyScoreSimulationEngine], or [SafetyScoreSimulator]. Their
/// default is [ConstantFleetConfidenceProvider.unavailable] — NO fleet data.
/// Up to 0.6.0 the default was `ConstantFleetConfidenceProvider()` (0.8),
/// which reported an absence as a measurement.
abstract interface class FleetConfidenceProvider {
  /// Fleet-derived safety confidence in the inclusive range `[0.0, 1.0]`, or
  /// **`null` when there is NO fleet data**.
  ///
  /// Higher = fleet data indicates safe road conditions.
  /// Lower = fleet data indicates hazardous conditions (ice, snow).
  ///
  /// `null` means the fleet said NOTHING. It is not a low confidence and it is
  /// not a high one. Up to 0.5.4 this was a non-nullable `double` and absence
  /// was filled with `0.8` — an optimistic number folded into the overall
  /// safety score with weight 0.2, so silence from the fleet RAISED the
  /// computed score. A consumer must handle `null` by leaving the term OUT
  /// (see `SimulatedSafetyScore`), never by substituting a value.
  double? get confidence;
}
