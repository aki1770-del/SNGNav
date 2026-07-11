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
    source: ObservationSource.measured,
    timestamp: DateTime.now(),
  );

  final a = DrivingConditionAssessment.fromCondition(condition);

  // THE GUARD (0.6.0 / snow_rendering 0.3.0 — the Measured-or-Absent contract).
  //
  // `surfaceState` and `gripFactor` are nullable, because the weather feed may
  // not have told us anything. `null` means NOT MEASURED — it never means "dry"
  // and never means "full grip".
  //
  // Do NOT write `?? RoadSurfaceState.dry` or `?? 1.0` here. That re-adds the
  // exact defect this release removed: up to 0.5.4 an unmeasured road came back
  // as `dry` with `gripFactor: 1.0` and the advisory "Conditions normal" — a
  // green light for a road nobody had looked at.
  final surface = a.surfaceState;
  final grip = a.gripFactor;
  final visibility = condition.visibilityMeters;

  if (surface == null || grip == null || visibility == null) {
    // You cannot simulate a safety score for a road you have no data for.
    // Saying so IS the useful thing to tell the driver.
    print('surface : unknown (no data received)');
    print('advisory: ${a.advisoryMessage}');
    // -> "Conditions unavailable — no data received; drive to what you can see"
    return;
  }

  final result = const SafetyScoreSimulator().simulate(
    speed: 50,
    gripFactor: grip,
    surface: surface,
    visibilityMeters: visibility,
    seed: 42, // deterministic
  );

  print('surface : ${surface.name}'); // compactedSnow
  print('grip    : ${grip.toStringAsFixed(2)}'); // 0.30
  print('advisory: ${a.advisoryMessage}');
  print(
    'safety  : ${result.score.overall.toStringAsFixed(2)} (0=stop, 1=clear)',
  );
}
