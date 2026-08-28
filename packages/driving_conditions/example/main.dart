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

  // --- The safety score: grip and visibility, 0.5/0.5, always ---
  // 0.7.0 removed the fleet term from the composite and with it the
  // `provider:` parameter. The weights are stated in SimulatedSafetyScore and
  // are never re-normalised, so `overall` means the same thing on every run.
  final result = const SafetyScoreSimulator().simulate(
    speed: 50,
    gripFactor: grip,
    surface: surface,
    visibilityMeters: visibility,
    seed: 42,
  );

  // --- Fleet telemetry, read SEPARATELY and on its own terms ---
  // The adapter is still here and still supported. It is simply not laundered
  // into the safety score above, because the fleet term never carried a real
  // reading: see SimulatedSafetyScore for the four defects that came of
  // pretending otherwise.
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

  final fleet = FleetHazardConfidenceAdapter(icyReports).confidence;
  final noFleet = const FleetHazardConfidenceAdapter([]).confidence;

  print('surfaceState: ${surface.name}');
  print('advisory:     ${assessment.advisoryMessage}');
  print('');
  print('--- safety score (grip 0.5 + visibility 0.5) ---');
  print('grip:             ${result.score.gripScore.toStringAsFixed(2)}');
  print('visibility:       ${result.score.visibilityScore.toStringAsFixed(2)}');
  print('overall safety:   ${result.score.overall.toStringAsFixed(2)}');
  print('incident count:   ${result.incidentCount}');
  print('');
  print('--- fleet telemetry, read separately (NOT in the score) ---');
  print(
    'icy + snowy reports: '
    '${fleet == null ? 'no fleet data' : fleet.toStringAsFixed(2)}',
  );
  print(
    'no reports at all:   '
    '${noFleet == null ? 'no fleet data' : noFleet.toStringAsFixed(2)}',
  );
}
