/// Coarse estimated road condition for an hourly forecast slot.
///
/// Explore-phase substrate; not a declared-final taxonomy.
enum RoadConditionEstimate { dry, wet, slush, packedSnow, ice, unknown }

/// One hour of forecast input.
class HourlyForecast {
  HourlyForecast({
    required this.hour,
    required this.tempCelsius,
    this.humidityRH,
    this.precipitationMmPerHour,
    this.visibilityMeters,
    this.estimatedRoadCondition,
  });

  /// Wall-clock hour the forecast slot describes.
  final DateTime hour;

  /// Air temperature in Celsius.
  final double tempCelsius;

  /// Relative humidity in percent (`95.0` for 95% RH). Null if unknown.
  ///
  /// UNIT WARNING: `navigation_safety_core`'s `DrivingContext.humidityRH`
  /// is a FRACTION in `[0.0, 1.0]` under the same field name — do not
  /// wire this value across directly; use
  /// `DrivingContext.withPercentHumidity(humidityPercent: ...)`.
  final double? humidityRH;

  /// Precipitation rate in millimetres per hour. Null if unknown.
  final double? precipitationMmPerHour;

  /// Visibility in metres. Null if unknown.
  final double? visibilityMeters;

  /// Caller-supplied road condition estimate, if any.
  final RoadConditionEstimate? estimatedRoadCondition;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HourlyForecast &&
        other.hour == hour &&
        other.tempCelsius == tempCelsius &&
        other.humidityRH == humidityRH &&
        other.precipitationMmPerHour == precipitationMmPerHour &&
        other.visibilityMeters == visibilityMeters &&
        other.estimatedRoadCondition == estimatedRoadCondition;
  }

  @override
  int get hashCode => Object.hash(
    hour,
    tempCelsius,
    humidityRH,
    precipitationMmPerHour,
    visibilityMeters,
    estimatedRoadCondition,
  );
}

/// Hourly forecast bundle the advisor consumes.
class WeatherForecast {
  WeatherForecast({required this.hourly, required this.issuedAt});

  /// Hourly forecast slots, ordered earliest first by convention.
  final List<HourlyForecast> hourly;

  /// When the forecast was produced by the upstream source.
  final DateTime issuedAt;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WeatherForecast &&
        _listEquals(other.hourly, hourly) &&
        other.issuedAt == issuedAt;
  }

  @override
  int get hashCode => Object.hash(Object.hashAll(hourly), issuedAt);
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
