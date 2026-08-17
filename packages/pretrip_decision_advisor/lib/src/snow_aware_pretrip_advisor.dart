/// Concrete pre-trip departure-timing advisor — the reference implementation
/// of the `pretrip_decision_advisor` contract.
///
/// The pre-trip departure-timing decision is often the most consequential
/// safety surface — not the in-trip moment. Substrate that fires advisory only
/// at the moment of detected hazard misses the upstream surface where the most
/// weight belongs. This advisor is that upstream surface: it answers "should I
/// leave now or wait?" BEFORE the driver is in the hazard.
///
/// PURE AND DETERMINISTIC — no LLM, no network, no clock. Everything is
/// computed from the typed inputs the caller hands in, so the same inputs
/// always produce the same recommendation and the worst-case path stays
/// offline. Null forecast fields contribute nothing to hazard scores: the
/// advisor never fabricates a hazard it has no data for, and it returns
/// `null` (driver's own judgment) when the forecast does not cover the
/// departure window at all.
///
/// Honesty rule (binding, from the contract): when the commute is
/// `required` — or its flexibility is `unknown` — the advisor never urges a
/// delay. It returns `honestyMode`, names what it sees, and defers to the
/// driver. A school run or work shift is not ours to cancel.
library;

import 'package:navigation_safety_calibration/navigation_safety_calibration.dart'
    show isRadiativeFrostBlackIce;

import 'commute_shape.dart';
import 'daylight.dart';
import 'driver_profile_spec.dart';
import 'pretrip_absence.dart';
import 'pretrip_advisor.dart';
import 'pretrip_messages.dart';
import 'pretrip_recommendation.dart';
import 'weather_forecast.dart';

/// Per-hour winter-hazard severity derived from one forecast slot.
///
/// Thresholds match the in-trip Snow Scene bands so pre-trip and in-trip
/// never disagree about what "whiteout" means: < 100 m is whiteout class
/// (the turn-back trigger in-trip), 100–200 m is the near-whiteout advisory
/// band, and near-freezing precipitation is the icing surface the JAF
/// frozen-rut voice warns defeats ABS/ESC.
enum HourHazard {
  /// No winter hazard signal in this slot.
  clear,

  /// Slush, light reduced visibility, cold rain, subzero air temperature,
  /// or the above-zero radiative-frost (black-ice) window
  /// (frost / black-ice risk) — drive with care.
  caution,

  /// Packed snow, near-whiteout visibility (< 200 m), or icing conditions
  /// (precipitation at near-freezing temperature).
  elevated,

  /// Whiteout-class visibility (< 100 m) or forecast ice.
  severe,
}

/// A hazard family the ladder could NOT decide for a forecast slot, because
/// the field it reads was absent (`null`) or unusable (non-finite).
///
/// Added in 0.5.3. This enum is deliberately NOT a member of [HourHazard]:
/// [HourHazard] is the MEASUREMENT scale, and "we could not look" does not
/// belong anywhere on a measurement scale — placed at the benign end it
/// invents safety, placed at the adverse end it invents danger. Both are
/// fabrications. Absence is reported here, beside the ladder, never on it.
///
/// Each member answers one mechanical question about
/// [SnowAwarePretripAdvisor.hazardOf]: *could some value of this absent field
/// have produced a hazard at this slot's temperature?* If yes, the family is
/// undecided and the affirmative all-clear has not been earned. If no, the
/// absence is harmless and no gap is reported — an absent precipitation figure
/// on a +8 °C afternoon cannot change any verdict, so it is not a gap.
enum HazardEvidenceGap {
  /// [HourlyForecast.visibilityMeters] absent or non-finite. Any value below
  /// 500 m produces at least caution and below 100 m produces severe, at ANY
  /// temperature — so absent visibility is always undecided.
  visibility,

  /// [HourlyForecast.precipitationMmPerHour] absent or non-finite while the
  /// temperature is at or below [SnowAwarePretripAdvisor.coldRainTempCelsius].
  /// Above that band no precipitation figure can produce a hazard, so its
  /// absence is not a gap.
  precipitation,

