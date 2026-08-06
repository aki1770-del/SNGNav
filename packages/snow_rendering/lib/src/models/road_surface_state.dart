/// Road surface state classification for driving conditions.
///
/// Six states derived from weather conditions using a decision tree.
/// Each state has an associated grip factor (0.0–1.0) representing
/// tyre-to-road adhesion.
///
/// Use [RoadSurfaceState.fromCondition] to classify from a
/// [WeatherCondition], or wrap in [HysteresisFilter] to debounce
/// rapid oscillation at boundary conditions.
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart'
    show isRadiativeFrostBlackIce, radiativeFrostAmbientCeilingCelsius;

/// Road surface classification.
enum RoadSurfaceState {
  /// Dry pavement — full grip.
  dry(gripFactor: 1.0),

  /// Wet pavement — rain, no ice risk.
  wet(gripFactor: 0.7),

  /// Slush — melting snow or mixed precipitation.
  slush(gripFactor: 0.5),

  /// Compacted snow — cold, moderate-to-heavy snowfall.
  compactedSnow(gripFactor: 0.3),

  /// Black ice — invisible ice layer, extremely low grip.
  blackIce(gripFactor: 0.15),

  /// Standing water — heavy rain pooling on road.
  standingWater(gripFactor: 0.6);

  /// Tyre-to-road grip coefficient (0.0–1.0).
  final double gripFactor;

  const RoadSurfaceState({required this.gripFactor});

  /// Classify road surface from current weather, or `null` when the weather
  /// data does not permit a classification.
  ///
  /// ## `null` means "cannot classify" — it is never [dry]
  ///
  /// Up to 0.2.7 this returned a non-nullable [RoadSurfaceState], so a
  /// [WeatherCondition] carrying no measurements fell through the decision tree
  /// to [dry] — and [dry] carries `gripFactor: 1.0`. Absence of data became
  /// MAXIMUM GRIP, then `RecommendedResponse.proceed`, then the advisory
  /// "Conditions normal", shown to a driver on a road nobody had measured.
  /// That was the fatal path of the Measured-or-Absent defect (see CHANGELOG).
  ///
  /// Under the contract, absence is a value: this returns `null` when the
  /// condition does not carry enough to classify. `null` is not a surface —
  /// it has no grip factor, and callers must say so rather than invent one.
  ///
  /// The asymmetry is deliberate and matches `driving_weather`'s
  /// [SafetyVerdict]: POSITIVE evidence of a hazard classifies even on partial
  /// data (an asserted `iceRisk`, or deep cold), while any benign
  /// classification — above all [dry] — requires knowing BOTH the temperature
  /// and the precipitation type, AND, inside the radiative-frost window, the
  /// humidity that determination rests on: a check that ABSTAINED never
  /// counts as a check that cleared the road. Being offline does not mean
  /// "ice"; it means "unknown", and unknown is a thing the driver is TOLD.
  ///
  /// Decision tree follows the position paper specification.
  /// For debounced classification, wrap with [HysteresisFilter].
  static RoadSurfaceState? fromCondition(WeatherCondition condition) {
    // POSITIVE evidence fires even when every other field is absent.
    if (condition.iceRisk == true) return blackIce;

    final temp = condition.temperatureCelsius;
    final precip = condition.precipType;

    if (precip == null) {
      // Precipitation unreported. We cannot tell snow from a dry road — but two
      // POSITIVE ice determinations rest on the temperature alone and therefore
      // still fire (caution-add-only; this state could not arise before 0.3.0,
      // so it regresses nothing, and an absent field must never SUPPRESS a
      // hazard a known field already justifies).
      if (temp != null) {
        // Deep cold: residual ice, whatever the sky is doing.
        if (temp <= -3) return blackIce;

        // Radiative-frost black ice — the classic Akita pre-dawn bridge-deck
        // hazard, and the one that matters most here: it is detected from
        // temperature + humidity, NOT from precipitation. Gating it behind a
        // *reported* `precipType` would mean a vehicle with a real thermometer
        // and a real hygrometer, but no rain sensor, silently lost its black-ice
        // detection — the offline path, which is exactly where this check earns
        // its keep (it fires BEFORE friction/traction, i.e. before the wheels
        // have already slipped). Still humidity-gated: absent humidity abstains
        // and never fabricates the hazard.
        if (isRadiativeFrostBlackIce(
          ambientCelsius: temp,
          humidityRHPercent: condition.humidityRH,
        )) {
          return blackIce;
        }
      }
      return null;
    }

    // Every remaining branch needs the temperature: it is what separates rain
    // from freezing rain, and slush from compacted snow. Without it we do not
    // know the surface — and we will not guess in the benign direction.
    if (temp == null) return null;

    if (precip == PrecipitationType.none) {
      // Cold dry conditions can still have residual ice.
      if (temp <= -3) return blackIce;
      // Radiative-frost black ice: with NO precipitation and the air still a
      // few degrees ABOVE 0 °C, clear-sky cooling can drop the road surface
      // below freezing (the classic Akita pre-dawn bridge-deck hazard). This
      // calls the family's single calibration source of truth — the SAME
      // function the pre-trip advisor uses — so, GIVEN THE SAME temperature +
      // humidity, the in-drive classifier and the pre-trip briefing cannot
      // disagree about this black-ice determination. Scope, stated honestly:
      // this reconciles only the radiative-frost window, and there is no
      // wind/time-of-day gate yet (all-hours). Caution-add-only: it can only
      // ADD the above-zero-ambient window, and absent humidity never
      // FABRICATES the hazard (see KNOWN_LIMITATIONS.md).
      if (isRadiativeFrostBlackIce(
        ambientCelsius: temp,
        humidityRHPercent: condition.humidityRH,
      )) {
        return blackIce;
      }

      // The frost check declined — and WHY it declined decides what we are
      // entitled to say next. It declines for two different reasons, and they
      // are not the same answer:
      //
      //   * it JUDGED — the temperature alone put us above the check's ambient
      //     ceiling, or the dew-point maths came back warm enough. Something
      //     was measured, and `dry` is earned.
      //   * it ABSTAINED — inside the frost window the determination rests on
      //     the humidity, and the feed carried none. Nothing was measured.
      //
      // Reporting an abstention as `dry` is the fabricated-clear: `dry` carries
      // `gripFactor: 1.0` (MAXIMUM GRIP), which becomes
      // `RecommendedResponse.proceed` and the advisory "Conditions normal" — a
      // POSITIVE claim about a road whose deciding field nobody read. It is why
      // a hygrometer-less feed at −2.9 °C was told the road was normal while
      // the SAME feed WITH a humidity reading was told "Black ice risk".
      //
      // So this is the `precip == null` branch's discipline (above) applied at
      // the one-field-absent seam: same abstention, same answer, `null`. `null`
      // is not an alarm and cannot cry wolf — it says "not measured", and the
      // assessment layer renders it "Road surface not measured here — drive to
      // what you can see" instead of an all-clear.
      //
      // Bounded deliberately at the ceiling. ABOVE it the check declines on the
      // TEMPERATURE, which WAS measured, so `dry` stays honest there; turning
      // every warm dry road into "unknown" would be the cry-wolf inverse and a
      // defect of its own (SAFETY_BOUNDARY.md §3).
      final humidity = condition.humidityRH;
      if (temp <= radiativeFrostAmbientCeilingCelsius &&
          (humidity == null || !humidity.isFinite)) {
        return null;
      }
      return dry;
    }

    switch (precip) {
      case PrecipitationType.rain:
        if (temp <= 0) return blackIce; // Freezing rain.
        if (condition.intensity == PrecipitationIntensity.heavy && temp > 3) {
          return standingWater;
        }
        return wet;

      case PrecipitationType.snow:
        if (temp > 2) return slush; // Melting.
        if (temp < -2 &&
            (condition.intensity == PrecipitationIntensity.moderate ||
                condition.intensity == PrecipitationIntensity.heavy)) {
          return compactedSnow;
        }
        return slush;

      case PrecipitationType.sleet:
        return slush;

      case PrecipitationType.hail:
        if (condition.intensity == PrecipitationIntensity.heavy) {
          return standingWater;
        }
        return wet;

      case PrecipitationType.none:
        return dry; // Unreachable — handled above.
    }
  }
}

