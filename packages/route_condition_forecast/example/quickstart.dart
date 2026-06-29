import 'package:latlong2/latlong.dart';
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
  final snow = WeatherCondition(precipType: PrecipitationType.snow, intensity: PrecipitationIntensity.heavy, temperatureCelsius: -4, visibilityMeters: 150, windSpeedKmh: 30, iceRisk: true, timestamp: DateTime.now());
  final forecaster = RouteConditionForecaster(forecastProvider: CurrentConditionsForecastProvider(snow), speedKmh: 50);
  final forecast = await forecaster.forecast(route);

  print('Route hazardous: ${forecast.hasAnyHazard}; first hazard ${forecast.firstHazardEtaSeconds?.round()}s in');
  for (final s in forecast.segments) {
    print('Seg ${s.segment.index}: arrives ${s.etaSeconds.round()}s, hazardous=${s.isHazardous}, conf=${s.confidence.toStringAsFixed(2)}');
  }
}
