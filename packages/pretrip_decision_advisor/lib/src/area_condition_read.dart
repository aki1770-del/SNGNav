/// Destination-AREA condition read — "what conditions will SHE face in her
/// mother's area if she drives there", so the driver (a daughter who drives to
/// care for family) decides whether and when to make the trip.
///
/// This is a PUBLIC-WEATHER-AT-A-PLACE read. It watches NO person. Its subject
/// is the weather at a PLACE — never an arrival, a presence, a person, or a
/// road. It is the companion to the offline daylight clock: a lightweight,
/// declarative section, not a second full briefing card.
///
/// BINDING BOUNDARIES (each is the point of the feature, not decoration):
///   * No person framing anywhere — the subject is the weather at a PLACE; the
///     area label is a place passthrough, never derived from a person signal.
///   * Honest claim ceiling — output is "conditions / official advisory for the
///     AREA" only. NEVER a road-passability, per-road, or route-segment claim.
///   * Real-sensor-or-nothing — a measured visibility is set ONLY from a real
///     [VisibilityObservation]; absent ⇒ null and the chip says so.
///   * Offline-deterministic — [summarizeAreaConditions] takes no clock and no
///     network; live reads degrade to null (the section is omitted upstream),
///     never to a fabricated value.
///
/// Pure Dart: no Flutter, no network, no dependency on `condition_aggregator`.
/// The publisher's official-warning text is passed in verbatim as a String and
/// a bool; this file never reaches a network for it.
library;

import 'pretrip_absence.dart';
import 'pretrip_messages.dart';
import 'snow_aware_pretrip_advisor.dart';
import 'visibility_observation.dart';
import 'weather_forecast.dart';

/// An immutable, declarative read of the conditions in a destination AREA over
/// a look-ahead window. Every field is about the place or the weather there —
/// there is deliberately NO suggestion, strength, recommendation, or verdict
/// field: the read informs the driver's own decision, it does not make it.
class AreaConditionRead {
  const AreaConditionRead({
    required HourHazard areaHazard,
    required this.forecastCovered,
    required this.officialWarningVerbatim,
    required this.warningCheckAvailable,
    required this.measuredVisibilityMeters,
    required this.visibilityStationName,
    required this.visibilityDistanceKm,
    required this.areaLabel,
  }) : _areaHazard = areaHazard;

  final HourHazard _areaHazard;

  /// Peak forecast hazard over the look-ahead window.
  ///
  /// Throws [AreaForecastNotCoveredException] when [forecastCovered] is false:
  /// no forecast slot covered the window, so no band was computed. Before 0.5.2
  /// this returned [HourHazard.clear] as a "non-asserted placeholder" — which a
  /// caller colouring a card from the band could not see, so a place nothing was
  /// known about rendered green. It is not clear there; it is unknown there, and
  /// [HourHazard] has no member for that.
  ///
  /// Guard with [forecastCovered] (as [areaConditionChips] always has), or read
  /// [areaHazardOrNull], added in 0.5.2.
  HourHazard get areaHazard {
    if (!forecastCovered) {
      throw AreaForecastNotCoveredException(areaLabel: areaLabel);
    }
    return _areaHazard;
  }

  /// [areaHazard], but `null` instead of throwing when the forecast does not
  /// cover the window. A `null` here means "we do not know", never "clear".
  HourHazard? areaHazardOrNull() => forecastCovered ? _areaHazard : null;

  /// False ⇒ the forecast does not cover the window; the band is NOT asserted.
  final bool forecastCovered;

  /// The publisher's official warning text, verbatim (e.g. 大雪警報). Null when
  /// there is no active warning, or when it is unknown.
  final String? officialWarningVerbatim;

  /// False ⇒ the official-warning check failed; an honest gap is shown rather
  /// than an implied "no warning".
  final bool warningCheckAvailable;

  /// Nearest measured visibility in metres — from a REAL sensor only. Null when
  /// there is no measured value.
  final int? measuredVisibilityMeters;

  /// The measuring station's published name. Null when there is no measurement.
  final String? visibilityStationName;

  /// Great-circle distance to the measuring station, km. Null when none.
  final int? visibilityDistanceKm;

