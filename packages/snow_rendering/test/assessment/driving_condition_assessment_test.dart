import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

WeatherCondition _condition({
  PrecipitationType precipType = PrecipitationType.none,
  PrecipitationIntensity intensity = PrecipitationIntensity.none,
  double temperatureCelsius = 5.0,
  double visibilityMeters = 10000,
  bool iceRisk = false,
  double? humidityRH,
}) => WeatherCondition(
  precipType: precipType,
  intensity: intensity,
  temperatureCelsius: temperatureCelsius,
  visibilityMeters: visibilityMeters,
  windSpeedKmh: 0,
  iceRisk: iceRisk,
  humidityRH: humidityRH,
  source: ObservationSource.measured,
  timestamp: DateTime(2026),
);

void main() {
  group('DrivingConditionAssessment.fromCondition', () {
    test('clear warm → dry surface, gripFactor 1.0', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.surfaceState, RoadSurfaceState.dry);
      expect(a.gripFactor, 1.0);
    });

    test('radiative frost (+2C/70%RH no precip) → the assessment carries the black-ice advisory', () {
      // UNIT scope: proves that when the classifier returns blackIce for the
      // radiative-frost window, the assessment text is the black-ice advisory.
      // This is NOT end-to-end: it does not prove the fix reaches HER's live
      // screen — the live feeds (digitraffic, KUKSA) do not yet supply
      // humidityRH, so on those feeds the classifier abstains. See
      // KNOWN_LIMITATIONS.md (reach gap).
      final a = DrivingConditionAssessment.fromCondition(
        _condition(temperatureCelsius: 2.0, humidityRH: 70.0),
      );
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.gripFactor, 0.15);
      expect(a.advisoryMessage, contains('Black ice risk'));
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test('same conditions without humidity → "not measured", NOT "Conditions '
        'normal" (an abstention is not an all-clear)', () {
      // Without the humidity feed the classifier cannot see the frost and must
      // not pretend to — absence is never a fabricated warning. It is not a
      // fabricated CLEARANCE either: this used to read "Conditions normal", so
      // the same road at the same temperature said "Black ice risk" to a feed
      // with a hygrometer and "Conditions normal" to a feed without one. The
      // driver is told what is actually true — that nobody measured it.
      final a = DrivingConditionAssessment.fromCondition(
        _condition(temperatureCelsius: 2.0),
      );
      expect(a.surfaceState, isNull);
      expect(a.gripFactor, isNull);
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.advisoryMessage,
          'Road surface not measured here — drive to what you can see');
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
        expect(
          a.gripFactor,
          a.surfaceState!.gripFactor,
          reason: 'gripFactor mismatch for ${a.surfaceState}',
        );
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
      expect(a.visibility!.opacity, closeTo(0.9, 0.001));
      expect(a.visibility!.blurSigma, closeTo(8.0, 0.001));
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
      final a = DrivingConditionAssessment.fromCondition(
        _condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -5,
        ),
      );
      expect(a.advisoryMessage, contains('Compacted snow'));
    });

    test('slush → advisory contains "Slushy"', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(
          precipType: PrecipitationType.sleet,
          intensity: PrecipitationIntensity.moderate,
        ),
      );
      expect(a.advisoryMessage, contains('Slushy'));
    });

    test('standingWater → advisory contains "Standing water"', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 10,
        ),
      );
      expect(a.advisoryMessage, contains('Standing water'));
    });

    test('wet → advisory contains "Wet road"', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 10,
        ),
      );
      expect(a.advisoryMessage, contains('Wet road'));
    });

    test('dry clear conditions → "Conditions normal"', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.advisoryMessage, 'Conditions normal');
    });

    test('mildly reduced visibility (500 m) on dry road → fog advisory', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 500),
      );
      expect(a.advisoryMessage, contains('fog lights'));
    });

    test(
      'near-whiteout band (150 m) → arrow-test whiteout cue, still reduceSpeed',
      () {
        final a = DrivingConditionAssessment.fromCondition(
          _condition(visibilityMeters: 150),
        );
        // The negative-evidence cue from DRIVER_VOICES.md: tell the driver
        // WHAT to look for, not just that visibility is reduced.
        expect(a.advisoryMessage, contains('arrow'));
        expect(a.advisoryMessage, contains('whiteout'));
        expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      },
    );

    test('band boundaries: 100 m gets the cue, 200 m does not', () {
      final atLowEdge = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 100),
      );
      expect(atLowEdge.advisoryMessage, contains('arrow'));
      expect(atLowEdge.recommendedResponse, RecommendedResponse.reduceSpeed);

      final atHighEdge = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 200),
      );
      expect(atHighEdge.advisoryMessage, contains('fog lights'));
    });

    test('black ice at 120 m visibility keeps the black-ice advisory', () {
      // Surface-hazard advisories keep precedence over the visibility cue:
      // at 120 m the dominant hazard on a still-visible road is the surface.
      final a = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 120, iceRisk: true),
      );
      expect(a.advisoryMessage, contains('Black ice'));
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test('snow heavy warm → precipitation config non-zero', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: 5,
        ),
      );
      expect(a.precipitation!.particleCount, greaterThan(0));
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

  group('RecommendedResponse — trip-abandonment as a first-class response', () {
    test('whiteout-class visibility (<100m) → considerTurningBack', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 50),
      );
      expect(a.recommendedResponse, RecommendedResponse.considerTurningBack);
      expect(a.advisoryMessage, contains('turning back'));
    });

    test('whiteout visibility triggers turn-back regardless of surface', () {
      // Heavy snow, sub-zero, near-zero visibility (80 m) → can't see → turn
      // back, whatever the grip.
      final a = DrivingConditionAssessment.fromCondition(
        _condition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -5,
          visibilityMeters: 80,
        ),
      );
      expect(a.recommendedResponse, RecommendedResponse.considerTurningBack);
    });

    test('black ice on a CLEAR road stays reduceSpeed, not turn-back', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(iceRisk: true, visibilityMeters: 10000),
      );
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
      expect(a.advisoryMessage, contains('Black ice'));
    });

    test('black ice while STILL visible (150m) stays reduceSpeed, not turn-back',
        () {
      // Low grip but the road is still visible — slow down hard, do not cry
      // wolf with a turn-back. The boundary is visibility, not grip.
      final a = DrivingConditionAssessment.fromCondition(
        _condition(iceRisk: true, visibilityMeters: 150),
      );
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test('reduced visibility (500m) on dry road → reduceSpeed', () {
      final a = DrivingConditionAssessment.fromCondition(
        _condition(visibilityMeters: 500),
      );
      expect(a.recommendedResponse, RecommendedResponse.reduceSpeed);
    });

    test('clear dry conditions → proceed', () {
      final a = DrivingConditionAssessment.fromCondition(_condition());
      expect(a.recommendedResponse, RecommendedResponse.proceed);
    });
  });
}
