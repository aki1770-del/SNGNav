import 'package:routing_engine/routing_engine.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';

Future<void> main() async {
  // A 2-leg route (your routing engine produces this RouteResult).
  final route = RouteResult(
    shape: const [LatLng(39.72, 140.10), LatLng(39.80, 140.30)],
    maneuvers: const [
      RouteManeuver(index: 0, instruction: 'Depart', type: 'depart', lengthKm: 12, timeSeconds: 720, position: LatLng(39.72, 140.10)),
      RouteManeuver(index: 1, instruction: 'Mountain pass', type: 'continue', lengthKm: 18, timeSeconds: 1080, position: LatLng(39.80, 140.30)),
    ],
    totalDistanceKm: 30, totalTimeSeconds: 1800, summary: 'Akita -> pass',
    engineInfo: const EngineInfo(name: 'mock'),
  );
  // Heavy snow + ice = hazardous; projected onto each segment at its arrival time.
  final snow = WeatherCondition(precipType: PrecipitationType.snow, intensity: PrecipitationIntensity.heavy, temperatureCelsius: -4, visibilityMeters: 150, windSpeedKmh: 30, iceRisk: true, source: ObservationSource.measured, timestamp: DateTime.now());
  final forecaster = RouteConditionForecaster(forecastProvider: CurrentConditionsForecastProvider(snow), speedKmh: 50);
  final forecast = await forecaster.forecast(route);

  // `hazard` is TRI-STATE (SafetyVerdict). Do NOT write
  // `if (forecast.hazard == SafetyVerdict.hazardous) warn(); else allClear();`
  // — that puts `unknown` in the "all clear" branch, which is the defect this
  // release removed. Handle all three, and let the compiler check that you did.
  switch (forecast.hazard) {
    case SafetyVerdict.hazardous:
      print(
        'Route HAZARDOUS; first hazard '
        '${forecast.firstHazardEtaSeconds?.round()}s in',
      );
    case SafetyVerdict.notHazardous:
      print('Route assessed and clear.');
    case SafetyVerdict.unknown:
      // NOT a green light. We could not assess the route — say so.
      print(
        'Route could NOT be assessed '
        '(${forecast.unassessedSegmentCount} unassessed segment(s), '
        '${forecast.unlocatableManeuverCount} unlocatable maneuver(s)). '
        'Drive to what you can see.',
      );
  }

  for (final s in forecast.segments) {
    print(
      'Seg ${s.segment.index}: arrives ${s.etaSeconds.round()}s, '
      'hazard=${s.hazard.name}, conf=${s.confidence.toStringAsFixed(2)}',
    );
  }
}
