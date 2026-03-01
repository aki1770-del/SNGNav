/// Geographic position — the atomic unit of location data in SNGNav.
///
/// Used throughout the location pipeline by all providers and BLoCs.
library;

import 'package:equatable/equatable.dart';

class GeoPosition extends Equatable {
  final double latitude;
  final double longitude;
  final double accuracy; // metres
  final double altitude;
  final double speed; // m/s
  final double heading; // degrees, 0 = north, clockwise
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
