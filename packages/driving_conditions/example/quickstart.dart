import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';

void main() {
  // Heavy snow, -4°C, 180m visibility — what is the road doing?
  final condition = WeatherCondition(
    precipType: PrecipitationType.snow,
    intensity: PrecipitationIntensity.heavy,
    temperatureCelsius: -4,
    visibilityMeters: 180,
    windSpeedKmh: 25,
    iceRisk: false,
    timestamp: DateTime.now(),
  );

  final a = DrivingConditionAssessment.fromCondition(condition);
  final result = const SafetyScoreSimulator().simulate(
    speed: 50,
    gripFactor: a.gripFactor,
    surface: a.surfaceState,
    visibilityMeters: condition.visibilityMeters,
    seed: 42, // deterministic
  );

  print('surface : ${a.surfaceState.name}');             // compactedSnow
  print('grip    : ${a.gripFactor.toStringAsFixed(2)}'); // 0.30
  print('advisory: ${a.advisoryMessage}');
  print('safety  : ${result.score.overall.toStringAsFixed(2)} (0=stop, 1=clear)');
}
