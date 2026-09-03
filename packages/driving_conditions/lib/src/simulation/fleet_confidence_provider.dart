/// Abstract interface for fleet-derived safety confidence.
library;

/// Provider of a fleet confidence score derived from fleet telemetry.
///
/// The score represents how safe road conditions are according to fleet
/// telemetry: 1.0 = fleet reports consistently safe conditions, 0.0 = fleet
/// reports danger, `null` = the fleet said nothing.
///
/// ## This no longer feeds the safety score (0.7.0)
///
/// Up to 0.6.0 an implementation of this interface was injected into
/// `CpuSafetyScoreSimulationEngine`, `NativeSafetyScoreSimulationEngine` and
/// `SafetyScoreSimulator`, and contributed 20% of the weight of
/// `SimulatedSafetyScore.overall`. Those `provider:` parameters are **removed**,
/// and the score has no fleet term. The reasoning is in `SimulatedSafetyScore`:
/// the term never carried a real reading, and four consecutive fixes were each
/// tuned as though absence were an edge case when it is the only case.
///
/// The interface is kept because reading fleet telemetry is a legitimate thing
/// to want. Use it and [FleetHazardConfidenceAdapter] to obtain a fleet
/// confidence for your own purposes — a display, a log, a decision of your own.
/// This package will simply not present that number as part of a safety score
/// it computes.
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
  /// computed score. Implementations must return `null` for absence rather than
  /// choosing a stand-in value.
  double? get confidence;
}