  /// [HourlyForecast.estimatedRoadCondition] absent, or explicitly
  /// [RoadConditionEstimate.unknown] — the caller telling us, honestly, that
  /// it could not look. Ice, packed snow and slush each produce a hazard at
  /// ANY temperature, so an unknown road surface is always undecided.
  ///
  /// The explicit-`unknown` case is the one that matters most: up to 0.5.2 a
  /// caller who honestly declared the road unknown got the SAME answer as one
  /// who reported a dry road.
  roadSurface,

  /// [HourlyForecast.humidityRH] absent or non-finite while the temperature is
  /// at or below [SnowAwarePretripAdvisor.radiativeFrostAmbientCeilingCelsius]
  /// — the band where clear-sky radiative cooling can take the road surface
  /// below freezing while the air reads above it. Above that ceiling the
  /// calibration cannot fire, so absent humidity is not a gap.
  radiativeFrostHumidity,

  /// [HourlyForecast.tempCelsius] is non-finite (NaN or infinite). It is a
  /// required, non-nullable field, so it can never be absent — but a NaN makes
  /// every `<=` comparison in the ladder false, and the calibration rejects it
  /// too, so the slot slides silently to [HourHazard.clear] with nothing
  /// having been decided at all.
  temperature,
}

/// One verdict shape the app UI renders directly. The contract's
/// [PretripRecommendation] is derived from this and carries the same
/// rationale; the briefing keeps the richer typed verdict so the card does
/// not have to re-parse prose.
enum PretripVerdict {
  /// Forecast does not cover the departure window — no recommendation.
  ///
  /// As of 0.5.2 [SnowAwarePretripAdvisor.brief] no longer PRODUCES this
  /// verdict: it throws [PretripForecastCoverageException] instead, because
  /// the briefing it would have had to build carries a non-nullable
  /// [PretripBriefing.peakHazard] and [HourHazard] has no "unknown" member —
  /// so the only briefing it could return was one that reported a morning with
  /// no forecast as [HourHazard.clear]. The member is kept (removing it would
  /// break your build) and remains available to other [PretripAdvisor]
  /// implementations and to your own verdict handling.
  noData,

  /// No winter hazard signals across the trip window.
  clear,

  /// Caution-class signals only; no delay suggested.
  caution,

  /// Hazard in the window and a materially better later window exists.
  waitAdvised,

  /// Hazard in the window and nothing materially better within the search
  /// horizon — the honest message is "decide with care", not a fake delay.
  hazardPersists,

  /// The trip is required (or flexibility unknown): hazard is named, no
  /// delay is urged, the driver decides.
  requiredTripHazard,
}

/// The full pre-trip briefing the app surface renders.
class PretripBriefing {
  const PretripBriefing({
    required this.verdict,
    required this.chips,
    required this.recommendation,
    required this.peakHazard,
  });

  final PretripVerdict verdict;

  /// Plain-language reason chips (also carried on the recommendation).
  final List<String> chips;

  /// The contract-shaped recommendation. Nullable by contract; every briefing
  /// [SnowAwarePretripAdvisor] now returns carries a non-null one (the one case
  /// that carried `null` — no forecast coverage — is a
  /// [PretripForecastCoverageException] as of 0.5.2, not a briefing).
  final PretripRecommendation? recommendation;

  /// Worst per-hour hazard inside the trip window.
  ///
  /// This value is ALWAYS derived from at least one real forecast slot. It is
  /// safe to colour a card from it. (Before 0.5.2 it was [HourHazard.clear] on
  /// a briefing built from no forecast at all.)
  final HourHazard peakHazard;
}

/// Deterministic snow-aware implementation of [PretripAdvisor].
class SnowAwarePretripAdvisor implements PretripAdvisor {
  const SnowAwarePretripAdvisor({
    this.searchHorizon = const Duration(hours: 6),
    this.messages = PretripMessages.en,
  });

  /// How far past the planned departure a better window is searched for.
  final Duration searchHorizon;

