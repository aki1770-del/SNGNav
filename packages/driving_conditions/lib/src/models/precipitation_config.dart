/// Precipitation visual parameters derived from weather conditions.
///
/// Provides particle count, velocity ranges, size ranges, and lifetime
/// for rendering precipitation effects. This is computation data, not
/// a renderer — application code decides how to draw particles.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';

class PrecipitationConfig extends Equatable {
  /// Number of particles to render.
  final int particleCount;

  /// Minimum particle velocity in m/s.
  final double minVelocity;

  /// Maximum particle velocity in m/s.
  final double maxVelocity;

  /// Minimum particle size in logical pixels.
  final double minSize;

  /// Maximum particle size in logical pixels.
  final double maxSize;

  /// Particle lifetime in seconds.
  final double lifetime;

  const PrecipitationConfig({
    required this.particleCount,
    required this.minVelocity,
    required this.maxVelocity,
    required this.minSize,
    required this.maxSize,
    required this.lifetime,
  });

  /// No precipitation — zero particles.
  static const none = PrecipitationConfig(
    particleCount: 0,
    minVelocity: 0,
    maxVelocity: 0,
    minSize: 0,
    maxSize: 0,
    lifetime: 0,
  );

  /// Derive particle configuration from current weather.
  ///
  /// Particle count formula: `(intensityFactor * 500).round()`.
  /// Velocity and size ranges vary by precipitation type.
  factory PrecipitationConfig.fromCondition(WeatherCondition condition) {
    if (condition.precipType == PrecipitationType.none ||
        condition.intensity == PrecipitationIntensity.none) {
      return none;
    }

    final intensityFactor = switch (condition.intensity) {
      PrecipitationIntensity.light => 0.3,
      PrecipitationIntensity.moderate => 0.6,
      PrecipitationIntensity.heavy => 1.0,
      PrecipitationIntensity.none => 0.0,
    };

    final count = (intensityFactor * 500).round();

    final (minV, maxV, minS, maxS, lt) = switch (condition.precipType) {
      PrecipitationType.snow => (2.0, 4.0, 2.0, 6.0, 4.0),
      PrecipitationType.rain => (7.0, 12.0, 1.0, 3.0, 1.5),
      PrecipitationType.sleet => (4.0, 8.0, 1.5, 4.0, 2.5),
      PrecipitationType.hail => (8.0, 15.0, 3.0, 8.0, 1.0),
      PrecipitationType.none => (0.0, 0.0, 0.0, 0.0, 0.0),
    };

    return PrecipitationConfig(
      particleCount: count,
      minVelocity: minV,
      maxVelocity: maxV,
      minSize: minS,
      maxSize: maxS,
      lifetime: lt,
    );
  }

  @override
  List<Object?> get props => [
        particleCount,
        minVelocity,
        maxVelocity,
        minSize,
        maxSize,
        lifetime,
      ];
}
