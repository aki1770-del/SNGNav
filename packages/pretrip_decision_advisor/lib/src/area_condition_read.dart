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
    required this.areaHazard,
    required this.forecastCovered,
    required this.officialWarningVerbatim,
    required this.warningCheckAvailable,
    required this.measuredVisibilityMeters,
    required this.visibilityStationName,
    required this.visibilityDistanceKm,
    required this.areaLabel,
  });

  /// Peak forecast hazard over the look-ahead window.
  ///
  /// [HourHazard.unknown] when [forecastCovered] is false — the forecast did
  /// not cover the window, so no band is asserted. Up to 0.5.1 this was
  /// [HourHazard.clear], which read as good news about hours nobody forecast.
  final HourHazard areaHazard;

  /// [areaHazard], but `null` instead of [HourHazard.unknown] when the forecast
  /// does not cover the window. A `null` here means "we do not know", never
  /// "clear".
  ///
  /// Restored in 0.6.1: it was public in 0.5.2–0.5.3 and removed in 0.6.0. The
  /// `unknown` member 0.6.0 introduced is the better default for this field and
  /// stays; this is for callers who would rather branch on null.
  HourHazard? areaHazardOrNull() => forecastCovered ? areaHazard : null;

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
        other.areaHazard == areaHazard &&
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
    areaHazard,
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
      // NOT HourHazard.clear. The forecast did not cover the window; nothing is
      // claimed. The chip layer shows "not covered", never a band — and now the
      // VALUE itself says so too, so a consumer reading `areaHazard` without
      // checking `forecastCovered` can no longer print "clear".
      : HourHazard.unknown;

  // A NON-FINITE reading (`NaN`, `±Infinity`) counts as ABSENT: it is not a
  // number, so it cannot be a measurement. `VisibilityObservation` is public
  // and unvalidated, so this is the seam that enforces it. Up to 0.6.0 such a
  // reading reached `.round()` and threw an untyped `UnsupportedError:
  // Infinity or NaN toInt` out of `summarizeAreaConditions` — untyped, so the
  // `on PretripDataAbsentException` clause integrators were asked to write did
  // not catch it. Reachable from publisher JSON: `double.tryParse('1e400')`
  // is `Infinity`.
  //
  // Non-finite is treated exactly as absent — the same equivalence
  // `SnowAwarePretripAdvisor.evidenceGaps` makes. These three fields are ONE
  // composite claim ("visibility M, measured at station S, D km away"), so a
  // non-finite `meters` withdraws all three, which is what their own field
  // docs already require. The hazard BAND is untouched: this is the chip's
  // arithmetic, not the ladder's judgement.
  final double? metersRaw = observed?.meters;
  final bool haveMeasurement = metersRaw != null && metersRaw.isFinite;
  final double? distanceRaw = observed?.distanceKm;

  return AreaConditionRead(
    areaHazard: areaHazard,
    forecastCovered: forecastCovered,
    officialWarningVerbatim: warningEventVerbatim,
    warningCheckAvailable: warningCheckAvailable,
    // Real-sensor-or-nothing: only ever from the passed observation.
    measuredVisibilityMeters: haveMeasurement ? metersRaw.round() : null,
    visibilityStationName: haveMeasurement ? observed!.stationName : null,
    // A null distance is never rendered as `0`, and survives only ever from a
    // finite reading.
    visibilityDistanceKm:
        haveMeasurement && distanceRaw != null && distanceRaw.isFinite
        ? distanceRaw.round()
        : null,
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
  chips.add(
    r.forecastCovered
        ? m.areaHazardChip(r.areaHazard)
        : m.areaForecastNotCovered(),
  );

  // 3. Measured visibility (real sensor or honest "none").
  chips.add(
    r.measuredVisibilityMeters != null
        ? m.areaMeasuredVisibility(
            r.measuredVisibilityMeters!,
            // Nullable through: an unknown station distance is NOT 0 km ("taken
            // at your location"), and an unnamed station is NOT ''.
            r.visibilityStationName,
            r.visibilityDistanceKm,
          )
        : m.areaNoMeasuredVisibility(),
  );

  return chips;
}
