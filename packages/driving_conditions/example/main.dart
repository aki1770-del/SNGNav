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
    source: ObservationSource.measured,
    timestamp: DateTime.now(),
  );

  final assessment = DrivingConditionAssessment.fromCondition(condition);

  // THE GUARD (see quickstart.dart). `null` means NOT MEASURED. A safety score
  // cannot be simulated for a road we have no data for, and substituting a
  // grip factor of 1.0 to make the call compile would fabricate exactly the
  // reassurance this contract exists to refuse.
  final surface = assessment.surfaceState;
  final grip = assessment.gripFactor;
  final visibility = condition.visibilityMeters;

  if (surface == null || grip == null || visibility == null) {
    print('surfaceState: unknown (no data received)');
    print('advisory:     ${assessment.advisoryMessage}');
    return;
  }

  // --- CPU path: constant provider (default 0.8 baseline) ---
  final defaultResult = const SafetyScoreSimulator().simulate(
    speed: 50,
    gripFactor: grip,
    surface: surface,
    visibilityMeters: visibility,
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
    gripFactor: grip,
    surface: surface,
    visibilityMeters: visibility,
    seed: 42,
  );

  print('surfaceState: ${surface.name}');
  print('advisory:     ${assessment.advisoryMessage}');
  print('');
  print('--- default (constant 0.8 — an ASSERTED value, not a measurement) ---');
  final defaultFleet = defaultResult.score.fleetConfidenceScore;
  print(
    'fleet confidence: '
    '${defaultFleet == null ? 'no fleet data' : defaultFleet.toStringAsFixed(2)}',
  );
  print('overall safety:   ${defaultResult.score.overall.toStringAsFixed(2)}');
  print('incident count:   ${defaultResult.incidentCount}');
  print('');
  print('--- fleet adapter (icy + snowy reports) ---');
  final fleet = fleetResult.score.fleetConfidenceScore;
  print(
    'fleet confidence: '
    '${fleet == null ? 'no fleet data' : fleet.toStringAsFixed(2)}',
  );
  print('overall safety:   ${fleetResult.score.overall.toStringAsFixed(2)}');
  print('incident count:   ${fleetResult.incidentCount}');
}
