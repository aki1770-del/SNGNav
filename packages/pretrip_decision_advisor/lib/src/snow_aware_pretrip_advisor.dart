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
    show computeEffectiveTemperatureCelsius;

import 'commute_shape.dart';
import 'daylight.dart';
import 'driver_profile_spec.dart';
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

  /// Slush, light reduced visibility, cold rain, or subzero air temperature
  /// (frost / black-ice risk) — drive with care.
  caution,

  /// Packed snow, near-whiteout visibility (< 200 m), or icing conditions
  /// (precipitation at near-freezing temperature).
  elevated,

  /// Whiteout-class visibility (< 100 m) or forecast ice.
  severe,
}

/// One verdict shape the app UI renders directly. The contract's
/// [PretripRecommendation] is derived from this and carries the same
/// rationale; the briefing keeps the richer typed verdict so the card does
/// not have to re-parse prose.
enum PretripVerdict {
  /// Forecast does not cover the departure window — no recommendation.
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

  /// The contract-shaped recommendation, `null` only for [PretripVerdict.noData].
  final PretripRecommendation? recommendation;

  /// Worst per-hour hazard inside the trip window.
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
  }) =>
      brief(forecast: forecast, commute: commute, profile: profile)
          .recommendation;

  /// The richer briefing the app UI consumes; [advise] derives from it.
  PretripBriefing brief({
    required WeatherForecast forecast,
    required CommuteShape commute,
    required DriverProfileSpec profile,
  }) {
    final window = _slotsCovering(
      forecast.hourly,
      commute.plannedDeparture,
      commute.plannedDuration,
    );
    if (window.isEmpty) {
      return const PretripBriefing(
        verdict: PretripVerdict.noData,
        chips: [],
        recommendation: null,
        peakHazard: HourHazard.clear,
      );
    }

    final peak = window.map(hazardOf).reduce(_worse);
    final worstSlot =
        window.firstWhere((s) => hazardOf(s) == peak, orElse: () => window.first);
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
            chips.add(messages.conditionsLookBetterIfAllows(
              _hhmm(commute.plannedDeparture.add(betterDelay)),
            ));
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
          chips.add(messages.conditionsImproveBy(
            _hhmm(commute.plannedDeparture.add(betterDelay)),
          ));
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
    final icing = precip != null &&
        precip > 0 &&
        slot.tempCelsius <= icingTempCelsius;
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

  /// Humidity-aware black-ice risk with NO precipitation required — the
  /// freezing-fog / hoar-frost killer the ambient-only frost check misses:
  /// clear-sky radiative cooling can take the road surface below freezing
  /// while the ambient air is still above 0 °C.
  ///
  /// Uses the family's single calibration source of truth (Magnus dew-point
  /// depression; `computeEffectiveTemperatureCelsius` returns a CONSERVATIVE
  /// road-surface estimate — deliberately early-warning; see the calibration
  /// module's citations and UNVERIFIED-magnitude caveat). Caution-add-only by
  /// construction: effective ≤ ambient always, so this can only ADD the
  /// above-zero-ambient window, never remove an existing flag.
  ///
  /// Unit seam, handled explicitly: [HourlyForecast.humidityRH] is PERCENT;
  /// the calibration takes a FRACTION `(0, 1]`. Mirrors the percent-door
  /// semantics of `navigation_safety_core`: supersaturation `(100, 105]`
  /// reads as saturated air (1.0); `<= 0` (missing-data sentinel) and
  /// implausible values add NOTHING — absence of data is never presence
  /// of hazard.
  bool radiativeFrostRisk(HourlyForecast slot) {
    final rhPercent = slot.humidityRH;
    if (rhPercent == null ||
        !rhPercent.isFinite ||
        rhPercent <= 0.0 ||
        rhPercent > 105.0) {
      return false;
    }
    final fraction = rhPercent > 100.0 ? 1.0 : rhPercent / 100.0;
    final effective = computeEffectiveTemperatureCelsius(
      ambientCelsius: slot.tempCelsius,
      humidityRH: fraction,
    );
    return effective <= frostTempCelsius;
  }

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
      if (peak.index <= HourHazard.caution.index) return delay;
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

  HourHazard _worse(HourHazard a, HourHazard b) =>
      a.index >= b.index ? a : b;

  String _describe(HourlyForecast slot) {
    final at = _hhmm(slot.hour);
    final vis = slot.visibilityMeters;
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
    if (slot.tempCelsius <= frostTempCelsius) {
      return messages.freezingAir(slot.tempCelsius.round(), at);
    }
    // Above-zero ambient but the humidity-aware surface estimate crosses
    // freezing — the black-ice window the ambient chip cannot describe.
    if (radiativeFrostRisk(slot)) {
      return messages.blackIceRadiativeRisk(at);
    }
    // Defensive fallback: unreachable given the current hazardOf ladder (any
    // slot that reaches _describe is caution+ and matches a branch above), but
    // kept so a future threshold change cannot return an empty reason chip.
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
