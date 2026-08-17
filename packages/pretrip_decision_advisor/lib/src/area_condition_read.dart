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
///     [VisibilityObservation]; absent ⇒ null and the chip says so. As of 0.5.3
///     a NON-FINITE reading (`NaN`, `±Infinity`) counts as absent: it is not a
///     number, so it cannot be a measurement. [VisibilityObservation] is public
///     and unvalidated, so this is the seam that enforces it.
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
  /// there is no measured value, which as of 0.5.3 includes a NON-FINITE
  /// reading: `NaN` and `±Infinity` are not numbers, so they are not
  /// measurements. Up to 0.5.2 such a reading reached `.round()` and threw an
  /// untyped `UnsupportedError` out of [summarizeAreaConditions].
  final int? measuredVisibilityMeters;

  /// The measuring station's published name. Null when there is no measurement —
  /// including when the reading was non-finite, since the three visibility
  /// fields are one composite claim and are withdrawn together.
  final String? visibilityStationName;

  /// Great-circle distance to the measuring station, km. Null when none, and
  /// also when the distance itself was non-finite while the reading was good —
  /// the measurement survives on THIS field, the distance does not. A null here
  /// is never rendered as `0`.
  ///
  /// Know what the chip does with it: [areaConditionChips] does not merely omit
  /// the numeric line, it REPLACES it with
  /// [PretripMessages.areaNoMeasuredVisibility] — "No measured visibility
  /// available for this area." So when only the distance is missing, the driver
  /// is told there is no measurement while [measuredVisibilityMeters] still
  /// holds one and the band still reports it. That over-statement is deliberate
  /// and bounded (the honest alternative needs a new [PretripMessages] member,
  /// which cannot ship inside `^0.5.0`); it is recorded in CHANGELOG 0.5.3
  /// *Honest bounds*. Read this field, not the chip, if you need the truth.
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
/// honestly: when no forecast slot covers the window, `forecastCovered` is false
/// and [AreaConditionRead.areaHazard] THROWS [AreaForecastNotCoveredException]
/// rather than hand back a band nothing was measured for. Guard with
/// [AreaConditionRead.forecastCovered] (as [areaConditionChips] does), or read
/// [AreaConditionRead.areaHazardOrNull] for a `null` instead.
///
/// (Corrected in 0.5.3: up to 0.5.2 this paragraph still said the band "is left
/// non-asserted ([HourHazard.clear])" — describing the pre-0.5.2 placeholder
/// that 0.5.2 had already removed. The code stopped fabricating a clear morning
/// and the doc went on teaching it, which is the defect, not housekeeping: an
/// integrator who reads this and colours a card from `areaHazard` was told the
/// no-forecast case paints green.)
///
/// The hazard band uses the SAME overlap rule + per-slot hazard ladder as the
/// in-window advisor (a slot at hour H covers [H, H+1h)), so the area read and
/// the pre-trip briefing never disagree about what "elevated" means.
///
/// [observed] is a REAL measured visibility (or null). When present it is merged
/// into the slot covering [now] (the measured value is valid for the hour she
/// would be leaving in), exactly as the in-window briefing merges it.
///
/// (Corrected in 0.5.3: a non-finite `meters` or `distanceKm` on [observed] used
/// to reach `.round()` here and throw an untyped `UnsupportedError`, which the
/// `on PretripDataAbsentException` clause 0.5.2 asked you to write did NOT
/// catch. A non-finite reading is now treated as absent — the same equivalence
/// `SnowAwarePretripAdvisor.evidenceGaps` already makes — so the measured-
/// visibility fields are `null` and the chip says so. The hazard band is
/// unchanged: the merge and the ladder both still see whatever you passed.)
///
/// [warningEventVerbatim] is the publisher's official warning text passed
/// through verbatim.
///
/// [warningCheckAvailable] states whether you actually reached the publisher.
/// It DEFAULTS TO FALSE as of 0.5.3, and the default is the point: up to 0.5.2
/// it defaulted to `true`, so the zero-effort call — one that passed neither a
/// warning nor the flag — rendered "No active snow warning or advisory for this
/// area." / 「この地域に発表中の雪の警報・注意報はありません。」 out of a check
/// that had never been performed. That sentence is a claim about COMPLETENESS,
/// and we were making it for free. Silence from a publisher you did not ask is
/// not an all-clear; it is a gap.
///
/// Pass `warningCheckAvailable: true` when — and only when — you reached the
/// publisher and it had nothing in force. That is the one case that earns the
/// negative claim, and it still renders exactly as before.
AreaConditionRead summarizeAreaConditions({
  required WeatherForecast forecast,
  required DateTime now,
  required String areaLabel,
  Duration lookAhead = const Duration(hours: 6),
  String? warningEventVerbatim,
  bool warningCheckAvailable = false,
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

  // 0.5.3 — a field that states a MEASURED NUMBER may only be built from a
  // finite one. This is the SAME rule the in-window advisor applies in
  // `SnowAwarePretripAdvisor._describe`, applied at the sibling seam it was not
  // applied to. `VisibilityObservation` is public, exported and unvalidated
  // (`double meters` / `double distanceKm`), and the source adapters build it
  // from network JSON — `_readNum` in `pretrip_source_jma` is `double.tryParse`,
  // which returns `Infinity` for the string `"Infinity"` and for an overflowing
  // literal such as `"1e400"`. A non-finite field reached `.round()` here and
  // threw an untyped `UnsupportedError: Infinity or NaN toInt` out of a pure,
  // offline function — and NOT one of this package's typed absence stops, so the
  // `on PretripDataAbsentException` clause 0.5.2 asked integrators to write did
  // not catch it.
  //
  // Non-finite is treated exactly as ABSENT — the same equivalence
  // `SnowAwarePretripAdvisor.evidenceGaps` already makes (`vis == null ||
  // !vis.isFinite` is one condition, not two). Absence here has one and only one
  // spelling, already published and already documented on these three fields:
  // `null`, and the chip says so. No new member, no new type, no new vocabulary.
  //
  // These three fields are ONE composite claim — "visibility M, measured at
  // station S, D km away" — so a non-finite `meters` withdraws all three, which
  // is what their own field docs already require ("Null when there is no
  // measurement" / "Null when none"). A non-finite `distanceKm` withdraws only
  // the distance: the measurement itself is still a real number and positive
  // evidence fires on partial knowledge.
  //
  // The hazard BAND is untouched. `mergeObservedVisibility` still carries
  // `observed.meters` into the departure slot and `hazardOf` still judges it;
  // this is the chip's arithmetic, not the ladder's judgement. Nothing here can
  // delete a band the ladder produced.
  final double? metersRaw = observed?.meters;
  final bool haveMeasurement = metersRaw != null && metersRaw.isFinite;
  final double? distanceRaw = observed?.distanceKm;

  return AreaConditionRead(
    areaHazard: areaHazard,
    forecastCovered: forecastCovered,
    officialWarningVerbatim: warningEventVerbatim,
    warningCheckAvailable: warningCheckAvailable,
    // Real-sensor-or-nothing: only ever from the passed observation, and only
    // ever from a finite reading.
    measuredVisibilityMeters: haveMeasurement ? metersRaw.round() : null,
    visibilityStationName: haveMeasurement ? observed!.stationName : null,
    visibilityDistanceKm:
        haveMeasurement && distanceRaw != null && distanceRaw.isFinite
        ? distanceRaw.round()
        : null,
    areaLabel: areaLabel,
  );
}

HourHazard _worse(HourHazard a, HourHazard b) => a.index >= b.index ? a : b;

/// The declarative area chips, in fixed order:
///   1. the official-warning line — the publisher's verbatim warning if one is
///      in hand (whatever the check's completeness); else "check unavailable"
///      if the check was not complete; else "none in force", which only an
///      asserted-complete check earns,
///   2. the forecast hazard band (or "forecast not covered"),
///   3. the nearest MEASURED visibility (or "none") — a composite of two
///      numbers, so it renders only when BOTH are in hand. A missing distance is
///      never filled with `0`.
///
/// Pure — no clock, no network. Every line is about the weather at a PLACE.
List<String> areaConditionChips(AreaConditionRead r, PretripMessages m) {
  final chips = <String>[];

  // 1. Official warning.
  //
  // ORDER IS LOAD-BEARING (0.5.3). A warning IN HAND renders FIRST, whatever
  // the check's completeness — a hazard seen is a hazard real, even on partial
  // data. Only the NEGATIVE claim ("none in force") requires the check to have
  // been complete, because a negative conclusion requires whole knowledge.
  // That asymmetry is `condition_aggregator`'s AdvisoryLookup doctrine
  // ("Positive evidence fires on partial knowledge. Negative conclusions
  // require whole knowledge.") applied at this seam.
  //
  // Up to 0.5.2 the `!warningCheckAvailable` branch came FIRST and
  // short-circuited the verbatim render: a caller who fetched a real 大雪警報
  // from one publisher while a second publisher failed — and who therefore
  // honestly reported the check as incomplete — had that heavy-snow warning
  // REPLACED by "check unavailable". The one branch that had a hazard to show
  // was unreachable whenever the caller admitted a gap. Honesty about the gap
  // cost her the warning.
  if (r.officialWarningVerbatim != null) {
    chips.add(m.areaOfficialWarning(r.officialWarningVerbatim!));
  } else if (!r.warningCheckAvailable) {
    chips.add(m.areaWarningCheckUnavailable());
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
  //
  // 0.5.3 — this chip is a COMPOSITE claim built from two numbers ("~M m … ~D km
  // away"), so it renders only when it holds both. Up to 0.5.2 a null distance
  // was filled by `?? 0`, which put the reading at the NEAREST POSSIBLE station —
  // absence arriving as a maximally-confident value, in the one clause a driver
  // reads to judge how much the reading is about HER. A missing number is not a
  // zero. Where a number is absent the chip degrades to the branch that needs no
  // number, exactly as `SnowAwarePretripAdvisor._describe` degrades to its
  // no-number fallback. (Reachable from `summarizeAreaConditions` only for a
  // non-finite `distanceKm`; reachable for any directly-constructed
  // `AreaConditionRead`, which is why the guard lives here and not only there.)
  final meters = r.measuredVisibilityMeters;
  final km = r.visibilityDistanceKm;
  final station = r.visibilityStationName;
  chips.add(
    (meters != null && km != null && station != null)
        ? m.areaMeasuredVisibility(meters, station, km)
        : m.areaNoMeasuredVisibility(),
  );

  return chips;
}