  /// The locale table the reason chips are written in. Defaults to English so
  /// every existing caller is unchanged; pass [PretripMessages.ja] (or
  /// [PretripMessages.forLanguage]) to reach a driver in her own language.
  final PretripMessages messages;

  /// Visibility below this is whiteout class — same band as the in-trip
  /// turn-back trigger.
  static const double whiteoutVisibilityMeters = 100;

  /// Visibility below this is the near-whiteout advisory band.
  static const double nearWhiteoutVisibilityMeters = 200;

  /// At or below this air temperature, precipitation is treated as an icing
  /// surface (freezing rain / refreeze band).
  static const double icingTempCelsius = 0.5;

  /// At or below this air temperature, precipitation is cold-rain class — the
  /// lowest temperature band in which a precipitation figure can produce any
  /// hazard at all.
  ///
  /// Added in 0.5.3 to name the literal the ladder already used, so
  /// [evidenceGaps] can ask "could an absent precipitation figure have
  /// mattered here?" without guessing. `hazardOf` is UNCHANGED in 0.5.3 and
  /// still carries the literal; `coldRainTempCelsius` is proven equal to it by
  /// a driven sweep in `unmeasured_all_clear_test.dart`, so the two cannot
  /// drift apart silently.
  static const double coldRainTempCelsius = 2.0;

  /// At or below this air temperature, even a dry forecast is caution class
  /// (frost / black-ice risk). Matches the in-trip MET Norway adapter's
  /// "Subzero forecast" moderate-advisory threshold so pre-trip and in-trip
  /// never disagree about what subzero means. Quantified motivation
  /// (2026-06-12, 620 real winter forecast slots): 70 dry-subzero slots down
  /// to −11.7 °C rendered "No winter hazard signals" under the old rule —
  /// temperature is REAL data here, not a null field, so flagging it is not
  /// fabrication.
  static const double frostTempCelsius = 0.0;

  /// A forecast older than this at the planned departure gets a staleness
  /// chip — conditions may have changed since it was issued.
  static const Duration staleAfter = Duration(hours: 6);

  /// Reaction-time calibration only (never strength, per the contract): a
  /// slower-reacting driver gets an extra margin added to a suggested delay
  /// so she is not sent into the trailing edge of a clearing hazard.
  static const double slowReactionSeconds = 2.5;
  static const Duration slowReactionMargin = Duration(minutes: 30);

