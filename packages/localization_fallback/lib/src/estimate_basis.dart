/// Which input produced an estimate's position.
library;

/// The provenance of an emitted position — which input it actually came from.
///
/// Carried on every [LocalizationEstimate] so the app can be honest about
/// where the dot came from, never just how confident it looks.
enum EstimateBasis {
  /// The position is a current, trusted GPS fix.
  trustedGpsFix,

  /// The position came from the injected dead-reckoning seam (e.g. a Kalman
  /// dead-reckoning estimate), NOT from GPS.
  deadReckoning,

  /// No dead-reckoning seam was available (or it returned null), so the
  /// position is the last trusted fix held frozen in place. The world has
  /// moved on but our knowledge has not — radius grows to say so.
  lastKnownPosition,

  /// No trusted baseline has ever been seen. The position is an untrusted raw
  /// fix used only as a coarse guess; mode is `lost`.
  unanchoredGuess,
}
