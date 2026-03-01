/// Weather condition — the atomic unit of weather data in SNGNav.
///
/// Models current weather at the vehicle's location. Fields cover
/// precipitation type, intensity, wind, visibility, and ice risk.
///
/// Weather sources are pluggable: Open-Meteo (real) or simulated (demo).
/// Configured via `--dart-define=WEATHER_PROVIDER`.
library;

import 'package:equatable/equatable.dart';

/// Type of precipitation observed.
enum PrecipitationType {
  /// No precipitation.
  none,

  /// Rain.
  rain,

  /// Snow — the primary scenario for SNGNav.
  snow,

  /// Sleet (mixed rain/snow).
  sleet,

  /// Hail.
  hail,
}

/// Intensity of precipitation.
enum PrecipitationIntensity {
  /// No precipitation.
  none,

  /// Light — minor impact on driving.
  light,

  /// Moderate — reduced visibility, increased stopping distance.
  moderate,

  /// Heavy — significant safety impact. May trigger safety alert.
  heavy,
}

class WeatherCondition extends Equatable {
  /// Type of precipitation (none, rain, snow, sleet, hail).
  final PrecipitationType precipType;

  /// Intensity of precipitation.
  final PrecipitationIntensity intensity;

  /// Temperature in Celsius. Snow threshold ≤ 0°C.
  final double temperatureCelsius;

  /// Visibility in metres. 10000 = clear, < 1000 = reduced, < 200 = hazardous.
  final double visibilityMeters;

  /// Wind speed in km/h.
  final double windSpeedKmh;

  /// Whether road icing / black ice risk is present.
  final bool iceRisk;

  /// When this condition was observed.
  final DateTime timestamp;

  const WeatherCondition({
    required this.precipType,
    required this.intensity,
    required this.temperatureCelsius,
    required this.visibilityMeters,
    required this.windSpeedKmh,
    this.iceRisk = false,
    required this.timestamp,
  });

  /// Clear weather — no precipitation, good visibility, no ice.
  const WeatherCondition.clear({required this.timestamp})
      : precipType = PrecipitationType.none,
        intensity = PrecipitationIntensity.none,
        temperatureCelsius = 5.0,
        visibilityMeters = 10000.0,
        windSpeedKmh = 0.0,
        iceRisk = false;

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// True when snow is falling at any intensity.
  bool get isSnowing =>
      precipType == PrecipitationType.snow &&
      intensity != PrecipitationIntensity.none;

  /// True when visibility is below 1 km (reduced).
  bool get hasReducedVisibility => visibilityMeters < 1000;

  /// True when conditions are hazardous — heavy precip, very low visibility,
  /// or ice risk. Used to decide if a safety alert should be raised.
  bool get isHazardous =>
      iceRisk ||
      intensity == PrecipitationIntensity.heavy ||
      visibilityMeters < 200;

  /// True when temperature is at or below freezing.
  bool get isFreezing => temperatureCelsius <= 0;

  @override
  List<Object?> get props => [
        precipType,
        intensity,
        temperatureCelsius,
        visibilityMeters,
        windSpeedKmh,
        iceRisk,
        timestamp,
      ];

  @override
  String toString() =>
      'WeatherCondition(${precipType.name} ${intensity.name}, '
      '${temperatureCelsius.toStringAsFixed(1)}°C, '
      'vis=${visibilityMeters.toStringAsFixed(0)}m, '
      'wind=${windSpeedKmh.toStringAsFixed(0)}km/h'
      '${iceRisk ? ", ICE" : ""})';
}
