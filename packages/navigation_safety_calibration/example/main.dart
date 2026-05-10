// Minimal example for navigation_safety_calibration.
//
// Demonstrates the three calibration primitives the package re-exports:
// surface-moisture decay after precipitation, dew-point / effective
// temperature via Magnus formula, and speed-adjusted visibility.

import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';

void main() {
  final moisture = computeSurfaceMoistureFraction(
    timeSincePrecipitation: const Duration(minutes: 30),
    ambientCelsius: 1.0,
  );
  print('Surface moisture after 30 min @ 1°C: ${moisture.toStringAsFixed(3)}');

  final effectiveTemp = computeEffectiveTemperatureCelsius(
    ambientCelsius: 1.0,
    humidityRH: 0.92,
  );
  print(
    'Effective temperature @ 1°C / 92% RH: '
    '${effectiveTemp.toStringAsFixed(1)} °C',
  );

  final visibility = computeSpeedAdjustedVisibilityMeters(
    profileBaseMeters: 200.0,
    speedMps: 22.2,
    driverReactionTimeSeconds: 1.5,
  );
  print(
    'Speed-adjusted visibility @ 80 km/h: '
    '${visibility.toStringAsFixed(0)} m',
  );
}
