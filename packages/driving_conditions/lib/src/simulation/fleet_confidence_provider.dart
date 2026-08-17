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
  ///
  /// An implementation that cannot compute a confidence at all may return a
  /// non-finite value (NaN or infinite). That is **not** a point on the scale
  /// and must not be read as one: it means "this could not be computed", not
  /// "safe" and not "dangerous". Do not clamp it — `num.clamp` maps NaN and
  /// `+Infinity` to the upper bound, which would report maximum safety.
  /// Consumers that must act on every value should decide explicitly what an
  /// uncomputable confidence means for them; `navigation_safety_core` treats
  /// it as worst-case so that it alerts.
  double get confidence;
}
