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
  group('DrivingConditionAssessment.fromCondition', () {
    test('clear conditions produce normal assessment', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition());

      expect(assessment.surfaceState, RoadSurfaceState.dry);
      expect(assessment.gripFactor, 1.0);
      expect(assessment.visibility, VisibilityDegradation.clear);
      expect(assessment.precipitation, PrecipitationConfig.none);
      expect(assessment.advisoryMessage, 'Conditions normal');
    });

    test('ice risk prioritises black ice advisory', () {
      final assessment = DrivingConditionAssessment.fromCondition(
        _condition(iceRisk: true),
      );

      expect(assessment.surfaceState, RoadSurfaceState.blackIce);
      expect(
        assessment.advisoryMessage,
        'Black ice risk — reduce speed significantly',
      );
    });

    test('compacted snow advisory is returned', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5,
      ));

      expect(assessment.surfaceState, RoadSurfaceState.compactedSnow);
      expect(
        assessment.advisoryMessage,
        'Compacted snow — use winter tyres, reduce speed',
      );
    });

    test('slush advisory is returned', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.sleet,
        intensity: PrecipitationIntensity.moderate,
      ));

      expect(assessment.surfaceState, RoadSurfaceState.slush);
      expect(
        assessment.advisoryMessage,
        'Slushy conditions — maintain safe following distance',
      );
    });

    test('standing water advisory is returned', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: 10,
      ));

      expect(assessment.surfaceState, RoadSurfaceState.standingWater);
      expect(
        assessment.advisoryMessage,
        'Standing water — risk of aquaplaning at speed',
      );
    });

    test('reduced visibility advisory is returned', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition(
        visibilityMeters: 300,
      ));

      expect(assessment.surfaceState, RoadSurfaceState.dry);
      expect(
        assessment.advisoryMessage,
        'Reduced visibility — use fog lights, reduce speed',
      );
    });

    test('wet road advisory is returned when no higher hazard applies', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 7,
      ));

      expect(assessment.surfaceState, RoadSurfaceState.wet);
      expect(
        assessment.advisoryMessage,
        'Wet road — increased stopping distance',
      );
    });

    // S50-2 in-flight review: verify sub-model population in complex scenario
    test('complex scenario populates all sub-models correctly', () {
      final assessment = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -5,
        visibilityMeters: 200,
      ));

      expect(assessment.surfaceState, RoadSurfaceState.compactedSnow);
      expect(assessment.gripFactor, 0.3);
      expect(assessment.visibility.opacity, 0.8);
      expect(assessment.visibility.blurSigma, 6.0);
      expect(assessment.precipitation.particleCount, 500);
      expect(assessment.precipitation.minVelocity, 2.0);
      expect(assessment.precipitation.maxVelocity, 4.0);
    });

    test('assessment remains value-comparable for identical conditions', () {
      final a = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 7,
      ));
      final b = DrivingConditionAssessment.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 7,
      ));

      expect(a, equals(b));
      expect(
        a.props,
        [
          a.surfaceState,
          a.gripFactor,
          a.visibility,
          a.precipitation,
          a.advisoryMessage,
        ],
      );
    });
  });
}