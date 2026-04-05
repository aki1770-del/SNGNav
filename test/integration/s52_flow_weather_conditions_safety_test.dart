library;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

import 's52_test_fixtures.dart';

DrivingConditionAssessment _assessment(WeatherCondition condition) {
  return DrivingConditionAssessment.fromCondition(condition);
}

SimulationResult _scoreFor(
  WeatherCondition condition, {
  required int seed,
  int runs = 200,
  double speed = 60,
}) {
  final assessment = _assessment(condition);
  const simulator = SafetyScoreSimulator();

  return simulator.simulate(
    runs: runs,
    speed: speed,
    gripFactor: assessment.gripFactor,
    surface: assessment.surfaceState,
    visibilityMeters: condition.visibilityMeters,
    seed: seed,
  );
}

void main() {
  group('S52 Flow 1: weather -> conditions -> safety', () {
    test('shared fixtures cover clear, rain, snow, and black ice scenarios', () {
      expect(S52TestFixtures.clearWeather.precipType, PrecipitationType.none);
      expect(
        S52TestFixtures.lightRainWeather.precipType,
        PrecipitationType.rain,
      );
      expect(
        S52TestFixtures.moderateSnowWeather.precipType,
        PrecipitationType.snow,
      );
      expect(S52TestFixtures.blackIceWeather.iceRisk, isTrue);
    });

    test('weather conditions map to the expected driving assessments', () {
      final clearAssessment = _assessment(S52TestFixtures.clearWeather);
      final rainAssessment = _assessment(S52TestFixtures.lightRainWeather);
      final snowAssessment = _assessment(S52TestFixtures.moderateSnowWeather);
      final blackIceAssessment = _assessment(S52TestFixtures.blackIceWeather);

      expect(clearAssessment.surfaceState, RoadSurfaceState.dry);
      expect(clearAssessment.advisoryMessage, 'Conditions normal');

      expect(rainAssessment.surfaceState, RoadSurfaceState.wet);
      expect(
        rainAssessment.advisoryMessage,
        'Wet road — increased stopping distance',
      );

      expect(snowAssessment.surfaceState, RoadSurfaceState.slush);
      expect(
        snowAssessment.advisoryMessage,
        'Slushy conditions — maintain safe following distance',
      );

      expect(blackIceAssessment.surfaceState, RoadSurfaceState.blackIce);
      expect(
        blackIceAssessment.advisoryMessage,
        'Black ice risk — reduce speed significantly',
      );
    });

    test('deterministic safety scoring degrades across worsening conditions', () {
      final config = NavigationSafetyConfig();

      final clearScore = _scoreFor(
        S52TestFixtures.clearWeather,
        seed: S52TestFixtures.safetySeed,
      );
      final rainScore = _scoreFor(
        S52TestFixtures.lightRainWeather,
        seed: S52TestFixtures.safetySeed,
      );
      final snowScore = _scoreFor(
        S52TestFixtures.moderateSnowWeather,
        seed: S52TestFixtures.safetySeed,
      );
      final blackIceScore = _scoreFor(
        S52TestFixtures.blackIceWeather,
        seed: S52TestFixtures.safetySeed,
        speed: 70,
      );

      expect(
        _scoreFor(
          S52TestFixtures.clearWeather,
          seed: S52TestFixtures.safetySeed,
        ),
        equals(clearScore),
      );

      expect(rainScore.score.overall, lessThan(clearScore.score.overall));
      expect(snowScore.score.overall, lessThan(rainScore.score.overall));
      expect(blackIceScore.score.overall, lessThan(snowScore.score.overall));

      expect(clearScore.score.toAlertSeverity(config), isNull);
      expect(snowScore.score.toAlertSeverity(config), isNotNull);
      expect(blackIceScore.score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('hysteresis prevents immediate clear-to-snow oscillation', () {
      final filter = HysteresisFilter<RoadSurfaceState>();
      final states = S52TestFixtures.clearToSnowTransition
          .map(RoadSurfaceState.fromCondition)
          .toList();

      final outputs = states.map(filter.update).toList();

      expect(states, [
        RoadSurfaceState.dry,
        RoadSurfaceState.slush,
        RoadSurfaceState.compactedSnow,
        RoadSurfaceState.compactedSnow,
      ]);

      expect(outputs, [
        RoadSurfaceState.dry,
        RoadSurfaceState.dry,
        RoadSurfaceState.dry,
        RoadSurfaceState.compactedSnow,
      ]);
    });
  });
}