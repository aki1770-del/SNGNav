// `driving_conditions` re-exports `RoadSurfaceState`, `HysteresisFilter` and
// `DrivingConditionAssessment` from `snow_rendering`. A facade is only as
// honest as what it re-exports — and a facade is exactly where a contract
// silently fails to arrive, because nothing here would fail to compile if the
// re-exported type quietly went back to being non-nullable.
//
// These tests pin the Measured-or-Absent contract AT THE FACADE: a consumer who
// only ever imports `package:driving_conditions` must get the same honesty as
// one who imports `package:snow_rendering` directly.

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';

final _t = DateTime.utc(2026, 1, 15, 6, 30);

void main() {
  group('the contract survives the re-export facade', () {
    test('unknown conditions → surface null, NOT dry', () {
      final surface = RoadSurfaceState.fromCondition(
        WeatherCondition.unknown(timestamp: _t),
      );
      expect(surface, isNull);
      expect(surface, isNot(RoadSurfaceState.dry));
    });

    test('unknown conditions → gripFactor null, NOT 1.0', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(timestamp: _t),
      );
      expect(a.gripFactor, isNull);
      expect(a.gripFactor, isNot(1.0));
    });

    test('unknown conditions → conditionsUnknown, never "Conditions normal"',
        () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition.unknown(timestamp: _t),
      );
      expect(a.recommendedResponse, RecommendedResponse.conditionsUnknown);
      expect(a.advisoryMessage, isNot(contains('Conditions normal')));
      expect(a.isAssessed, isFalse);
    });

    test('the SafetyScoreSimulator still demands a REAL grip factor', () {
      // This is the load-bearing seam of THIS package. `simulate` takes a
      // non-nullable `double gripFactor` — so an unknown surface cannot be
      // scored at all, and the caller is forced (at compile time) to handle it
      // rather than quietly scoring a road on a fabricated grip of 1.0.
      //
      // Here we assert the positive half: a MEASURED condition still scores.
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -5,
          visibilityMeters: 200,
          windSpeedKmh: 20,
          iceRisk: false,
          source: ObservationSource.measured,
          timestamp: _t,
        ),
      );

      final grip = a.gripFactor;
      final surface = a.surfaceState;
      expect(grip, isNotNull);
      expect(surface, isNotNull);

      final result = const SafetyScoreSimulator().simulate(
        speed: 50,
        gripFactor: grip!,
        surface: surface!,
        visibilityMeters: 200,
        seed: 42,
      );
      expect(result.score.overall, inInclusiveRange(0.0, 1.0));
    });

    test('measured-benign still proceeds — the facade does not cry wolf', () {
      final a = DrivingConditionAssessment.fromCondition(
        WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 5.0,
          visibilityMeters: 10000,
          windSpeedKmh: 0,
          iceRisk: false,
          source: ObservationSource.measured,
          timestamp: _t,
        ),
      );
      expect(a.recommendedResponse, RecommendedResponse.proceed);
      expect(a.gripFactor, 1.0);
    });
  });
}
