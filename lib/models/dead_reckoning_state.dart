/// Dead reckoning state vector — linear extrapolation from last GPS fix.
///
/// When GPS signal is lost (e.g., tunnel), the state vector predicts the
/// driver's position using the last known speed and heading. Accuracy
/// degrades linearly over time (+5m/sec) to honestly signal uncertainty.
///
/// Part of the configurable location pipeline (see provider_config.dart).
/// Safety: ASIL-QM — display only, no vehicle control input.
library;

import 'dart:math' as math;

import 'package:equatable/equatable.dart';

import 'geo_position.dart';

/// Linear dead reckoning state vector.
///
/// Extrapolates position from the last valid GPS fix using constant-velocity
/// assumption: the driver continues at the same speed and heading.
class DeadReckoningState extends Equatable {
  /// Latitude in degrees (WGS84).
  final double latitude;

  /// Longitude in degrees (WGS84).
  final double longitude;

  /// Speed in m/s from the last GPS fix.
  final double speed;

  /// Heading in degrees (0 = north, clockwise) from the last GPS fix.
  final double heading;

  /// Accuracy of the original GPS fix in metres.
  final double baseAccuracy;

  /// Timestamp of the last valid GPS fix.
  final DateTime lastGpsTime;

  /// Number of extrapolation steps performed since GPS loss.
  final int extrapolationCount;

  /// Maximum accuracy (metres) before DR stops emitting.
  /// Safety boundary: beyond this, position is too uncertain to display.
  static const double maxAccuracy = 500.0;

  /// Accuracy degradation rate: metres per second of GPS loss.
  static const double degradationRate = 5.0;

  /// Metres per degree of latitude (WGS84 approximation).
  static const double _metresPerDegreeLat = 111320.0;

  const DeadReckoningState({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.heading,
    required this.baseAccuracy,
    required this.lastGpsTime,
    this.extrapolationCount = 0,
  });

  /// Creates a [DeadReckoningState] from a valid GPS [GeoPosition].
  ///
  /// Returns `null` if speed or heading are NaN — cannot extrapolate
  /// without knowing direction and velocity.
  static DeadReckoningState? fromGeoPosition(GeoPosition pos) {
    if (pos.speed.isNaN || pos.heading.isNaN) return null;
    if (pos.speed < 0) return null;

    return DeadReckoningState(
      latitude: pos.latitude,
      longitude: pos.longitude,
      speed: pos.speed,
      heading: pos.heading,
      baseAccuracy: pos.accuracy,
      lastGpsTime: pos.timestamp,
    );
  }

  /// Whether this state can produce meaningful extrapolation.
  bool get canExtrapolate => !speed.isNaN && !heading.isNaN && speed >= 0;

  /// Whether the estimated accuracy has exceeded the safety cap.
  bool get isAccuracyExceeded {
    final elapsed = DateTime.now().difference(lastGpsTime).inMilliseconds;
    final estimatedAccuracy =
        baseAccuracy + degradationRate * (elapsed / 1000.0);
    return estimatedAccuracy > maxAccuracy;
  }

  /// Predict the next position after [dt] from the current state.
  ///
  /// Uses flat-Earth approximation (accurate within ~1km at mid-latitudes).
  /// Returns a new [DeadReckoningState] with updated lat/lon and incremented
  /// extrapolation count.
  DeadReckoningState predict(Duration dt) {
    if (!canExtrapolate || speed == 0) {
      return DeadReckoningState(
        latitude: latitude,
        longitude: longitude,
        speed: speed,
        heading: heading,
        baseAccuracy: baseAccuracy,
        lastGpsTime: lastGpsTime,
        extrapolationCount: extrapolationCount + 1,
      );
    }

    final dtSeconds = dt.inMilliseconds / 1000.0;
    final distance = speed * dtSeconds; // metres

    // Convert heading to radians (0 = north, clockwise).
    final headingRad = heading * math.pi / 180.0;

    // Flat-Earth displacement.
    final dLat = distance * math.cos(headingRad) / _metresPerDegreeLat;
    final latRad = latitude * math.pi / 180.0;
    final dLon = distance *
        math.sin(headingRad) /
        (_metresPerDegreeLat * math.cos(latRad));

    return DeadReckoningState(
      latitude: latitude + dLat,
      longitude: longitude + dLon,
      speed: speed,
      heading: heading,
      baseAccuracy: baseAccuracy,
      lastGpsTime: lastGpsTime,
      extrapolationCount: extrapolationCount + 1,
    );
  }

  /// Estimated accuracy at [now], degrading linearly from GPS loss.
  double accuracyAt(DateTime now) {
    final elapsed = now.difference(lastGpsTime).inMilliseconds / 1000.0;
    return baseAccuracy + degradationRate * elapsed;
  }

  /// Convert the current state to a [GeoPosition] with degraded accuracy.
  ///
  /// The [now] parameter allows deterministic testing. Defaults to
  /// [DateTime.now] in production.
  GeoPosition toGeoPosition({DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    return GeoPosition(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracyAt(timestamp),
      speed: speed,
      heading: heading,
      timestamp: timestamp,
    );
  }

  @override
  List<Object?> get props => [
        latitude,
        longitude,
        speed,
        heading,
        baseAccuracy,
        lastGpsTime,
        extrapolationCount,
      ];

  @override
  String toString() =>
      'DeadReckoningState($latitude, $longitude, '
      '${speed.toStringAsFixed(1)} m/s, '
      '${heading.toStringAsFixed(0)}°, '
      'steps=$extrapolationCount)';
}
