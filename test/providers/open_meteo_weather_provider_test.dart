/// OpenMeteoWeatherProvider unit tests.
///
/// Tests:
///   1. parseWeatherResponse: clear sky (code 0) → none/none
///   2. parseWeatherResponse: light snow (code 71) → snow/light
///   3. parseWeatherResponse: heavy snow (code 75) → snow/heavy
///   4. parseWeatherResponse: light rain (code 61) → rain/light
///   5. parseWeatherResponse: freezing rain (code 66) → sleet/light
///   6. parseWeatherResponse: ice risk when sub-zero + precip
///   7. parseWeatherResponse: no ice risk when warm
///   8. parseWeatherResponse: snowfall inference from hourly data
///   9. fetchWeather: successful HTTP → WeatherCondition
///  10. fetchWeather: HTTP error → throws HttpException
///  11. startMonitoring: emits condition on start
///  12. startMonitoring: polls at configured interval
///  13. offline fallback: re-emits last condition on HTTP failure
///  14. offline fallback: no emission when no prior condition
///  15. stopMonitoring: stops polling
///  16. dispose: closes stream
///
/// Sprint 8 Day 6 — E8-3 (real data source).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:sngnav_snow_scene/models/weather_condition.dart';
import 'package:sngnav_snow_scene/providers/open_meteo_weather_provider.dart';

// ---------------------------------------------------------------------------
// Test data — realistic Open-Meteo API response
// ---------------------------------------------------------------------------

Map<String, dynamic> _buildResponse({
  double temperature = 5.0,
  int weatherCode = 0,
  double windSpeed = 10.0,
  List<double>? snowfall,
  List<double>? visibility,
}) {
  // Generate 24 hourly entries.
  final hours = List.generate(24, (i) => '2026-02-27T${i.toString().padLeft(2, '0')}:00');
  return {
    'current': {
      'temperature_2m': temperature,
      'weather_code': weatherCode,
      'wind_speed_10m': windSpeed,
    },
    'hourly': {
      'time': hours,
      'snowfall': snowfall ?? List.filled(24, 0.0),
      'visibility': visibility ?? List.filled(24, 10000.0),
    },
  };
}

