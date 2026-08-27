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

  // --- CPU path: no fleet source wired at all ---
  // The default provider is ConstantFleetConfidenceProvider.unavailable(), so
  // fleetConfidenceScore is null and the grip/visibility weights are
  // re-normalised over what was actually measured. Up to 0.6.0 this default
  // was 0.8, and this run silently reported a fleet that never spoke.
  final noFleetResult = const SafetyScoreSimulator().simulate(
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
      // ASSERTED observation confidence — this is a scenario we are declaring,
      // not a measurement. Required since fleet_hazard 0.6.0, which removed
      // its own defaulted 0.8 for the same reason this package removed its.
      confidence: 0.9,
    ),
    FleetReport(
      vehicleId: 'v2',
      position: const LatLng(35.1, 136.9),
      timestamp: DateTime.now(),
      condition: RoadCondition.snowy,
      confidence: 0.9,
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
  print('--- no fleet source wired (the default) ---');
  final noFleet = noFleetResult.score.fleetConfidenceScore;
  print(
    'fleet confidence: '
    '${noFleet == null ? 'no fleet data' : noFleet.toStringAsFixed(2)}',
  );
  print('hasFleetData:     ${noFleetResult.score.hasFleetData}');
  print('overall safety:   ${noFleetResult.score.overall.toStringAsFixed(2)}');
  print('incident count:   ${noFleetResult.incidentCount}');
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
