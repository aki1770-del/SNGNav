// Minimal example for snow_rendering.
//
// Demonstrates DrivingConditionAssessment.fromCondition() — converts a
// driving_weather WeatherCondition into the full driving condition
// picture (road surface state, precipitation params, visibility).

import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';

void main() {
  final condition = WeatherCondition(
    precipType: PrecipitationType.snow,
    intensity: PrecipitationIntensity.heavy,
    temperatureCelsius: -2.0,
    visibilityMeters: 800.0,
    windSpeedKmh: 15.0,
    source: ObservationSource.measured,
    timestamp: DateTime.now(),
  );
  final assessment = DrivingConditionAssessment.fromCondition(condition);
  print('Surface: ${assessment.surfaceState?.name ?? "unknown"}');
  print('Particle count: ${assessment.precipitation?.particleCount ?? "unknown"}');
  print('Visibility blur: ${assessment.visibility?.blurSigma ?? "unknown"}');
}
