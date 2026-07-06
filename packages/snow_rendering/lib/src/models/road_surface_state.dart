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
      // calls the family's single calibration source of truth — the SAME
      // function the pre-trip advisor uses — so, GIVEN THE SAME temperature +
      // humidity, the in-drive classifier and the pre-trip briefing cannot
      // disagree about this black-ice determination. Scope, stated honestly:
      // this reconciles only the radiative-frost window; a feed that omits
      // humidity abstains here (see KNOWN_LIMITATIONS.md), and there is no
      // wind/time-of-day gate yet (all-hours). Humidity-gated and
      // caution-add-only: absent humidity returns dry, never fabricating the
      // hazard and never downgrading a colder classification.
      if (isRadiativeFrostBlackIce(
        ambientCelsius: temp,
        humidityRHPercent: condition.humidityRH,
      )) {
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
