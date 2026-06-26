/// The dead-reckoning seam type and its return value.
library;

/// A dead-reckoning position estimate, supplied by the injected seam.
///
/// The caller backs the seam with whatever dead-reckoning engine they like
/// (for example the `kalman_dr` package). This package never integrates motion
/// itself; it only consumes the seam's output and degrades its confidence
/// truthfully.
class DeadReckoningEstimate {
  /// Latitude in decimal degrees (WGS-84).
  final double latitude;

  /// Longitude in decimal degrees (WGS-84).
  final double longitude;

  /// The seam's own accuracy claim in metres, or `null` if it does not model
  /// one. The controller never lets the emitted radius drop BELOW this, and it
  /// applies its own growth floor on top, so a seam that under-reports drift
  /// cannot make the estimate look more certain than time allows.
  final double? estimatedAccuracyMeters;

  const DeadReckoningEstimate({
    required this.latitude,
    required this.longitude,
    this.estimatedAccuracyMeters,
  });

  /// Whether the coordinates are finite, real numbers.
  bool get hasFiniteGeometry => latitude.isFinite && longitude.isFinite;
}

/// A pull-based dead-reckoning seam: given a moment in time, return the best
/// dead-reckoned position as of then, or `null` if dead reckoning cannot
/// produce one (no seam wired, no motion model, or it has itself given up).
///
/// Returning `null` is honest and supported — the controller falls back to the
/// last trusted position held frozen, and says so via [EstimateBasis].
typedef DeadReckoningSeam = DeadReckoningEstimate? Function(DateTime asOf);
