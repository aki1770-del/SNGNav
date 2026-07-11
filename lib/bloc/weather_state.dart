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

import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';

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

  /// How old [condition] is, or `null` when there is no condition.
  ///
  /// `Duration.zero` = observed on the latest poll. Anything larger means the
  /// refresh FAILED and this is the last known reading, carried with its real
  /// age (driving_weather's `WeatherStale`). Up to 0.4.4 a failed fetch silently
  /// re-emitted the old condition with a fresh timestamp — stale data wearing a
  /// fresh face. The age is carried so the app can SAY it.
  final Duration? conditionAge;

  const WeatherState({
    required this.status,
    this.condition,
    this.errorMessage,
    this.conditionAge,
  });

  const WeatherState.unavailable()
      : status = WeatherStatus.unavailable,
        condition = null,
        errorMessage = null,
        conditionAge = null;

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// Whether weather data is being monitored.
  bool get isMonitoring => status == WeatherStatus.monitoring;

  /// Whether a weather condition is available.
  bool get hasCondition => condition != null;

  // ---------------------------------------------------------------------------
  // Safety verdicts — TRI-STATE. Never `?? false`.
  //
  // These were four `bool` getters resolving a null condition to `false`:
  //
  //   bool get isHazardous => condition?.isHazardous ?? false;   // <-- the lie
  //
  // driving_weather 0.5.0 removed `bool get isHazardous` from the LIBRARY
  // precisely because a bool silently resolves absence to the safe branch. The
  // app then re-added exactly that with `?? false`, one layer up — in the code
  // that actually ships to the driver. "No data" was rendered as "not
  // hazardous", and the map painted the calm chrome over a road nobody had
  // measured.
  //
  // `?? false` is the single keystroke that restores the original defect and
  // greps as nothing. It must not appear at any of these sites.
  // ---------------------------------------------------------------------------

  /// Are current conditions hazardous? [SafetyVerdict.unknown] when there is no
  /// condition — which is NOT a green light and must render as its own state.
  SafetyVerdict get hazard => condition?.hazard ?? SafetyVerdict.unknown;

  /// Is it snowing? [SafetyVerdict.unknown] when unknown.
  SafetyVerdict get snowing => condition?.snowing ?? SafetyVerdict.unknown;

  /// Is visibility reduced (< 1 km)? [SafetyVerdict.unknown] when unknown.
  SafetyVerdict get reducedVisibility =>
      condition?.reducedVisibility ?? SafetyVerdict.unknown;

  /// Ice risk: `true` = ice, `false` = no ice, **`null` = NOT MEASURED**.
  bool? get iceRisk => condition?.iceRisk;

  /// True only on POSITIVE evidence of a hazard. An absent condition is not
  /// hazardous and not benign — see [isConditionUnknown].
  bool get isHazardous => hazard == SafetyVerdict.hazardous;

  /// True when we do not know whether the road is safe. Render this as a
  /// DISTINCT state — never as the same calm chrome as "not hazardous".
  bool get isConditionUnknown => hazard == SafetyVerdict.unknown;

  /// True only on POSITIVE evidence of snow.
  bool get isSnowing => snowing == SafetyVerdict.hazardous;

  /// True only on POSITIVE evidence of ice.
  bool get hasIceRisk => iceRisk == true;

  /// True only on POSITIVE evidence of reduced visibility.
  bool get hasReducedVisibility =>
      reducedVisibility == SafetyVerdict.hazardous;

  /// True when [condition] is a last-known reading that could not be refreshed.
  bool get isStale => (conditionAge ?? Duration.zero) > Duration.zero;

  WeatherState copyWith({
    WeatherStatus? status,
    WeatherCondition? condition,
    String? errorMessage,
    Duration? conditionAge,
    bool clearCondition = false,
  }) {
    return WeatherState(
      status: status ?? this.status,
      condition: clearCondition ? null : (condition ?? this.condition),
      errorMessage: errorMessage,
      conditionAge:
          clearCondition ? null : (conditionAge ?? this.conditionAge),
    );
  }

  @override
  List<Object?> get props => [status, condition, errorMessage, conditionAge];

  @override
  String toString() =>
      'WeatherState($status${condition != null ? ", $condition" : ""})';
}
