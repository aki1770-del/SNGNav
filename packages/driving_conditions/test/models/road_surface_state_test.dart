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
  });
}
