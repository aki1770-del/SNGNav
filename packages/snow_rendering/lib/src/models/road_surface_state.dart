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
    show isRadiativeFrostBlackIce;

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

  /// Classify road surface from current weather.
  ///
  /// **SAFETY NOTE (0.2.x line):** this method cannot say "I don't know" —
  /// its return is non-nullable, and the 0.4.x-era [WeatherCondition] forces
  /// every field to hold a value. A condition built from FILLER values
  /// classifies as [dry] (gripFactor 1.0). Never call this with fields you
  /// did not measure; gate absence at your call site and tell your user
  /// "unknown". The 0.3.0 line fixes this in the type system (nullable
  /// return; nullable measurements) — prefer it for any new integration.
  ///
  /// Decision tree follows the position paper specification.
  /// For debounced classification, wrap with [HysteresisFilter].
  static RoadSurfaceState fromCondition(WeatherCondition condition) {
    if (condition.iceRisk) return blackIce;

    final temp = condition.temperatureCelsius;

    if (condition.precipType == PrecipitationType.none) {
      // Cold dry conditions can still have residual ice.
      if (temp <= -3) return blackIce;
      // Radiative-frost black ice: with NO precipitation and the air still a
      // few degrees ABOVE 0 °C, clear-sky cooling can drop the road surface
      // below freezing (the classic Akita pre-dawn bridge-deck hazard). This
      // branch CALLS the exported [isInvisibleIceWindow] predicate — the one
      // copy of the window logic — whose only decision source is the family's
      // single calibration function ([isRadiativeFrostBlackIce], the SAME
      // function the pre-trip advisor uses) — so, GIVEN THE SAME temperature +
      // humidity, the in-drive classifier, the pre-trip briefing, and any
      // consumer of the predicate cannot disagree about this black-ice
      // determination. Scope, stated honestly: this reconciles only the
      // radiative-frost window; a feed that omits humidity abstains here (see
      // KNOWN_LIMITATIONS.md), and there is no wind/time-of-day gate yet
      // (all-hours). Humidity-gated and caution-add-only: absent humidity
      // returns dry, never fabricating the hazard and never downgrading a
      // colder classification.
      if (isInvisibleIceWindow(condition)) {
        return blackIce;
      }
      return dry;
    }

    switch (condition.precipType) {
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

  /// The invisible-ice (radiative-frost) window predicate — the
  /// provenance fact [fromCondition]'s return value cannot carry.
  ///
  /// Returns `true` when [condition] sits in the radiative-frost
  /// black-ice window: NO precipitation falling, ambient above the
  /// cold-dry regime (> −3 °C), and the family's single calibration
  /// source of truth ([isRadiativeFrostBlackIce]) determines that
  /// clear-sky cooling can have carried the road surface to or below
  /// freezing. This is the invisible morning: nothing is falling, the
  /// road looks merely wet or dry — and it may be frozen. It is the
  /// one classifier path on which the looks-wet surprise clause of
  /// `invisibleBlackIceAnnouncement` is true.
  ///
  /// **Why this is exported.** A consumer selecting between the
  /// general black-ice announcement and the invisible-ice variant
  /// previously had to re-implement this gate around [fromCondition]:
  /// pre-checking temperature and precipitation itself, then inferring
  /// the path from the [blackIce] result. Two independently maintained
  /// copies of the window logic are a drift seam — if this decision
  /// tree gains a path or moves a threshold, every call-site copy
  /// silently disagrees with the classifier (the exact
  /// two-copies-disagree failure the calibration package documents).
  /// [fromCondition]'s radiative branch CALLS this predicate — there is
  /// one copy of the window logic, so consumer and classifier cannot
  /// drift; the alignment sweeps test-catch any future decoupling in
  /// both directions.
  ///
  /// Honest semantics, stated precisely:
  ///
  /// - It describes the MEASURED window, independent of the feed's
  ///   `iceRisk` flag: if the flag is set AND the no-precipitation
  ///   window holds, this still returns `true`. ([fromCondition]
  ///   short-circuits on the flag, but the invisible-morning fact does
  ///   not depend on which check ran first — nothing is falling and
  ///   the road still looks merely wet.)
  /// - Cold-dry (≤ −3 °C, no precipitation) returns `false`: that is
  ///   the EXPECTED-frozen regime, not the above-freezing surprise —
  ///   mirroring [fromCondition]'s branch ordering.
  /// - Freezing rain returns `false` (precipitation is falling —
  ///   outside this no-precipitation window). Freezing rain IS
  ///   invisible-ice phenomenology — glare ice from rain looks merely
  ///   wet — but the classifier's rain-at-≤0 °C branch cannot
  ///   distinguish a true freezing-rain event from a marginal or
  ///   erroneous temperature reading during cold rain, so the strong
  ///   looks-wet claim is deliberately not attached on that path. A
  ///   consumer with genuine freezing-rain detection (a dedicated feed
  ///   signal, not the temperature heuristic) may select the
  ///   invisible-ice announcement deliberately.
  /// - Absence abstains: a missing or non-finite humidity or a
  ///   non-finite temperature returns `false` — the window is never
  ///   fabricated from unmeasured fields (the calibration function's
  ///   own never-throws, absence-is-never-hazard contract).
  ///
  /// Alignment guarantee (tested): whenever this returns `true`,
  /// [fromCondition] classifies the same condition as [blackIce].
  static bool isInvisibleIceWindow(WeatherCondition condition) {
    if (condition.precipType != PrecipitationType.none) return false;
    final temp = condition.temperatureCelsius;
    // Cold-dry regime: expected-frozen, not the invisible surprise.
    // (A non-finite temperature falls through and abstains inside
    // isRadiativeFrostBlackIce, which rejects it.)
    if (temp <= -3) return false;
    return isRadiativeFrostBlackIce(
      ambientCelsius: temp,
      humidityRHPercent: condition.humidityRH,
    );
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

  HysteresisFilter({this.windowSize = 3, this.threshold = 2});

  /// Current stabilised state, or `null` if no readings yet.
  T? get current => _current;

  /// Add a new reading and return the stabilised state.
  T add(T reading) {
    _buffer.add(reading);
    if (_buffer.length > windowSize) {
      _buffer.removeAt(0);
    }

    // Count occurrences of the new reading in the window.
    final count = _buffer.where((e) => e == reading).length;
    if (count >= threshold || _current == null) {
      _current = reading;
    }
    return _current as T;
  }

  /// Alias for [add] to keep the API intention explicit at call sites.
  T update(T reading) => add(reading);

  /// Reset the filter, clearing all buffered readings.
  void reset() {
    _buffer.clear();
    _current = null;
  }
}