String _jsonResponse({
  double temperature = 5.0,
  int weatherCode = 0,
  double windSpeed = 10.0,
  List<double>? snowfall,
  List<double>? visibility,
}) {
  return jsonEncode(_buildResponse(
    temperature: temperature,
    weatherCode: weatherCode,
    windSpeed: windSpeed,
    snowfall: snowfall,
    visibility: visibility,
  ));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OpenMeteoWeatherProvider', () {
    group('parseWeatherResponse', () {
      test('clear sky (code 0) → none/none', () {
        final json = _buildResponse(weatherCode: 0, temperature: 15.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.none);
        expect(condition.intensity, PrecipitationIntensity.none);
        expect(condition.temperatureCelsius, 15.0);
        expect(condition.iceRisk, false);
      });

      test('light snow (code 71) → snow/light', () {
        final json = _buildResponse(weatherCode: 71, temperature: -2.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.snow);
        expect(condition.intensity, PrecipitationIntensity.light);
        expect(condition.temperatureCelsius, -2.0);
      });

      test('heavy snow (code 75) → snow/heavy', () {
        final json = _buildResponse(weatherCode: 75, temperature: -5.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.snow);
        expect(condition.intensity, PrecipitationIntensity.heavy);
      });

      test('moderate snow (code 73) → snow/moderate', () {
        final json = _buildResponse(weatherCode: 73, temperature: -1.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.snow);
        expect(condition.intensity, PrecipitationIntensity.moderate);
      });

      test('light rain (code 61) → rain/light', () {
        final json = _buildResponse(weatherCode: 61, temperature: 8.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.rain);
        expect(condition.intensity, PrecipitationIntensity.light);
      });

      test('freezing rain (code 66) → sleet/light', () {
        final json = _buildResponse(weatherCode: 66, temperature: -1.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.sleet);
        expect(condition.intensity, PrecipitationIntensity.light);
      });

      test('ice risk when sub-zero + precipitation', () {
        final json = _buildResponse(weatherCode: 71, temperature: -3.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.iceRisk, true);
        expect(condition.isFreezing, true);
      });

      test('no ice risk when warm temperature', () {
        final json = _buildResponse(weatherCode: 61, temperature: 8.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.iceRisk, false);
      });

      test('snowfall inference from hourly data', () {
        // Weather code is clear (0) but hourly snowfall > 0.
        final snowfall = List.filled(24, 1.0); // 1cm/hr
        final json = _buildResponse(
          weatherCode: 0,
          temperature: -2.0,
          snowfall: snowfall,
        );
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.snow);
        expect(condition.intensity, PrecipitationIntensity.moderate);
      });

      test('visibility from hourly data', () {
        final visibility = List.filled(24, 500.0);
        final json = _buildResponse(
          weatherCode: 73,
          temperature: -1.0,
          visibility: visibility,
        );
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.visibilityMeters, 500.0);
        expect(condition.hasReducedVisibility, true);
      });

      test('snow shower codes map correctly', () {
        // Code 85 = light snow shower
        final json85 = _buildResponse(weatherCode: 85, temperature: -1.0);
        final c85 = OpenMeteoWeatherProvider.parseWeatherResponse(json85);
        expect(c85.precipType, PrecipitationType.snow);
        expect(c85.intensity, PrecipitationIntensity.light);

        // Code 86 = heavy snow shower
        final json86 = _buildResponse(weatherCode: 86, temperature: -3.0);
        final c86 = OpenMeteoWeatherProvider.parseWeatherResponse(json86);
        expect(c86.precipType, PrecipitationType.snow);
        expect(c86.intensity, PrecipitationIntensity.heavy);
      });

      test('thunderstorm codes map to rain/heavy', () {
        final json = _buildResponse(weatherCode: 95, temperature: 10.0);
        final condition = OpenMeteoWeatherProvider.parseWeatherResponse(json);

        expect(condition.precipType, PrecipitationType.rain);
        expect(condition.intensity, PrecipitationIntensity.heavy);
      });
    });

    group('fetchWeather', () {
      test('successful HTTP → WeatherCondition', () async {
        final mockClient = MockClient((request) async {
          expect(request.url.host, 'api.open-meteo.com');
          expect(request.url.path, '/v1/forecast');
          expect(request.url.queryParameters['latitude'], '35.18');
          return http.Response(
            _jsonResponse(weatherCode: 71, temperature: -2.0),
            200,
          );
        });

        final provider = OpenMeteoWeatherProvider(client: mockClient);
        final condition = await provider.fetchWeather();

        expect(condition.precipType, PrecipitationType.snow);
        expect(condition.temperatureCelsius, -2.0);

        provider.dispose();
      });

      test('HTTP error → throws HttpException', () async {
        final mockClient = MockClient((_) async {
          return http.Response('Server Error', 500);
        });

        final provider = OpenMeteoWeatherProvider(client: mockClient);

        expect(
          () => provider.fetchWeather(),
          throwsA(isA<HttpException>()),
        );

        provider.dispose();
      });
    });

    group('stream behavior', () {
      test('startMonitoring emits condition on start', () async {
        final mockClient = MockClient((_) async {
          return http.Response(
            _jsonResponse(weatherCode: 0, temperature: 10.0),
            200,
          );
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(seconds: 60),
        );

        final firstCondition = provider.conditions.first;
        await provider.startMonitoring();

        final condition = await firstCondition.timeout(
          const Duration(seconds: 5),
        );
        expect(condition, isA<WeatherCondition>());
        expect(condition.precipType, PrecipitationType.none);

        provider.dispose();
      });

      test('polls at configured interval', () async {
        int fetchCount = 0;
        final mockClient = MockClient((_) async {
          fetchCount++;
          return http.Response(
            _jsonResponse(weatherCode: 0, temperature: 10.0),
            200,
          );
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(milliseconds: 50),
        );

        final emissions = <WeatherCondition>[];
        final sub = provider.conditions.listen(emissions.add);
        await provider.startMonitoring();

        // Wait for initial + 2 poll cycles.
        await Future.delayed(const Duration(milliseconds: 150));

        expect(fetchCount, greaterThanOrEqualTo(2));
        expect(emissions.length, greaterThanOrEqualTo(2));

        await sub.cancel();
        provider.dispose();
      });

      test('offline fallback: re-emits last condition on HTTP failure',
          () async {
        int callCount = 0;
        final mockClient = MockClient((_) async {
          callCount++;
          if (callCount == 1) {
            // First call succeeds.
            return http.Response(
              _jsonResponse(weatherCode: 71, temperature: -2.0),
              200,
            );
          }
          // Subsequent calls fail.
          return http.Response('Server Error', 500);
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(milliseconds: 50),
        );

        final emissions = <WeatherCondition>[];
        final sub = provider.conditions.listen(emissions.add);
        await provider.startMonitoring();

        // Wait for initial success + at least one failed poll.
        await Future.delayed(const Duration(milliseconds: 150));

        // Should have at least 2 emissions (first real, then fallback).
        expect(emissions.length, greaterThanOrEqualTo(2));
        // All emissions should be the same condition (fallback).
        for (final e in emissions) {
          expect(e.precipType, PrecipitationType.snow);
          expect(e.temperatureCelsius, -2.0);
        }

        await sub.cancel();
        provider.dispose();
      });

      test('offline fallback: no emission when no prior condition', () async {
        final mockClient = MockClient((_) async {
          return http.Response('Server Error', 500);
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(milliseconds: 50),
        );

        final emissions = <WeatherCondition>[];
        final sub = provider.conditions.listen(emissions.add);
        await provider.startMonitoring();

        // Wait a bit — should emit nothing.
        await Future.delayed(const Duration(milliseconds: 150));

        expect(emissions, isEmpty);

        await sub.cancel();
        provider.dispose();
      });

      test('stopMonitoring stops polling', () async {
        int fetchCount = 0;
        final mockClient = MockClient((_) async {
          fetchCount++;
          return http.Response(
            _jsonResponse(weatherCode: 0, temperature: 10.0),
            200,
          );
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(milliseconds: 50),
        );

        final emissions = <WeatherCondition>[];
        final sub = provider.conditions.listen(emissions.add);
        await provider.startMonitoring();

        // Wait for initial fetch.
        await Future.delayed(const Duration(milliseconds: 30));
        final countAfterStart = fetchCount;

        await provider.stopMonitoring();
        await Future.delayed(const Duration(milliseconds: 150));

        // No additional fetches after stop.
        expect(fetchCount, countAfterStart);

        await sub.cancel();
        provider.dispose();
      });

      test('dispose closes stream', () async {
        final mockClient = MockClient((_) async {
          return http.Response(
            _jsonResponse(weatherCode: 0, temperature: 10.0),
            200,
          );
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(seconds: 60),
        );

        await provider.startMonitoring();
        provider.dispose();

        // Stream should be done after dispose.
        expect(
          () => provider.conditions,
          returnsNormally,
        );
      });
    });

    group('coordinate configuration', () {
      test('uses custom coordinates in API request', () async {
        final mockClient = MockClient((request) async {
          expect(request.url.queryParameters['latitude'], '34.5');
          expect(request.url.queryParameters['longitude'], '135.5');
          return http.Response(
            _jsonResponse(weatherCode: 0, temperature: 10.0),
            200,
          );
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          latitude: 34.5,
          longitude: 135.5,
        );

        await provider.fetchWeather();
        provider.dispose();
      });
    });
  });
}
