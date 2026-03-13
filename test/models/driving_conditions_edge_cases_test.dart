library;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_test/flutter_test.dart';

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
    test('clear warm returns dry', () {
      expect(RoadSurfaceState.fromCondition(_condition()), RoadSurfaceState.dry);
    });

    test('iceRisk overrides all other branches', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 20,
          iceRisk: true,
        )),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip at exactly -3C returns blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(temperatureCelsius: -3)),
        RoadSurfaceState.blackIce,
      );
    });

    test('no precip above -3C returns dry', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(temperatureCelsius: -2)),
        RoadSurfaceState.dry,
      );
    });

    test('rain at 0C returns blackIce', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 0,
        )),
        RoadSurfaceState.blackIce,
      );
    });

    test('rain at 1C returns wet', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 1,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('heavy rain at exactly 3C returns wet', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 3,
        )),
        RoadSurfaceState.wet,
      );
    });

    test('heavy rain above 3C returns standingWater', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 4,
        )),
        RoadSurfaceState.standingWater,
      );
    });

    test('snow above 2C returns slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: 3,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('snow at exactly 2C returns slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: 2,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('snow at exactly -2C returns slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -2,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('moderate snow below -2C returns compactedSnow', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -3,
        )),
        RoadSurfaceState.compactedSnow,
      );
    });

    test('light snow below -2C still returns slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: -5,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('sleet returns slush', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.sleet,
          intensity: PrecipitationIntensity.moderate,
        )),
        RoadSurfaceState.slush,
      );
    });

    test('heavy hail returns standingWater', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.hail,
          intensity: PrecipitationIntensity.heavy,
        )),
        RoadSurfaceState.standingWater,
      );
    });

    test('moderate hail returns wet', () {
      expect(
        RoadSurfaceState.fromCondition(_condition(
          precipType: PrecipitationType.hail,
          intensity: PrecipitationIntensity.moderate,
        )),
        RoadSurfaceState.wet,
      );
    });
  });

  group('RoadSurfaceState grip factors', () {
    test('dry grip is 1.0', () {
      expect(RoadSurfaceState.dry.gripFactor, 1.0);
    });

    test('wet grip is 0.7', () {
      expect(RoadSurfaceState.wet.gripFactor, 0.7);
    });

    test('standingWater grip is 0.6', () {
      expect(RoadSurfaceState.standingWater.gripFactor, 0.6);
    });

    test('slush grip is 0.5', () {
      expect(RoadSurfaceState.slush.gripFactor, 0.5);
    });

    test('compactedSnow grip is 0.3', () {
      expect(RoadSurfaceState.compactedSnow.gripFactor, 0.3);
    });

    test('blackIce grip is 0.15', () {
      expect(RoadSurfaceState.blackIce.gripFactor, 0.15);
    });

    test('all grip factors stay within 0 to 1', () {
      for (final state in RoadSurfaceState.values) {
        expect(state.gripFactor, inInclusiveRange(0.0, 1.0));
      }
    });
  });

  group('HysteresisFilter', () {
    test('first reading sets current immediately', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      expect(filter.update(RoadSurfaceState.dry), RoadSurfaceState.dry);
    });

    test('single transient change does not transition', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      expect(filter.update(RoadSurfaceState.wet), RoadSurfaceState.dry);
    });

    test('two matching readings transition to new state', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      expect(filter.update(RoadSurfaceState.wet), RoadSurfaceState.wet);
    });

    test('rapid three-way oscillation stays on stable state', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      filter.update(RoadSurfaceState.slush);
      expect(filter.current, RoadSurfaceState.dry);
    });

    test('reset clears current state', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      filter.update(RoadSurfaceState.dry);
      filter.reset();
      expect(filter.current, isNull);
    });

    test('custom threshold delays transition', () {
      final filter = HysteresisFilter<RoadSurfaceState>(
        windowSize: 5,
        threshold: 3,
      );
      filter.update(RoadSurfaceState.dry);
      filter.update(RoadSurfaceState.wet);
      filter.update(RoadSurfaceState.wet);
      expect(filter.current, RoadSurfaceState.dry);
      expect(filter.update(RoadSurfaceState.wet), RoadSurfaceState.wet);
    });
  });

  group('VisibilityDegradation.compute', () {
    test('negative visibility clamps to zero', () {
      final result = VisibilityDegradation.compute(-1);
      expect(result.opacity, 0.9);
      expect(result.blurSigma, 10.0);
    });

    test('zero visibility returns max degradation', () {
      final result = VisibilityDegradation.compute(0);
      expect(result.opacity, 0.9);
      expect(result.blurSigma, 10.0);
    });

    test('100m visibility returns dense fog values', () {
      final result = VisibilityDegradation.compute(100);
      expect(result.opacity, 0.9);
      expect(result.blurSigma, 8.0);
    });

    test('500m visibility returns zero blur boundary', () {
      final result = VisibilityDegradation.compute(500);
      expect(result.opacity, 0.5);
      expect(result.blurSigma, 0.0);
    });

    test('501m visibility stays at zero blur', () {
      final result = VisibilityDegradation.compute(501);
      expect(result.blurSigma, 0.0);
      expect(result.opacity, lessThan(0.5));
    });

    test('1000m visibility returns clear', () {
      expect(
        VisibilityDegradation.compute(1000),
        VisibilityDegradation.clear,
      );
    });

    test('very high visibility remains clear', () {
      expect(
        VisibilityDegradation.compute(10000),
        VisibilityDegradation.clear,
      );
    });

    test('equal inputs produce equal outputs', () {
      expect(
        VisibilityDegradation.compute(300),
        VisibilityDegradation.compute(300),
      );
    });

    test('different inputs produce different outputs', () {
      expect(
        VisibilityDegradation.compute(300),
        isNot(equals(VisibilityDegradation.compute(400))),
      );
    });
  });
}