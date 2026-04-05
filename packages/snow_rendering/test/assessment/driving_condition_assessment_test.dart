import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';
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
  group('DrivingConditionAssessment.fromCondition', () {
    test('clear warm → dry surface, gripFactor 1.0', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.surfaceState, RoadSurfaceState.dry);
      expect(a.gripFactor, 1.0);
    });

    test('gripFactor matches surfaceState.gripFactor', () {
      final conditions = [
        _condition(iceRisk: true),
        _condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 10,
        ),
        _condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -5,
        ),
      ];
      for (final c in conditions) {
        final a = DrivingConditionAssessment.fromCondition(c);
        expect(a.gripFactor, a.surfaceState.gripFactor,
            reason: 'gripFactor mismatch for ${a.surfaceState}');
      }
    });

    test('clear warm → no precipitation config', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.precipitation, PrecipitationConfig.none);
    });

    test('clear 10000m visibility → no visibility degradation', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.visibility, VisibilityDegradation.clear);
    });

    test('fog 100m → high opacity degradation', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 100),
      );
      expect(a.visibility.opacity, closeTo(0.9, 0.001));
      expect(a.visibility.blurSigma, closeTo(8.0, 0.001));
    });

    test('iceRisk → advisory contains "Black ice"', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(iceRisk: true),
      );
      expect(a.advisoryMessage, contains('Black ice'));
    });

    test('blackIce from cold → advisory contains "Black ice"', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(temperatureCelsius: -5),
      );
      expect(a.advisoryMessage, contains('Black ice'));
    });

    test('compactedSnow → advisory contains "Compacted snow"', () {
      final a = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5,
      ));
      expect(a.advisoryMessage, contains('Compacted snow'));
    });

    test('slush → advisory contains "Slushy"', () {
      final a = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.sleet,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(a.advisoryMessage, contains('Slushy'));
    });

    test('standingWater → advisory contains "Standing water"', () {
      final a = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: 10,
      ));
      expect(a.advisoryMessage, contains('Standing water'));
    });

    test('wet → advisory contains "Wet road"', () {
      final a = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 10,
      ));
      expect(a.advisoryMessage, contains('Wet road'));
    });

    test('dry clear conditions → "Conditions normal"', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.advisoryMessage, 'Conditions normal');
    });

    test('reduced visibility on dry road → fog advisory', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 100),
      );
      expect(a.advisoryMessage, contains('fog lights'));
    });

    test('snow heavy warm → precipitation config non-zero', () {
      final a = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: 5,
      ));
      expect(a.precipitation.particleCount, greaterThan(0));
    });

    test('equality — same condition produces equal assessment', () {
      final cond = _condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.moderate,
        temperatureCelsius: 8,
      );
      expect(
        DrivingConditionAssessment.fromCondition(cond),
        DrivingConditionAssessment.fromCondition(cond),
      );
    });
  });
}
