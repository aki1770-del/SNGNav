/// Source-neutral measured-visibility observation + its departure-hour merge.
///
/// A real visibility sensor reading near the driver's point, from any road- or
/// weather-network source: Fintraffic's Digitraffic road-weather network in
/// Finland (`digitraffic_visibility.dart`) or the Japan Meteorological Agency's
/// AMeDAS surface network in Japan (`jma_visibility.dart`). The pre-trip
/// advisor reaches the whiteout/severe band ONLY from a real measured value
/// like this — never from a warning or an estimate — so both providers produce
/// this same typed observation and the merge logic lives here once, not twice.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

/// One real visibility measurement near a requested point.
class VisibilityObservation {
  const VisibilityObservation({
    required this.meters,
    required this.stationId,
    required this.stationName,
    required this.measuredAt,
    required this.distanceKm,
  });

  /// Measured visibility in metres.
  final double meters;

  /// The source network's station id the measurement came from (Digitraffic
  /// numeric id, or the JMA AMeDAS 5-digit station code parsed to int — both
  /// are lossless integers).
  final int stationId;

  /// Station name as published (e.g. `vt1_Espoo_Nupuri`, or a JMA station's
  /// romanised name such as `Akita`).
  final String stationName;

  /// When the sensor measured this value (from the publisher, UTC→local).
  final DateTime measuredAt;

  /// Great-circle distance from the requested point to the station.
  final double distanceKm;
}

/// Merges a NOW visibility observation into the single forecast slot that
/// covers [departure] — and no other. A station measurement is valid for the
/// hour she is leaving in; projecting it into later forecast hours would
/// fabricate forecast visibility the publisher never issued. The measured
/// value takes precedence over any forecast visibility for that hour (a real
/// sensor beats a forecast for "now"). Returns the forecast unchanged when
/// no slot covers the departure.
WeatherForecast mergeObservedVisibility(
  WeatherForecast forecast,
  VisibilityObservation observation,
  DateTime departure,
) {
  final hourly = [
    for (final s in forecast.hourly)
      if (!s.hour.isAfter(departure) &&
          s.hour.add(const Duration(hours: 1)).isAfter(departure))
        HourlyForecast(
          hour: s.hour,
          tempCelsius: s.tempCelsius,
          humidityRH: s.humidityRH,
          precipitationMmPerHour: s.precipitationMmPerHour,
          visibilityMeters: observation.meters,
          estimatedRoadCondition: s.estimatedRoadCondition,
        )
      else
        s,
  ];
  return WeatherForecast(hourly: hourly, issuedAt: forecast.issuedAt);
}
