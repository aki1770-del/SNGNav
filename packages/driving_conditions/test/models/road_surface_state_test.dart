import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';

WeatherCondition _condition({
  PrecipitationType precipType = PrecipitationType.none,
  PrecipitationIntensity intensity = PrecipitationIntensity.none,
  double temperatureCelsius = 5.0,
  double visibilityMeters = 10000,
  bool iceRisk = false,
}) =>
    WeatherCondition(
      precipType: precipType,
      intensity: intensity,
      temperatureCelsius: temperatureCelsius,
      visibilityMeters: visibilityMeters,
      windSpeedKmh: 0,
      iceRisk: iceRisk,
      timestamp: DateTime(2026),
    );

void main() {
  group('RoadSurfaceState.fromCondition', () {
    test('clear warm → dry', () {
      expect(
        RoadSurfaceState.fromCondition(_condition()),
        RoadSurfaceState.dry,
      );
    });

    test('iceRisk flag → blackIce regardless of precip', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(iceRisk: true)),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip, very cold → blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: -5),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('rain heavy warm → standingWater', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 10,
        )),
        RoadSurfaceState.standingWater,
      );
    });

    test('rain light warm → wet', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 10,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('freezing rain → blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -1,
        )),
        RoadSurfaceState.blackIce,
      );
    });

    test('snow warm → slush (melting)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: 3,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('snow cold heavy → compactedSnow', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -5,
        )),
        RoadSurfaceState.compactedSnow,
      );
    });

    test('sleet → slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.sleet,
          intensity: PrecipitationIntensity.moderate,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('hail heavy → standingWater', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.hail,
          intensity: PrecipitationIntensity.heavy,
        )),
        RoadSurfaceState.standingWater,
      );
    });

    test('snow cold light → slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: -5,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('hail light → wet', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.hail,
          intensity: PrecipitationIntensity.light,
        )),
        RoadSurfaceState.wet,
      );
    });

    // Boundary regression tests (S50-2 in-flight review)
    test('heavy rain at exactly 3°C → wet (boundary, not standingWater)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 3,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('snow at exactly 2°C → slush (boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: 2,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('snow moderate at exactly -2°C → slush (boundary, not compacted)',
        () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -2,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('no precip at exactly -3°C → blackIce (boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: -3),
        ),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip at -2°C → dry (above blackIce threshold)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: -2),
        ),
        RoadSurfaceState.dry,
      );
    });

    test('rain at exactly 0°C → blackIce (freezing boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 0,
        )),
        RoadSurfaceState.blackIce,
      );
    });

    test('rain at exactly 1°C → wet (just above freezing)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 1,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('heavy rain at exactly 3°C → wet (not standingWater, needs >3)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 3,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('heavy rain at 4°C → standingWater (just above 3°C boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 4,
        )),
        RoadSurfaceState.standingWater,
      );
    });

    test('snow at exactly -2°C moderate → slush (boundary, not compacted)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -2,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('snow at -3°C moderate → compactedSnow (crosses <-2 boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -3,
        )),
        RoadSurfaceState.compactedSnow,
      );
    });

    test('snow at exactly 2°C → slush (boundary, melting)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: 2,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('snow at 3°C → slush (above >2 boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: 3,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('hail moderate → wet (not heavy, not standingWater)', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.hail,
          intensity: PrecipitationIntensity.moderate,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('iceRisk overrides snow classification', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 5,
          iceRisk: true,
        )),
        RoadSurfaceState.blackIce,
      );
    });

    test('iceRisk overrides rain classification', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 20,
          iceRisk: true,
        )),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip at exactly -3°C → blackIce (boundary)', () {
      expect(
        RoadSurfaceState.fromCondition(
          _condition(temperatureCelsius: -3),
        ),
        RoadSurfaceState.blackIce,
      );
    });
  });

  group('RoadSurfaceState grip factors', () {
    test('dry = 1.0', () {
      expect(RoadSurfaceState.dry.gripFactor, 1.0);
    });

    test('blackIce = 0.15', () {
      expect(RoadSurfaceState.blackIce.gripFactor, 0.15);
    });

    test('standingWater = 0.6', () {
      expect(RoadSurfaceState.standingWater.gripFactor, 0.6);
    });

    test('wet = 0.7', () {
      expect(RoadSurfaceState.wet.gripFactor, 0.7);
    });

    test('slush = 0.5', () {
      expect(RoadSurfaceState.slush.gripFactor, 0.5);
    });

    test('compactedSnow = 0.3', () {
      expect(RoadSurfaceState.compactedSnow.gripFactor, 0.3);
    });

    test('all grip factors are in 0.0–1.0 range', () {
      for (final state in RoadSurfaceState.values) {
        expect(state.gripFactor, greaterThanOrEqualTo(0.0));
        expect(state.gripFactor, lessThanOrEqualTo(1.0));
      }
    });

    test('grip factors are ordered: dry > wet > standingWater > slush > compactedSnow > blackIce', () {
      expect(RoadSurfaceState.dry.gripFactor,
          greaterThan(RoadSurfaceState.wet.gripFactor));
      expect(RoadSurfaceState.wet.gripFactor,
          greaterThan(RoadSurfaceState.standingWater.gripFactor));
      expect(RoadSurfaceState.standingWater.gripFactor,
          greaterThan(RoadSurfaceState.slush.gripFactor));
      expect(RoadSurfaceState.slush.gripFactor,
          greaterThan(RoadSurfaceState.compactedSnow.gripFactor));
      expect(RoadSurfaceState.compactedSnow.gripFactor,
          greaterThan(RoadSurfaceState.blackIce.gripFactor));
    });
  });

  group('HysteresisFilter', () {
    test('debounces transient changes', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      // 3 readings needed, threshold 2
      expect(filter.update(RoadSurfaceState.dry), RoadSurfaceState.dry);
      expect(filter.update(RoadSurfaceState.wet), RoadSurfaceState.dry);
      expect(filter.update(RoadSurfaceState.dry), RoadSurfaceState.dry);
    });

    test('transitions when threshold met', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      final result = filter.update(RoadSurfaceState.wet);
      expect(result, RoadSurfaceState.wet);
    });

    test('reset clears buffered state', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      filter.reset();
      expect(filter.current, isNull);
      expect(filter.update(RoadSurfaceState.slush), RoadSurfaceState.slush);
    });

    test('rapid three-way oscillation stays on first state', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      filter.update(RoadSurfaceState.slush);
      // None reached threshold=2 except dry (which was first/current)
      expect(filter.current, RoadSurfaceState.dry);
    });

    test('custom window and threshold', () {
      final filter = HysteresisFilter<RoadSurfaceState>(
        windowSize: 5,
        threshold: 3,
      );
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      filter.update(RoadSurfaceState.wet);
      // 2 wet out of 3 readings, threshold is 3 — not enough
      expect(filter.current, RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      // 3 wet out of 4 readings — threshold met
      expect(filter.current, RoadSurfaceState.wet);
    });

    test('first reading always sets current', () {
      final filter = HysteresisFilter<String>();
      expect(filter.current, isNull);
      expect(filter.update('hello'), 'hello');
    });

    test('add and update are aliases', () {
      final filter = HysteresisFilter<int>();
      expect(filter.add(1), 1);
      expect(filter.update(2), 1); // not enough to transition
      expect(filter.add(2), 2); // threshold met
    });
  });
}
