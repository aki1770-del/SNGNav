/// A single fused position fix — the minimal input the integrity floor needs.
///
/// This is deliberately NOT a `geolocator` `Position`: the floor is pure Dart
/// with zero plugin dependencies, so it builds and runs anywhere (server, CLI,
/// test, low-end ARM head unit) without a Flutter engine. Map your platform's
/// location object into a [PositionFix] — latitude/longitude in degrees,
/// horizontal accuracy in metres, and the fix's own timestamp — and hand it to
/// [PositionIntegrityMonitor.update].
class PositionFix {
  /// A fix is intentionally constructible with any values — a degraded sensor
  /// really does emit NaN / out-of-range coordinates, and the whole point of
  /// this package is to HANDLE such a fix gracefully (the monitor returns
  /// [IntegrityStatus.failed] for it), never to crash on it. Validation lives
  /// in the monitor, in every build mode, not in a debug-only assert here.
  const PositionFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMetres,
    required this.timestamp,
  });

  /// Latitude in degrees (WGS-84).
  final double latitude;

  /// Longitude in degrees (WGS-84).
  final double longitude;

  /// The platform's own reported horizontal accuracy, in metres. Larger means
  /// less certain.
  ///
  /// This is NEVER treated as ground truth. The entire reason this package
  /// exists is that a confident (small) accuracy number can still accompany a
  /// physically impossible — i.e. lying — position. Accuracy is used only to
  /// scale the stationary-jitter tolerance, never to decide trust on its own.
  final double accuracyMetres;

  /// The instant this fix was sampled. The monitor reasons about motion from
  /// the time deltas between successive fixes, so this must be the fix's real
  /// timestamp, not the moment it was received.
  final DateTime timestamp;

  @override
  String toString() =>
      'PositionFix($latitude, $longitude, ±${accuracyMetres}m @ '
      '${timestamp.toIso8601String()})';
}
