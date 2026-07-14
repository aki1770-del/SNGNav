import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';

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

  // --- CPU path: constant provider (default 0.8 baseline) ---
  final defaultResult = const SafetyScoreSimulator().simulate(
    speed: 50,
    gripFactor: assessment.gripFactor,
    surface: assessment.surfaceState,
    visibilityMeters: condition.visibilityMeters,
    seed: 42,
  );

  // --- CPU path: fleet adapter (icy reports reduce confidence) ---
  final icyReports = [
    FleetReport(
      vehicleId: 'v1',
      position: const LatLng(35.1, 136.9),
      timestamp: DateTime.now(),
      condition: RoadCondition.icy,
    ),
    FleetReport(
      vehicleId: 'v2',
      position: const LatLng(35.1, 136.9),
      timestamp: DateTime.now(),
      condition: RoadCondition.snowy,
    ),
  ];

  final fleetResult = SafetyScoreSimulator(
    provider: FleetHazardConfidenceAdapter(icyReports),
  ).simulate(
    speed: 50,
    gripFactor: assessment.gripFactor,
    surface: assessment.surfaceState,
    visibilityMeters: condition.visibilityMeters,
    seed: 42,
  );

  print('surfaceState: ${assessment.surfaceState.name}');
  print('advisory:     ${assessment.advisoryMessage}');
  print('');
  print('--- default (constant 0.8) ---');
  print('fleet confidence: ${defaultResult.score.fleetConfidenceScore.toStringAsFixed(2)}');
  print('overall safety:   ${defaultResult.score.overall.toStringAsFixed(2)}');
  print('incident count:   ${defaultResult.incidentCount}');
  print('');
  print('--- fleet adapter (icy + snowy reports) ---');
  print('fleet confidence: ${fleetResult.score.fleetConfidenceScore.toStringAsFixed(2)}');
  print('overall safety:   ${fleetResult.score.overall.toStringAsFixed(2)}');
  print('incident count:   ${fleetResult.incidentCount}');
}
