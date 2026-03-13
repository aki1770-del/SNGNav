/// Geographic position — the atomic unit of location data.
library;

import 'package:equatable/equatable.dart';

/// A geographic position fix with accuracy and motion metadata.
///
/// The atomic unit of location data in the dead-reckoning pipeline.
/// Carries both the position and quality indicators ([isNavigationGrade],
/// [isHighAccuracy]) so downstream code can react to degrading fixes.
class GeoPosition extends Equatable {
  /// Latitude in decimal degrees (WGS-84).
  final double latitude;

  /// Longitude in decimal degrees (WGS-84).
  final double longitude;

  /// Horizontal accuracy radius in metres.
  ///
  /// Grows during dead reckoning as uncertainty increases.
  final double accuracy;

  /// Altitude in metres above the WGS-84 ellipsoid. [double.nan] if unknown.
  final double altitude;

  /// Ground speed in metres per second. [double.nan] if unknown.
  final double speed;

  /// Heading in degrees clockwise from true north. [double.nan] if unknown.
  final double heading;

  /// Timestamp of this fix (UTC).
  final DateTime timestamp;

  const GeoPosition({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.altitude = double.nan,
    this.speed = double.nan,
    this.heading = double.nan,
    required this.timestamp,
  });

  /// Speed in km/h (convenience getter for display).
  double get speedKmh => speed.isNaN ? double.nan : speed * 3.6;

  /// Whether this fix has useful accuracy for navigation (< 50m).
  bool get isNavigationGrade => accuracy <= 50.0;

  /// Whether this fix has high accuracy (< 10m).
  bool get isHighAccuracy => accuracy <= 10.0;

  @override
  List<Object?> get props => [
        latitude,
        longitude,
        accuracy,
        altitude,
        speed,
        heading,
        timestamp,
      ];

  @override
  String toString() =>
      'GeoPosition($latitude, $longitude ±${accuracy.toStringAsFixed(1)}m)';
}
