/// Geographic position — the atomic unit of location data.
library;

import 'package:equatable/equatable.dart';

/// Where a [GeoPosition]'s coordinate came from.
///
/// A position that was *invented* by extrapolation and a position that was
/// *measured* by a sensor are different kinds of claim, and a consumer must be
/// able to tell them apart from the object alone — not from the provider that
/// produced it, not from a getter read at some later moment, and not from
/// [GeoPosition.accuracy], which does not discriminate: one second of
/// dead reckoning off a clean 8 m urban fix yields 13 m and reads *better*
/// than a genuine 40 m fix under snow-loaded tree cover.
///
/// Each value below corresponds to a real emit site in
/// `DeadReckoningProvider`; none is aspirational.
enum PositionSource {
  /// Straight from the sensor, unmodified. The provider forwarded exactly what
  /// it received.
  measured,

  /// Filter output. A real sensor reading from this update was combined with
  /// the filter's prediction; the coordinate is neither the raw measurement nor
  /// pure invention.
  fused,

  /// Pure prediction. **No sensor reading contributed to this update.** The
  /// coordinate was extrapolated forward from the last known fix under a
  /// constant-velocity assumption. It is where the driver *would* be if
  /// nothing had changed.
  deadReckoned,

  /// The producer did not state a provenance.
  ///
  /// This is the default, and it is deliberately not [measured]: a library
  /// cannot know that an arbitrary caller's coordinate came off a sensor, and
  /// asserting it would manufacture a claim the data does not support. Absence
  /// of provenance is reported as absence, never as a clean bill of health.
  unknown,
}

/// A geographic position fix with accuracy, motion metadata, and provenance.
///
/// The atomic unit of location data in the dead-reckoning pipeline. Carries the
/// position, quality indicators ([isNavigationGrade], [isHighAccuracy]) and —
/// load-bearing when GPS is gone — [source], which says whether the coordinate
/// was measured or invented.
///
/// ```dart
/// provider.positions.listen((pos) {
///   if (pos.isDeadReckoned) {
///     // No sensor reading behind this dot. Say so before she turns on it.
///     showEstimatedPositionWarning(pos.extrapolatedFor);
///   }
/// });
/// ```
class GeoPosition extends Equatable {
  /// Latitude in decimal degrees (WGS-84).
  final double latitude;

  /// Longitude in decimal degrees (WGS-84).
  final double longitude;

  /// Horizontal accuracy radius in metres.
  ///
  /// Grows during dead reckoning as uncertainty increases. **Not a provenance
  /// signal** — see [source]. A short extrapolation off a good fix can report a
  /// smaller radius than a genuine measurement taken in poor conditions.
  final double accuracy;

  /// Altitude in metres above the WGS-84 ellipsoid. [double.nan] if unknown.
  final double altitude;

  /// Ground speed in metres per second. [double.nan] if unknown.
  final double speed;

  /// Heading in degrees clockwise from true north. [double.nan] if unknown.
  final double heading;

  /// Timestamp of this fix (UTC).
  ///
  /// For a [PositionSource.deadReckoned] position this is the moment the
  /// estimate was *emitted*, which is recent — it is **not** the age of the
  /// evidence behind it. Freshness of this field therefore says nothing about
  /// whether a sensor was involved; [source] does, and [extrapolatedFor] says
  /// how far the estimate has run without one.
  final DateTime timestamp;

  /// Where this coordinate came from. Defaults to [PositionSource.unknown].
  final PositionSource source;

  /// How long this estimate has run without a sensor reading.
  ///
  /// [Duration.zero] when a measurement contributed to this update
  /// ([PositionSource.measured], [PositionSource.fused]). `null` when the
  /// producer did not state it.
  ///
  /// This cannot be recovered from [accuracy]: the degradation model is
  /// `baseAccuracy + rate * elapsed`, and `baseAccuracy` is not carried on the
  /// object, so elapsed time is not invertible from the radius alone. Three
  /// seconds of guessing and forty seconds of guessing are different facts for
  /// a driver deciding whether to trust the dot.
  final Duration? extrapolatedFor;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude = double.nan,
    this.speed = double.nan,
    this.heading = double.nan,
    required this.timestamp,
    this.source = PositionSource.unknown,
    this.extrapolatedFor,
  });

  /// Speed in km/h (convenience getter for display).
  double get speedKmh => speed.isNaN ? double.nan : speed * 3.6;

  /// Whether this fix has useful accuracy for navigation (< 50m).
  ///
  /// Says nothing about provenance — a dead-reckoned estimate can pass this.
  bool get isNavigationGrade => accuracy <= 50.0;

  /// Whether this fix has high accuracy (< 10m).
  ///
  /// Says nothing about provenance — a dead-reckoned estimate can pass this.
  bool get isHighAccuracy => accuracy <= 10.0;

  /// Whether this coordinate is the raw, unmodified sensor value.
  ///
  /// False for [PositionSource.fused] (real, but filtered) and for
  /// [PositionSource.unknown] (unstated). To ask the weaker question — "did a
  /// sensor contribute at all?" — use [containsMeasurement].
  bool get isMeasured => source == PositionSource.measured;

  /// Whether a real sensor reading contributed to this update.
  ///
  /// True for [PositionSource.measured] and [PositionSource.fused]. This is
  /// the question a safety consumer usually means.
  bool get containsMeasurement =>
      source == PositionSource.measured || source == PositionSource.fused;

  /// Whether this coordinate is pure prediction with no sensor reading behind
  /// it.
  bool get isDeadReckoned => source == PositionSource.deadReckoned;

  @override
  List<Object?> get props => [
    latitude,
    longitude,
    accuracy,
    altitude,
    speed,
    heading,
    timestamp,
    // Provenance participates in equality on purpose. Without it, a consumer
    // applying `Stream.distinct()` would silently swallow the measured ->
    // dead-reckoned transition whenever it happens at a stationary coordinate
    // — losing exactly the event that matters.
    source,
    extrapolatedFor,
  ];

  @override
  String toString() {
    // Un-stated provenance renders byte-identically to the pre-provenance
    // format, so a producer that has not adopted `source` sees no change. The
    // tag appears only where there is something true to say.
    final tag = source == PositionSource.unknown ? '' : ' ${source.name}';
    return 'GeoPosition($latitude, $longitude '
        '±${accuracy.toStringAsFixed(1)}m$tag)';
  }
}