/// Debounce filter that prevents rapid state oscillation.
///
/// Requires a new state to appear in at least [threshold] of the last
/// [windowSize] readings before transitioning. Defaults: window 3,
/// threshold 2.
class HysteresisFilter<T> {
  final int windowSize;
  final int threshold;
  final List<T> _buffer = [];
  T? _current;

  /// Whether [_current] holds a real reading.
  ///
  /// This exists because `T` may itself be NULLABLE. Since 0.3.0,
  /// `RoadSurfaceState.fromCondition` can honestly return `null` ("cannot
  /// classify"), so a filter is routinely instantiated as
  /// `HysteresisFilter<RoadSurfaceState?>` — and then a genuine `null` reading
  /// is a VALID state, not the absence of one.
  ///
  /// Up to 0.2.7 this class used `_current == null` as its "nothing seen yet"
  /// sentinel. With a nullable `T` that sentinel is ambiguous: every real `null`
  /// reading would look like "not seeded", the seeding branch would fire on
  /// every frame, and the filter would **silently stop debouncing** — accepting
  /// the very single-frame flicker it exists to suppress. A separate flag is the
  /// only way to tell "I have seen nothing" from "I have seen an unknown".
  bool _seeded = false;

  HysteresisFilter({this.windowSize = 3, this.threshold = 2});

  /// Current stabilised state.
  ///
  /// When `T` is nullable this is ambiguous on its own — check [hasCurrent] to
  /// distinguish "no readings yet" from "a reading whose value is `null`".
  T? get current => _current;

  /// Whether any reading has been accepted yet.
  bool get hasCurrent => _seeded;

  /// Add a new reading and return the stabilised state.
  T add(T reading) {
    _buffer.add(reading);
    if (_buffer.length > windowSize) {
      _buffer.removeAt(0);
    }

    // Count occurrences of the new reading in the window.
    final count = _buffer.where((e) => e == reading).length;
    if (count >= threshold || !_seeded) {
      _current = reading;
      _seeded = true;
    }
    return _current as T;
  }

  /// Alias for [add] to keep the API intention explicit at call sites.
  T update(T reading) => add(reading);

  /// Reset the filter, clearing all buffered readings.
  void reset() {
    _buffer.clear();
    _current = null;
    _seeded = false;
  }
}