  /// A PLACE label (e.g. a prefecture or town name) — NEVER a person.
  final String areaLabel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AreaConditionRead &&
        other._areaHazard == _areaHazard &&
        other.forecastCovered == forecastCovered &&
        other.officialWarningVerbatim == officialWarningVerbatim &&
        other.warningCheckAvailable == warningCheckAvailable &&
        other.measuredVisibilityMeters == measuredVisibilityMeters &&
        other.visibilityStationName == visibilityStationName &&
        other.visibilityDistanceKm == visibilityDistanceKm &&
        other.areaLabel == areaLabel;
  }

  @override
  int get hashCode => Object.hash(
        _areaHazard,
        forecastCovered,
        officialWarningVerbatim,
        warningCheckAvailable,
        measuredVisibilityMeters,
        visibilityStationName,
        visibilityDistanceKm,
        areaLabel,
      );
}

/// Summarises the conditions in a destination AREA over [lookAhead] starting at
/// [now]. PURE: no clock read, no network — every input is handed in. Degrades
/// honestly: when no forecast slot covers the window, [AreaConditionRead.areaHazard]
/// is left non-asserted ([HourHazard.clear]) and `forecastCovered` is false.
///
/// The hazard band uses the SAME overlap rule + per-slot hazard ladder as the
/// in-window advisor (a slot at hour H covers [H, H+1h)), so the area read and
/// the pre-trip briefing never disagree about what "elevated" means.
///
/// [observed] is a REAL measured visibility (or null). When present it is merged
/// into the slot covering [now] (the measured value is valid for the hour she
/// would be leaving in), exactly as the in-window briefing merges it.
///
/// [warningEventVerbatim] is the publisher's official warning text passed
/// through verbatim; [warningCheckAvailable] is false when that check failed.
AreaConditionRead summarizeAreaConditions({
  required WeatherForecast forecast,
  required DateTime now,
  required String areaLabel,
  Duration lookAhead = const Duration(hours: 6),
  String? warningEventVerbatim,
  bool warningCheckAvailable = true,
  VisibilityObservation? observed,
  SnowAwarePretripAdvisor advisor = const SnowAwarePretripAdvisor(),
}) {
  // A real sensor reading is valid for the hour she would be leaving in; merge
  // it into the slot covering [now] only (never projected into later hours).
  final effective = observed != null
      ? mergeObservedVisibility(forecast, observed, now)
      : forecast;

  // Slots overlapping [now, now + lookAhead) — the SAME rule the advisor uses
  // (a slot at hour H covers [H, H + 1h)).
  final end = now.add(lookAhead);
  final slots = [
    for (final s in effective.hourly)
      if (s.hour.isBefore(end) &&
          s.hour.add(const Duration(hours: 1)).isAfter(now))
        s,
  ];

  final bool forecastCovered = slots.isNotEmpty;
  final HourHazard areaHazard = forecastCovered
      ? slots.map(advisor.hazardOf).reduce(_worse)
      // Non-asserted placeholder: the chip layer shows "not covered", not a band.
      : HourHazard.clear;

  return AreaConditionRead(
    areaHazard: areaHazard,
    forecastCovered: forecastCovered,
    officialWarningVerbatim: warningEventVerbatim,
    warningCheckAvailable: warningCheckAvailable,
    // Real-sensor-or-nothing: only ever from the passed observation.
    measuredVisibilityMeters: observed?.meters.round(),
    visibilityStationName: observed?.stationName,
    visibilityDistanceKm: observed?.distanceKm.round(),
    areaLabel: areaLabel,
  );
}

HourHazard _worse(HourHazard a, HourHazard b) => a.index >= b.index ? a : b;

/// The declarative area chips, in fixed order:
///   1. the official-warning line (verbatim, or "none", or "check unavailable"),
///   2. the forecast hazard band (or "forecast not covered"),
///   3. the nearest MEASURED visibility (or "none").
///
/// Pure — no clock, no network. Every line is about the weather at a PLACE.
List<String> areaConditionChips(AreaConditionRead r, PretripMessages m) {
  final chips = <String>[];

  // 1. Official warning.
  if (!r.warningCheckAvailable) {
    chips.add(m.areaWarningCheckUnavailable());
  } else if (r.officialWarningVerbatim != null) {
    chips.add(m.areaOfficialWarning(r.officialWarningVerbatim!));
  } else {
    chips.add(m.areaNoOfficialWarning());
  }

  // 2. Forecast hazard band (or honest "not covered").
  chips.add(r.forecastCovered
      ? m.areaHazardChip(r.areaHazard)
      : m.areaForecastNotCovered());

  // 3. Measured visibility (real sensor or honest "none").
  chips.add(r.measuredVisibilityMeters != null
      ? m.areaMeasuredVisibility(
          r.measuredVisibilityMeters!,
          r.visibilityStationName ?? '',
          r.visibilityDistanceKm ?? 0,
        )
      : m.areaNoMeasuredVisibility());

  return chips;
}
