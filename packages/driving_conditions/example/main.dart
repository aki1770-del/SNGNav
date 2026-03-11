import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';

void main() {
  final condition = WeatherCondition(
    precipType: PrecipitationType.snow,
    intensity: PrecipitationIntensity.heavy,
    temperatureCelsius: -4,
    visibilityMeters: 180,
    windSpeedKmh: 20,
    iceRisk: false,
    timestamp: DateTime.now(),
  );

  final assessment = DrivingConditionAssessment.fromCondition(condition);

  final score = const SafetyScoreSimulator().simulate(
    speed: 50,
    gripFactor: assessment.gripFactor,
    surface: assessment.surfaceState,
    visibilityMeters: condition.visibilityMeters,
    seed: 42,
  );

  print('surfaceState: ${assessment.surfaceState.name}');
  print('gripFactor: ${assessment.gripFactor.toStringAsFixed(2)}');
  print('advisory: ${assessment.advisoryMessage}');
  print('visibility opacity: ${assessment.visibility.opacity.toStringAsFixed(2)}');
  print('simulated overall safety: ${score.overall.toStringAsFixed(2)}');
}