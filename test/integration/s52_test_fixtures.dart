library;

import 'package:driving_weather/driving_weather.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';

class S52TestFixtures {
  static const int safetySeed = 42;
  static const int transitionSeed = 101;
  static const int recoverySeed = 202;

  static final DateTime timestamp = DateTime.utc(2026, 3, 11, 6, 0, 0);

  static const LatLng sakae = LatLng(35.1709, 136.9066);
  static const LatLng nagoya = LatLng(35.1709, 136.8815);
  static const LatLng toyota = LatLng(35.0504, 137.1566);
  static const LatLng inuyama = LatLng(35.3883, 136.9394);
  static const LatLng higashiokazaki = LatLng(34.9554, 137.1791);

  static const RouteRequest nagoyaToOkazakiRequest = RouteRequest(
    origin: nagoya,
    destination: higashiokazaki,
  );

  static const RouteResult nagoyaToOkazakiRoute = RouteResult(
    shape: [nagoya, higashiokazaki],
    maneuvers: [
      RouteManeuver(
        index: 0,
        instruction: 'Head east on Route 153',
        type: 'depart',
        lengthKm: 25.7,
        timeSeconds: 1200,
        position: nagoya,
      ),
      RouteManeuver(
        index: 1,
        instruction: 'Arrive at Higashiokazaki',
        type: 'arrive',
        lengthKm: 0,
        timeSeconds: 0,
        position: higashiokazaki,
      ),
    ],
    totalDistanceKm: 25.7,
    totalTimeSeconds: 1200,
    summary: 'Route 153, 25.7 km',
    engineInfo: EngineInfo(name: 'mock-s52'),
  );

  static const RouteRequest nagoyaToInuyamaRequest = RouteRequest(
    origin: nagoya,
    destination: inuyama,
  );

  static const RouteResult nagoyaToInuyamaRoute = RouteResult(
    shape: [nagoya, inuyama],
    maneuvers: [
      RouteManeuver(
        index: 0,
        instruction: 'Head north on Route 41',
        type: 'depart',
        lengthKm: 18.0,
        timeSeconds: 1200,
        position: nagoya,
      ),
      RouteManeuver(
        index: 1,
        instruction: 'Arrive at Inuyama Castle',
        type: 'arrive',
        lengthKm: 0,
        timeSeconds: 0,
        position: inuyama,
      ),
    ],
    totalDistanceKm: 18.0,
    totalTimeSeconds: 1200,
    summary: 'Route 41, 18.0 km',
    engineInfo: EngineInfo(name: 'mock-s52'),
  );

  static final WeatherCondition clearWeather = WeatherCondition.clear(
    timestamp: timestamp,
  );

  static final WeatherCondition lightRainWeather = WeatherCondition(
    precipType: PrecipitationType.rain,
    intensity: PrecipitationIntensity.light,
    temperatureCelsius: 7.0,
    visibilityMeters: 2200,
    windSpeedKmh: 12,
    timestamp: timestamp,
  );

  static final WeatherCondition moderateSnowWeather = WeatherCondition(
    precipType: PrecipitationType.snow,
    intensity: PrecipitationIntensity.moderate,
    temperatureCelsius: -2.0,
    visibilityMeters: 700,
    windSpeedKmh: 20,
    timestamp: timestamp,
  );

  static final WeatherCondition blackIceWeather = WeatherCondition(
    precipType: PrecipitationType.none,
    intensity: PrecipitationIntensity.none,
    temperatureCelsius: -5.0,
    visibilityMeters: 120,
    windSpeedKmh: 8,
    iceRisk: true,
    timestamp: timestamp,
  );

  static final List<WeatherCondition> clearToSnowTransition = [
    clearWeather,
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.light,
      temperatureCelsius: 1.0,
      visibilityMeters: 2500,
      windSpeedKmh: 10,
      timestamp: timestamp,
    ),
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -5.0,
      visibilityMeters: 300,
      windSpeedKmh: 28,
      timestamp: timestamp,
    ),
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -5.0,
      visibilityMeters: 250,
      windSpeedKmh: 30,
      timestamp: timestamp,
    ),
  ];

  static final GeoPosition gpsFix = GeoPosition(
    latitude: 35.1709,
    longitude: 136.8815,
    accuracy: 5.0,
    speed: 13.89,
    heading: 0.0,
    timestamp: timestamp,
  );

  static final GeoPosition gpsFixUpdated = GeoPosition(
    latitude: 35.1720,
    longitude: 136.8815,
    accuracy: 3.0,
    speed: 16.67,
    heading: 20.0,
    timestamp: timestamp.add(const Duration(seconds: 5)),
  );

  static final GeoPosition gpsFixNoSpeed = GeoPosition(
    latitude: 35.1709,
    longitude: 136.8815,
    accuracy: 5.0,
    timestamp: timestamp,
  );

  const S52TestFixtures._();
}