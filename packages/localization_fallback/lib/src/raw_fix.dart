/// A raw position fix, exactly as a geolocator / GNSS receiver emits it.
library;

/// A single raw position fix as it arrives from the device GNSS / geolocator.
///
/// This is the UNFILTERED input. It carries no judgement about whether it can
/// be trusted — that judgement is supplied separately as a [trust] signal when
/// the fix is fed to the controller (the caller maps it from a position-trust
/// verdict such as `position_integrity`).
class RawFix {
  /// Latitude in decimal degrees (WGS-84).
  final double latitude;

  /// Longitude in decimal degrees (WGS-84).
  final double longitude;

  /// Receiver-reported horizontal accuracy radius, in metres.
  ///
  /// This is the receiver's OWN claim. A spoofed or multipath fix can report a
  /// small accuracy while being far wrong — which is exactly why a separate
  /// trust signal exists and why this number is never taken as ground truth.
  final double accuracyMeters;

  /// When the fix was observed (UTC recommended).
  final DateTime timestamp;

  /// Ground speed in metres per second, or `null` if unknown.
  final double? speedMps;

  /// Heading in degrees clockwise from true north, or `null` if unknown.
  final double? headingDegrees;

  const RawFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
    this.speedMps,
    this.headingDegrees,
  });

  /// Whether the coordinates and accuracy are finite, real numbers.
  ///
  /// A fix that fails this check cannot be trusted regardless of any trust
  /// signal — garbage in is never confident out.
  bool get hasFiniteGeometry =>
      latitude.isFinite &&
      longitude.isFinite &&
      accuracyMeters.isFinite &&
      accuracyMeters >= 0;

  @override
  String toString() => 'RawFix(lat: $latitude, lon: $longitude, '
      'acc: ${accuracyMeters}m, t: $timestamp)';
}