  @override
  PretripRecommendation? advise({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) => briefOrNull(
    forecast: forecast,
    commute: commute,
    profile: profile,
  )?.recommendation;

  /// The richer briefing the app UI consumes; [advise] derives from it.
  ///
  /// Throws a [PretripDataAbsentException] in the two cases where no honest
  /// briefing exists — catch that base type to handle both:
  ///
  ///  * [PretripForecastCoverageException] when NO forecast slot covers the
  ///    planned trip window. Before 0.5.2 this returned a briefing whose
  ///    `peakHazard` was [HourHazard.clear] — a morning nobody forecast, handed
  ///    to the driver as a clear morning.
  ///  * [PretripAssessmentIncompleteException] (new in 0.5.3) when a forecast
  ///    DOES cover the window but the fields deciding the ladder were never
  ///    measured, so the affirmative all-clear was not earned. Up to 0.5.2 a
  ///    slot carrying a temperature and nothing else reported
  ///    "No winter hazard signals in your trip window".
  ///
  /// [HourHazard] has no `unknown` member and [PretripBriefing.peakHazard] is
  /// non-nullable, so there is no honest briefing to build in either case; the
  /// advisor stops and says why rather than paint green over a data blackout.
  /// A MEASURED hazard is never withheld — it reports from partial data as it
  /// always has.
  ///
  /// If you would rather branch than catch, [briefOrNull] returns `null` in
  /// exactly these cases, and [allClearEarned] answers the question before you
  /// call. [advise] is unchanged and still returns `null`.
  PretripBriefing brief({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) {
    final briefing = briefOrNull(
      forecast: forecast,
      commute: commute,
      profile: profile,
    );
    if (briefing != null) return briefing;

    // Two different absences reach here, and they are not the same stop.
    final window = _slotsCovering(
      forecast.hourly,
      commute.plannedDeparture,
      commute.plannedDuration,
    );
    if (window.isEmpty) {
      throw PretripForecastCoverageException(
        plannedDeparture: commute.plannedDeparture,
        plannedDuration: commute.plannedDuration,
        forecastSlotCount: forecast.hourly.length,
      );
    }
    throw _unearnedReason(window, commute)!;
  }

  /// [brief], but returns `null` instead of throwing wherever [brief] would
  /// stop. Added in 0.5.2 as the branch-don't-catch way forward; a `null` here
  /// means "we do not know", never "clear".
  ///
  /// As of 0.5.3 that covers one more way of not knowing: a window the
  /// forecast reaches but did not measure (see
  /// [PretripAssessmentIncompleteException]). The published contract of this
  /// method is unchanged — `null` still means exactly "we do not know" — but
  /// it now returns `null` in a case that previously returned a briefing
  /// saying "No winter hazard signals in your trip window". Use
  /// [allClearEarned] to distinguish the cases without catching, or
  /// [evidenceGaps] to see which fields were missing.
  PretripBriefing? briefOrNull({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) {
    final window = _slotsCovering(
      forecast.hourly,
      commute.plannedDeparture,
      commute.plannedDuration,
    );
    if (window.isEmpty) return null;

    final peak = window.map(hazardOf).reduce(_worse);

    // 0.5.3 — the affirmative all-clear must be EARNED. A `clear` peak means
    // "nothing fired", which is not the same as "nothing is there": every
    // hazard test in `hazardOf` is guarded `field != null && ...`, so a slot
    // carrying a temperature and nothing else lands here having decided
    // nothing. Reporting that as "No winter hazard signals in your trip
    // window" is the per-slot twin of the no-forecast fabrication 0.5.2 fixed.
    //
    // ONLY the affirmative is gated. A measured hazard still reports from
    // partial data, exactly as before — positive evidence fires on partial
    // knowledge, negative conclusions require whole knowledge.
    if (peak == HourHazard.clear && _unearnedReason(window, commute) != null) {
      return null;
    }
    final worstSlot = window.firstWhere(
      (s) => hazardOf(s) == peak,
      orElse: () => window.first,
    );
    final chips = <String>[];

    final staleness = commute.plannedDeparture.difference(forecast.issuedAt);
    void addStalenessChip() {
      if (staleness > staleAfter) {
        chips.add(messages.stalenessChip(staleness.inHours));
      }
    }

    // Offline daylight clock: a light/time note when the trip falls in
    // low-light hours. Stays silent unless the commute carries a [TripGeo], and
    // never asserts a road hazard from the time of day alone.
    void addDaylightChip() {
      final daylight = _selectDaylight(commute);
      if (daylight != null) {
        chips.add(messages.daylightChip(daylight));
      }
    }

    // Calibration-only margin (never strength).
    final margin = profile.reactionTimeSeconds >= slowReactionSeconds
        ? slowReactionMargin
        : Duration.zero;

    final delayUrgeable =
        commute.flexibility == CommuteFlexibility.discretionary;

    switch (peak) {
      case HourHazard.clear:
        chips.add(messages.noWinterHazard());
        addStalenessChip();
        addDaylightChip();
        return PretripBriefing(
          verdict: PretripVerdict.clear,
          chips: List.unmodifiable(chips),
          recommendation: PretripRecommendation(
            suggestedDelay: Duration.zero,
            confidenceWindow: const Duration(hours: 1),
            strength: RecommendationStrength.advisoryWeak,
            rationale: List.unmodifiable(chips),
          ),
          peakHazard: peak,
        );

      case HourHazard.caution:
        chips.add(_describe(worstSlot));
        chips.add(messages.allowExtraTime());
        addStalenessChip();
        addDaylightChip();
        return PretripBriefing(
          verdict: PretripVerdict.caution,
          chips: List.unmodifiable(chips),
          recommendation: PretripRecommendation(
            suggestedDelay: Duration.zero,
            confidenceWindow: const Duration(hours: 1),
            strength: RecommendationStrength.advisoryWeak,
            rationale: List.unmodifiable(chips),
          ),
          peakHazard: peak,
        );

      case HourHazard.elevated:
      case HourHazard.severe:
        chips.add(_describe(worstSlot));
        final betterDelay = _findBetterWindow(forecast.hourly, commute);

        if (!delayUrgeable) {
          // Honesty rule: required (or unknown) commute — never urge a delay.
          if (betterDelay != null) {
            chips.add(
              messages.conditionsLookBetterIfAllows(
                _hhmm(commute.plannedDeparture.add(betterDelay)),
              ),
            );
          }
          chips.add(messages.requiredNoDelayUrged());
          addStalenessChip();
          addDaylightChip();
          return PretripBriefing(
            verdict: PretripVerdict.requiredTripHazard,
            chips: List.unmodifiable(chips),
            recommendation: PretripRecommendation(
              suggestedDelay: Duration.zero,
              confidenceWindow: const Duration(hours: 1),
              strength: RecommendationStrength.honestyMode,
              rationale: List.unmodifiable(chips),
            ),
            peakHazard: peak,
          );
        }

        if (betterDelay != null) {
          final delay = betterDelay + margin;
          chips.add(
            messages.conditionsImproveBy(
              _hhmm(commute.plannedDeparture.add(betterDelay)),
            ),
          );
          if (margin > Duration.zero) {
            chips.add(messages.reactionMargin(margin.inMinutes));
          }
          addStalenessChip();
          addDaylightChip();
          return PretripBriefing(
            verdict: PretripVerdict.waitAdvised,
            chips: List.unmodifiable(chips),
            recommendation: PretripRecommendation(
              suggestedDelay: delay,
              confidenceWindow: const Duration(hours: 1),
              strength: peak == HourHazard.severe
                  ? RecommendationStrength.advisoryStrong
                  : RecommendationStrength.advisoryWeak,
              rationale: List.unmodifiable(chips),
            ),
            peakHazard: peak,
          );
        }

        chips.add(messages.noBetterWindow(searchHorizon.inHours));
        addStalenessChip();
        addDaylightChip();
        return PretripBriefing(
          verdict: PretripVerdict.hazardPersists,
          chips: List.unmodifiable(chips),
          recommendation: PretripRecommendation(
            // Duration.zero here means "no delay target to suggest", and the
            // chips carry the honest message; the advisor does not invent a
            // wait it has no forecast basis for.
            suggestedDelay: Duration.zero,
            confidenceWindow: const Duration(hours: 1),
            strength: RecommendationStrength.advisoryWeak,
            rationale: List.unmodifiable(chips),
          ),
          peakHazard: peak,
        );
    }
  }

  /// Hazard severity of a single forecast slot. Null fields contribute
  /// nothing — absence of data is never treated as presence of hazard.
  HourHazard hazardOf(HourlyForecast slot) {
    final vis = slot.visibilityMeters;
    final precip = slot.precipitationMmPerHour;
    final road = slot.estimatedRoadCondition;

    if (road == RoadConditionEstimate.ice ||
        (vis != null && vis < whiteoutVisibilityMeters)) {
      return HourHazard.severe;
    }
    final icing =
        precip != null && precip > 0 && slot.tempCelsius <= icingTempCelsius;
    if (road == RoadConditionEstimate.packedSnow ||
        icing ||
        (vis != null && vis < nearWhiteoutVisibilityMeters)) {
      return HourHazard.elevated;
    }
    final coldRain = precip != null && precip > 0 && slot.tempCelsius <= 2.0;
    if (road == RoadConditionEstimate.slush ||
        coldRain ||
        (vis != null && vis < 500) ||
        slot.tempCelsius <= frostTempCelsius ||
        radiativeFrostRisk(slot)) {
      return HourHazard.caution;
    }
    return HourHazard.clear;
  }

  /// The hazard families [hazardOf] could not decide for [slot], because the
  /// field each one reads was absent or non-finite. Empty means every family
  /// that could still have fired at this slot's temperature was measured — and
  /// only then is the affirmative "no winter hazard" claim earned.
  ///
  /// Added in 0.5.3. This is deliberately public and deliberately per-slot:
  /// the advisor stops asserting what it did not measure, but it does not
  /// decide FOR you what an acceptable gap is. A caller who knows its own
  /// region — one whose roads are salted and monitored, or who has a road
  /// model of its own — can read the gaps and apply its own policy. What the
  /// advisor will not do is print "No winter hazard signals in your trip
  /// window" over them.
  ///
  /// Absence is never a hazard: a gap NEVER raises the hazard band. It only
  /// withholds the affirmative all-clear. [hazardOf] is unchanged.
  Set<HazardEvidenceGap> evidenceGaps(HourlyForecast slot) {
    final gaps = <HazardEvidenceGap>{};
    final t = slot.tempCelsius;

    // A non-finite temperature decides nothing: every `<=` below is false and
    // the radiative-frost calibration rejects it outright.
    if (!t.isFinite) gaps.add(HazardEvidenceGap.temperature);

    // Visibility: a value < 500 fires at any temperature, so absence always
    // leaves the whiteout / reduced-visibility families undecided.
    final vis = slot.visibilityMeters;
    if (vis == null || !vis.isFinite) gaps.add(HazardEvidenceGap.visibility);

    // Road surface: ice / packed snow / slush fire at any temperature. An
    // explicit `unknown` is the caller saying it could not look — which is
    // exactly the case this gap exists to stop being read as "dry".
    final road = slot.estimatedRoadCondition;
    if (road == null || road == RoadConditionEstimate.unknown) {
      gaps.add(HazardEvidenceGap.roadSurface);
    }

    // Precipitation: can only produce a hazard at or below the cold-rain band.
    // Warmer than that, an absent figure could not have changed any verdict.
    final precip = slot.precipitationMmPerHour;
    if ((precip == null || !precip.isFinite) &&
        (!t.isFinite || t <= coldRainTempCelsius)) {
      gaps.add(HazardEvidenceGap.precipitation);
    }

    // Humidity: only decides inside the radiative-frost ambient ceiling.
    final rh = slot.humidityRH;
    if ((rh == null || !rh.isFinite) &&
        (!t.isFinite || t <= radiativeFrostAmbientCeilingCelsius)) {
      gaps.add(HazardEvidenceGap.radiativeFrostHumidity);
    }

    return gaps;
  }

  /// Whether the affirmative "no winter hazard signals in your trip window"
  /// claim is EARNED for this trip — i.e. every hour of the window has a
  /// forecast slot, and every one of those slots left no [evidenceGaps].
  ///
  /// Added in 0.5.3 so a caller can branch BEFORE calling [brief] rather than
  /// catch afterwards. Note this answers only whether the all-clear could be
  /// earned; a window full of measured hazard is not "earned" territory at all
  /// and reports its hazard normally.
  bool allClearEarned({
    required WeatherForecast forecast,
    required CommuteShape commute,
  }) {
    final window = _slotsCovering(
      forecast.hourly,
      commute.plannedDeparture,
      commute.plannedDuration,
    );
    if (window.isEmpty) return false;
    return _unearnedReason(window, commute) == null;
  }

  /// Null when the all-clear is earned; otherwise the reason, ready to throw.
  PretripAssessmentIncompleteException? _unearnedReason(
    List<HourlyForecast> window,
    CommuteShape commute,
  ) {
    final covered = _coversWhole(
      window,
      commute.plannedDeparture,
      commute.plannedDuration,
    );
    final gapsByHour = <DateTime, Set<HazardEvidenceGap>>{};
    for (final s in window) {
      final g = evidenceGaps(s);
      if (g.isNotEmpty) gapsByHour[s.hour] = g;
    }
    if (covered && gapsByHour.isEmpty) return null;
    return PretripAssessmentIncompleteException(
      plannedDeparture: commute.plannedDeparture,
      plannedDuration: commute.plannedDuration,
      gapsByHour: Map.unmodifiable(gapsByHour),
      windowFullyCovered: covered,
    );
  }

  /// Ambient ceiling for the radiative-frost condition, °C.
  ///
  /// The calibration's documented envelope is black ice forming when the
  /// ambient air is "several degrees above 0 °C" (clear-sky radiative
  /// cooling); the dew-point test alone has NO such bound and would fire on
  /// benign dry afternoons (probe-measured: 20 °C at 25% RH) — cry-wolf that
  /// discredits the chip before the genuine near-zero morning. The ceiling
  /// keeps the condition inside the physics the calibration documents.
  static const double radiativeFrostAmbientCeilingCelsius = 3.0;

  /// Humidity-aware black-ice risk with NO precipitation required — the
  /// clear-sky-radiative-cooling window the ambient-only frost check misses:
  /// under dry-to-moderate humidity the road surface can cool below freezing
  /// while the ambient air is still (a few degrees) above 0 °C. (It does NOT
  /// cover near-saturated freezing fog above ~+1 °C; see the calibration doc.)
  ///
  /// Delegates to the family's SINGLE source of truth,
  /// `isRadiativeFrostBlackIce` in `navigation_safety_calibration` — the exact
  /// same function the in-drive road-surface classifier
  /// (`RoadSurfaceState.fromCondition`) calls, so the pre-trip briefing and the
  /// live in-drive screen can never disagree about black ice. That function
  /// owns the ceiling, the caution-add-only construction, the percent→fraction
  /// door, and the never-throw / absence-is-never-hazard contract; see its
  /// doc for the full rationale. [HourlyForecast.humidityRH] is PERCENT and is
  /// passed through unchanged.
  bool radiativeFrostRisk(HourlyForecast slot) => isRadiativeFrostBlackIce(
    ambientCelsius: slot.tempCelsius,
    humidityRHPercent: slot.humidityRH,
  );

  /// Earliest whole-hour delay (up to [searchHorizon]) whose shifted trip
  /// window is fully forecast-covered and at worst [HourHazard.caution].
  Duration? _findBetterWindow(List<HourlyForecast> hourly, CommuteShape c) {
    for (var h = 1; h <= searchHorizon.inHours; h++) {
      final delay = Duration(hours: h);
      final dep = c.plannedDeparture.add(delay);
      final slots = _slotsCovering(hourly, dep, c.plannedDuration);
      if (slots.isEmpty) return null; // forecast ran out — stop searching
      if (!_coversWhole(slots, dep, c.plannedDuration)) return null;
      final peak = slots.map(hazardOf).reduce(_worse);
      if (peak.index <= HourHazard.caution.index) {
        // 0.5.3 — "conditions improve by 08:00" is an AFFIRMATIVE claim about
        // an hour she is not in yet, and acting on it PUTS her there. Up to
        // 0.5.2 an hour with no visibility and no road data scored `clear` and
        // was offered as the better window: the advisor sent her into the one
        // hour it knew least about. An unassessable hour is skipped, not
        // offered — a later, fully-measured hour can still win.
        if (slots.any((s) => evidenceGaps(s).isNotEmpty)) continue;
        return delay;
      }
    }
    return null;
  }

  /// Slots overlapping [start, start + duration). A slot at hour H covers
  /// [H, H + 1h).
  List<HourlyForecast> _slotsCovering(
    List<HourlyForecast> hourly,
    DateTime start,
    Duration duration,
  ) {
    final end = start.add(duration);
    return [
      for (final s in hourly)
        if (s.hour.isBefore(end) &&
            s.hour.add(const Duration(hours: 1)).isAfter(start))
          s,
    ];
  }

  /// True when [slots] leave no gap over [start, start + duration).
  bool _coversWhole(
    List<HourlyForecast> slots,
    DateTime start,
    Duration duration,
  ) {
    final end = start.add(duration);
    var cursor = start;
    for (final s in slots) {
      if (s.hour.isAfter(cursor)) return false;
      final slotEnd = s.hour.add(const Duration(hours: 1));
      if (slotEnd.isAfter(cursor)) cursor = slotEnd;
      if (!cursor.isBefore(end)) return true;
    }
    return !cursor.isBefore(end);
  }

  HourHazard _worse(HourHazard a, HourHazard b) => a.index >= b.index ? a : b;

  String _describe(HourlyForecast slot) {
    final at = _hhmm(slot.hour);
    // 0.5.3 — a chip that states a MEASURED NUMBER may only be built from a
    // finite one. Up to 0.5.2 a `-Infinity` visibility or temperature reached
    // `.round()` here and threw an untyped `UnsupportedError` out of a pure,
    // offline advisor — and NOT one of this package's typed absence stops, so
    // the `on PretripDataAbsentException` clause 0.5.2 asked integrators to
    // write did not catch it. The number-bearing branches below now require
    // `isFinite`; a non-finite field falls through to the defensive fallback
    // at the end, which needs no number. The hazard BAND is unchanged: this
    // is the chip's arithmetic, not the ladder's judgement.
    final visRaw = slot.visibilityMeters;
    final vis = (visRaw != null && visRaw.isFinite) ? visRaw : null;
    final tempFinite = slot.tempCelsius.isFinite;
    if (vis != null && vis < whiteoutVisibilityMeters) {
      return messages.visibilityWhiteout(vis.round(), at);
    }
    if (slot.estimatedRoadCondition == RoadConditionEstimate.ice) {
      return messages.icyRoads(at);
    }
    if (slot.estimatedRoadCondition == RoadConditionEstimate.packedSnow) {
      return messages.packedSnow(at);
    }
    final precip = slot.precipitationMmPerHour;
    if (precip != null && precip > 0 && slot.tempCelsius <= icingTempCelsius) {
      return messages.precipNearFreezing(at);
    }
    if (vis != null && vis < nearWhiteoutVisibilityMeters) {
      return messages.visibilityReducedNearWhiteout(vis.round(), at);
    }
    if (slot.estimatedRoadCondition == RoadConditionEstimate.slush) {
      return messages.slushPossible(at);
    }
    if (precip != null && precip > 0 && slot.tempCelsius <= 2.0) {
      return messages.coldRain(at);
    }
    if (vis != null && vis < 500) {
      return messages.reducedVisibility(vis.round(), at);
    }
    if (tempFinite && slot.tempCelsius <= frostTempCelsius) {
      return messages.freezingAir(slot.tempCelsius.round(), at);
    }
    // Above-zero ambient but the humidity-aware surface estimate crosses
    // freezing — the black-ice window the ambient chip cannot describe.
    if (radiativeFrostRisk(slot)) {
      return messages.blackIceRadiativeRisk(at);
    }

    // Defensive fallback: reached when a slot is caution+ but no branch above
    // can describe it with a number it actually has — which is exactly the
    // non-finite case 0.5.3 stopped crashing on. Also kept so a future
    // threshold change cannot return an empty reason chip.
    return messages.winterConditionsPossible(at);
  }

  String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// Pick the daylight facts for the darkest of the trip's GENUINE instants —
  /// departure and arrival (departure + duration) — so a PRE-DAWN departure or
  /// a dark arrival is covered. The worst-hazard slot is deliberately NOT a
  /// candidate: its hour-start can fall outside the actual trip window, which
  /// would make the chip's "your departure/trip" wording name a time the driver
  /// is not on the road (a wrong clock is worse than no chip). Returns null when
  /// the commute carries no [TripGeo] or when every candidate is in full
  /// daylight (no low-light note to make).
  TripDaylight? _selectDaylight(CommuteShape commute) {
    final geo = commute.geo;
    if (geo == null) return null;

    final candidates = <DateTime>[
      commute.plannedDeparture,
      commute.plannedDeparture.add(commute.plannedDuration),
    ];

    TripDaylight? darkest;
    for (final instant in candidates) {
      final d = evaluateDaylight(instant, geo);
      if (darkest == null || d.severity > darkest.severity) {
        darkest = d;
      }
    }
    if (darkest == null || darkest.severity == 0) return null;
    return darkest;
  }
}
