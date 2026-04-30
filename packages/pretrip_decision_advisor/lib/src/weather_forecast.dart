/// Estimated road condition for a forecast hour.
enum RoadConditionEstimate {
  dry,
  wet,
  slush,
  packedSnow,
  ice,

  /// Forecast does not have enough information to estimate. The
  /// advisor should treat this as a degraded input.
  unknown,
}

/// Forecast for a single hour of the trip window.
class HourlyForecast {
  const HourlyForecast({
    required this.localHourStart,
    required this.airTemperatureC,
    required this.roadCondition,
    this.precipitationProbability,
  });

  /// Local-time start of the hour this forecast covers.
  final DateTime localHourStart;

  /// Air temperature in degrees Celsius.
  final double airTemperatureC;

  /// Estimated road condition for this hour.
  final RoadConditionEstimate roadCondition;

  /// Precipitation probability in [0.0, 1.0] if known.
  final double? precipitationProbability;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is HourlyForecast &&
        other.localHourStart == localHourStart &&
        other.airTemperatureC == airTemperatureC &&
        other.roadCondition == roadCondition &&
        other.precipitationProbability == precipitationProbability;
  }

  @override
  int get hashCode => Object.hash(
        localHourStart,
        airTemperatureC,
        roadCondition,
        precipitationProbability,
      );
}

/// Caller-supplied forecast covering the trip window.
class WeatherForecast {
  const WeatherForecast({required this.hours});

  /// Hourly entries covering at least the planned trip window.
  /// May be empty; the advisor must degrade gracefully.
  final List<HourlyForecast> hours;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! WeatherForecast) return false;
    if (other.hours.length != hours.length) return false;
    for (var i = 0; i < hours.length; i++) {
      if (other.hours[i] != hours[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(hours);
}
