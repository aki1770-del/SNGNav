/// Weather state — current conditions and monitoring status.
///
/// State transitions:
///   unavailable → monitoring (on start + first condition received)
///   unavailable → monitoring (on start, no condition yet — monitoring but empty)
///   monitoring → monitoring (new condition received — updates current)
///   monitoring → unavailable (on stop)
///   monitoring → error (provider error)
///   error → monitoring (restart)
///   any → unavailable (on stop)
///
/// Core state for snow-scenario weather monitoring.
library;

import 'package:equatable/equatable.dart';

import '../models/weather_condition.dart';

/// Weather monitoring status.
enum WeatherStatus {
  /// Weather system not started.
  unavailable,

  /// Actively monitoring — may or may not have conditions yet.
  monitoring,

  /// Provider error.
  error,
}

class WeatherState extends Equatable {
  final WeatherStatus status;
  final WeatherCondition? condition;
  final String? errorMessage;

  const WeatherState({
    required this.status,
    this.condition,
    this.errorMessage,
  });

  const WeatherState.unavailable()
      : status = WeatherStatus.unavailable,
        condition = null,
        errorMessage = null;

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// Whether weather data is being monitored.
  bool get isMonitoring => status == WeatherStatus.monitoring;

  /// Whether a weather condition is available.
  bool get hasCondition => condition != null;

  /// Whether current conditions are hazardous (heavy precip, low visibility,
  /// or ice risk). Returns false if no condition is available.
  bool get isHazardous => condition?.isHazardous ?? false;

  /// Whether it's currently snowing at any intensity.
  bool get isSnowing => condition?.isSnowing ?? false;

  /// Whether ice risk is present.
  bool get hasIceRisk => condition?.iceRisk ?? false;

  /// Whether visibility is reduced (< 1 km).
  bool get hasReducedVisibility => condition?.hasReducedVisibility ?? false;

  WeatherState copyWith({
    WeatherStatus? status,
    WeatherCondition? condition,
    String? errorMessage,
    bool clearCondition = false,
  }) {
    return WeatherState(
      status: status ?? this.status,
      condition: clearCondition ? null : (condition ?? this.condition),
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, condition, errorMessage];

  @override
  String toString() =>
      'WeatherState($status${condition != null ? ", $condition" : ""})';
}
