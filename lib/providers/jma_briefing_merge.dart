/// Merges an official JMA winter-snow advisory into a pre-trip forecast so the
/// Japanese driver's briefing is not blind to the hazard this project is built
/// around.
///
/// Measured at the source (2026-06-13): the live Japan forecast source (the MET Norway
/// compact product) carries NO visibility and NO road-surface state
/// (`met_norway_hourly_forecast.dart`: both mapped null ALWAYS), so the Nagoya
/// driver's briefing runs on temperature + precipitation alone and can never
/// reach the snow/ice hazard bands. The Nordic path closes that gap with real
/// Digitraffic visibility sensors; the Japan path had no equivalent. When JMA
/// has ISSUED a winter advisory for her area, that is authoritative PRESENT
/// data — an official warning, not an estimate — so we map it onto the
/// road-condition field the advisor already understands, for the departure
/// window only.
///
/// Honesty rules (binding, mirroring the Digitraffic visibility merge):
///  - Applies ONLY for a recognized JMA snow-class event name; any other event
///    is a no-op (the forecast is returned unchanged).
///  - Sets `estimatedRoadCondition` ONLY where it is null or `unknown` — it
///    never overrides a real measured/forecast road condition.
///  - Touches ONLY the road-condition field; it NEVER fabricates a visibility
///    number. A snow warning is not a measured visibility, so the advisor's
///    no-estimate rule stands and the whiteout band is reached only by real
///    visibility data, never by a warning.
///  - Applies only to the departure-window hours, never the whole feed.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

/// The road condition an official JMA snow-class advisory implies, or null when
/// [jmaEventName] is not a recognized snow-class warning.
///
/// 着雪 (snow accretion / icing) is an icing surface → [RoadConditionEstimate.ice];
/// 大雪 / 暴風雪 (heavy snow / blizzard) → [RoadConditionEstimate.packedSnow].
RoadConditionEstimate? roadConditionForJmaSnowAdvisory(String jmaEventName) {
  if (jmaEventName.contains('着雪')) return RoadConditionEstimate.ice;
  if (jmaEventName.contains('大雪') || jmaEventName.contains('暴風雪')) {
    return RoadConditionEstimate.packedSnow;
  }
  return null;
}

/// Returns [forecast] with the JMA advisory's implied road condition applied to
/// the departure-window slots that currently have no road-condition data.
///
/// The window is `[windowStart, windowStart + windowDuration)`; a slot at hour
/// H covers `[H, H + 1h)`. See the file header for the binding honesty rules.
WeatherForecast mergeJmaWinterAdvisory(
  WeatherForecast forecast, {
  required String jmaEventName,
  required DateTime windowStart,
  required Duration windowDuration,
}) {
  final road = roadConditionForJmaSnowAdvisory(jmaEventName);
  if (road == null) return forecast; // not a snow-class advisory → unchanged.

  final end = windowStart.add(windowDuration);
  final merged = <HourlyForecast>[
    for (final s in forecast.hourly)
      if ((s.estimatedRoadCondition == null ||
              s.estimatedRoadCondition == RoadConditionEstimate.unknown) &&
          s.hour.isBefore(end) &&
          s.hour.add(const Duration(hours: 1)).isAfter(windowStart))
        HourlyForecast(
          hour: s.hour,
          tempCelsius: s.tempCelsius,
          humidityRH: s.humidityRH,
          precipitationMmPerHour: s.precipitationMmPerHour,
          visibilityMeters: s.visibilityMeters, // never touched.
          estimatedRoadCondition: road,
        )
      else
        s,
  ];
  return WeatherForecast(hourly: merged, issuedAt: forecast.issuedAt);
}
