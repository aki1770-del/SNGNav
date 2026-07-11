/// OpenMeteoWeatherProvider unit tests.
///
/// The group "absence is never filled in" FAILS against 0.4.4, where an empty
/// `hourly` block silently produced `visibility = 10000` (i.e. "clear") and
/// `snowfall = 0` — values the API never sent.
///
/// The group "a failed fetch says so" FAILS against 0.4.4, which re-emitted the
/// last condition with no staleness marker and went silent when it had none.
library;

import 'dart:convert';

import 'package:test/test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:driving_weather/driving_weather.dart';

// ---------------------------------------------------------------------------
// Test data — realistic Open-Meteo API response
// ---------------------------------------------------------------------------

Map<String, dynamic> _buildResponse({
  double? temperature = 5.0,
  int? weatherCode = 0,
  double? windSpeed = 10.0,
  double? humidity,
  List<double>? snowfall,
  List<double>? visibility,
  bool includeHourly = true,
}) {
  final hours = List.generate(
    24,
    (i) => '2026-02-27T${i.toString().padLeft(2, '0')}:00',
  );
  return {
    'current': {
      if (temperature != null) 'temperature_2m': temperature,
      if (humidity != null) 'relative_humidity_2m': humidity,
      if (weatherCode != null) 'weather_code': weatherCode,
      if (windSpeed != null) 'wind_speed_10m': windSpeed,
    },
    if (includeHourly)
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
  return jsonEncode(
    _buildResponse(
      temperature: temperature,
      weatherCode: weatherCode,
      windSpeed: windSpeed,
      snowfall: snowfall,
      visibility: visibility,
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('absence is never filled in', () {
    test('an EMPTY hourly block leaves visibility null — not 10 km', () {
      final json = _buildResponse(
        weatherCode: 0,
        temperature: 3.0,
        snowfall: const <double>[],
        visibility: const <double>[],
      );
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      // 0.4.4 hardcoded `double visibility = 10000` as the fallback here and
      // shipped it as if the API had said "you can see for 10 km".
      expect(c.visibilityMeters, isNull);
      expect(c.reducedVisibility, SafetyVerdict.unknown);
    });

    test('an ABSENT hourly block leaves visibility null', () {
      final json = _buildResponse(
        weatherCode: 0,
        temperature: 3.0,
        includeHourly: false,
      );
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.visibilityMeters, isNull);
    });

    test('a missing temperature leaves temperature AND ice risk unknown', () {
      final json = _buildResponse(temperature: null, weatherCode: 71);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      // Never "above freezing", never "no ice".
      expect(c.temperatureCelsius, isNull);
      expect(c.freezing, SafetyVerdict.unknown);
      expect(c.iceRisk, isNull);
    });

    test('a missing weather code leaves precipitation unknown', () {
      final json = _buildResponse(weatherCode: null, temperature: 2.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, isNull);
      expect(c.intensity, isNull);
      expect(c.snowing, SafetyVerdict.unknown);
      // And with intensity unknown, no clear-road verdict is possible.
      expect(c.hazard, SafetyVerdict.unknown);
    });

    test('a missing wind speed stays null — never 0 km/h', () {
      final json = _buildResponse(windSpeed: null, temperature: 2.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.windSpeedKmh, isNull);
    });

    test('snowfall still evidences snow when the code is missing', () {
      // Positive evidence fires on partial data — the asymmetry, at the parser.
      final json = _buildResponse(
        weatherCode: null,
        temperature: -2.0,
        snowfall: List.filled(24, 3.0),
      );
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.snow);
      expect(c.intensity, PrecipitationIntensity.heavy);
      expect(c.hazard, SafetyVerdict.hazardous);
    });
  });

  group('parseWeatherResponse', () {
    test('clear sky (code 0) → none/none, and it is a MEASURED source', () {
      final json = _buildResponse(weatherCode: 0, temperature: 15.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.none);
      expect(c.intensity, PrecipitationIntensity.none);
      expect(c.temperatureCelsius, 15.0);
      expect(c.iceRisk, isFalse);
      expect(c.source, ObservationSource.measured);
      // Everything the verdict needs is present, so a clear-road answer is
      // legitimate here — this is what an honest `notHazardous` looks like.
      expect(c.hazard, SafetyVerdict.notHazardous);
    });

    test('relative_humidity_2m is parsed into humidityRH (percent)', () {
      final json = _buildResponse(temperature: 1.0, humidity: 82.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.humidityRH, 82.0);
    });

    test('humidityRH stays null when the feed omits humidity', () {
      final json = _buildResponse(temperature: 1.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.humidityRH, isNull);
    });

    test('light snow (code 71) → snow/light', () {
      final json = _buildResponse(weatherCode: 71, temperature: -2.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.snow);
      expect(c.intensity, PrecipitationIntensity.light);
      expect(c.temperatureCelsius, -2.0);
    });

    test('heavy snow (code 75) → snow/heavy', () {
      final json = _buildResponse(weatherCode: 75, temperature: -5.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.snow);
      expect(c.intensity, PrecipitationIntensity.heavy);
      expect(c.hazard, SafetyVerdict.hazardous);
    });

    test('moderate snow (code 73) → snow/moderate', () {
      final json = _buildResponse(weatherCode: 73, temperature: -1.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.snow);
      expect(c.intensity, PrecipitationIntensity.moderate);
    });

    test('light rain (code 61) → rain/light', () {
      final json = _buildResponse(weatherCode: 61, temperature: 8.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.rain);
      expect(c.intensity, PrecipitationIntensity.light);
    });

    test('freezing rain (code 66) → sleet/light', () {
      final json = _buildResponse(weatherCode: 66, temperature: -1.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.sleet);
      expect(c.intensity, PrecipitationIntensity.light);
    });

    test('ice risk when sub-zero + precipitation', () {
      final json = _buildResponse(weatherCode: 71, temperature: -3.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.iceRisk, isTrue);
      expect(c.freezing, SafetyVerdict.hazardous);
      expect(c.hazard, SafetyVerdict.hazardous);
    });

    test('no ice risk when warm temperature', () {
      final json = _buildResponse(weatherCode: 61, temperature: 8.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.iceRisk, isFalse);
    });

    test('snowfall inference from hourly data', () {
      final json = _buildResponse(
        weatherCode: 0,
        temperature: -2.0,
        snowfall: List.filled(24, 1.0), // 1 cm/hr
      );
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.snow);
      expect(c.intensity, PrecipitationIntensity.moderate);
    });

    test('visibility from hourly data', () {
      final json = _buildResponse(
        weatherCode: 73,
        temperature: -1.0,
        visibility: List.filled(24, 500.0),
      );
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.visibilityMeters, 500.0);
      expect(c.reducedVisibility, SafetyVerdict.hazardous);
    });

    test('snow shower codes map correctly', () {
      final c85 = OpenMeteoWeatherProvider.parseWeatherResponse(
        _buildResponse(weatherCode: 85, temperature: -1.0),
      );
      expect(c85.precipType, PrecipitationType.snow);
      expect(c85.intensity, PrecipitationIntensity.light);

      final c86 = OpenMeteoWeatherProvider.parseWeatherResponse(
        _buildResponse(weatherCode: 86, temperature: -3.0),
      );
      expect(c86.precipType, PrecipitationType.snow);
      expect(c86.intensity, PrecipitationIntensity.heavy);
    });

    test('thunderstorm codes map to rain/heavy', () {
      final json = _buildResponse(weatherCode: 95, temperature: 10.0);
      final c = OpenMeteoWeatherProvider.parseWeatherResponse(json);

      expect(c.precipType, PrecipitationType.rain);
      expect(c.intensity, PrecipitationIntensity.heavy);
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

      expect(() => provider.fetchWeather(), throwsA(isA<HttpException>()));

      provider.dispose();
    });
  });

  group('stream behavior', () {
    test('startMonitoring emits an observed reading on start', () async {
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

      final first = provider.conditions.first;
      await provider.startMonitoring();

      final reading = await first.timeout(const Duration(seconds: 5));
      expect(reading, isA<WeatherObserved>());
      expect(
        (reading as WeatherObserved).condition.precipType,
        PrecipitationType.none,
      );

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

      final emissions = <WeatherReading>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(fetchCount, greaterThanOrEqualTo(2));
      expect(emissions.length, greaterThanOrEqualTo(2));

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

      final emissions = <WeatherReading>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 30));
      final countAfterStart = fetchCount;

      await provider.stopMonitoring();
      await Future<void>.delayed(const Duration(milliseconds: 150));

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

      expect(() => provider.conditions, returnsNormally);
    });
  });

  group('a failed fetch says so', () {
    test(
      'emits WeatherStale carrying the last known value and its real age',
      () async {
        int callCount = 0;
        final mockClient = MockClient((_) async {
          callCount++;
          if (callCount == 1) {
            return http.Response(
              _jsonResponse(weatherCode: 71, temperature: -2.0),
              200,
            );
          }
          return http.Response('Server Error', 500);
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(milliseconds: 50),
        );

        final emissions = <WeatherReading>[];
        final sub = provider.conditions.listen(emissions.add);
        await provider.startMonitoring();

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(emissions.length, greaterThanOrEqualTo(2));
        expect(emissions.first, isA<WeatherObserved>());

        // 0.4.4 re-emitted the first condition verbatim, indistinguishable from
        // a fresh one. Stale data now announces itself.
        final stale = emissions.whereType<WeatherStale>().toList();
        expect(stale, isNotEmpty);
        expect(stale.first.lastKnown.precipType, PrecipitationType.snow);
        expect(stale.first.lastKnown.temperatureCelsius, -2.0);
        expect(stale.first.cause, isA<HttpException>());
        expect(stale.first.age.isNegative, isFalse);
        // Nothing after the first success claims to be a fresh observation.
        expect(emissions.skip(1).whereType<WeatherObserved>(), isEmpty);

        await sub.cancel();
        provider.dispose();
      },
    );

    test(
      'emits WeatherUnavailable when it never had data — never silence',
      () async {
        final mockClient = MockClient((_) async {
          return http.Response('Server Error', 500);
        });

        final provider = OpenMeteoWeatherProvider(
          client: mockClient,
          pollInterval: const Duration(milliseconds: 50),
        );

        final emissions = <WeatherReading>[];
        final sub = provider.conditions.listen(emissions.add);
        await provider.startMonitoring();

        await Future<void>.delayed(const Duration(milliseconds: 150));

        // 0.4.4 emitted NOTHING here — the UI could not tell "offline" from
        // "still loading". The absence of data is now a reading in its own right.
        expect(emissions, isNotEmpty);
        expect(emissions.every((r) => r is WeatherUnavailable), isTrue);
        expect(
          (emissions.first as WeatherUnavailable).cause,
          isA<HttpException>(),
        );

        await sub.cancel();
        provider.dispose();
      },
    );
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

  group('a malformed body is a FAILURE, not an all-null observation', () {
    test('a body with no `current` block throws WeatherParseException', () {
      // Before this guard, an empty/garbage 200-body parsed cleanly into a
      // condition with every field null — and was then emitted as
      // WeatherObserved (a reading that observed nothing) AND written over
      // _lastCondition, poisoning the WeatherStale fallback the driver depends
      // on when the network dies.
      expect(
        () => OpenMeteoWeatherProvider.parseWeatherResponse(const {}),
        throwsA(isA<WeatherParseException>()),
      );
    });

    test('a fully-unknown condition never overwrites the last real one', () async {
      var callCount = 0;
      final mock = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          // A real observation.
          return http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': -3.0,
                'weather_code': 71,
                'wind_speed_10m': 12.0,
              },
              'hourly': {'snowfall': <double>[], 'visibility': <double>[]},
            }),
            200,
          );
        }
        // Then the feed goes bad.
        return http.Response(jsonEncode(const {}), 200);
      });

      final provider = OpenMeteoWeatherProvider(
        client: mock,
        pollInterval: const Duration(milliseconds: 50),
      );
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);

      await provider.startMonitoring();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await provider.stopMonitoring();
      await sub.cancel();
      provider.dispose();

      expect(readings.first, isA<WeatherObserved>());
      final stale = readings.whereType<WeatherStale>().toList();
      expect(stale, isNotEmpty, reason: 'a broken body must route to stale');
      // The stale reading carries the LAST REAL observation, not a null husk.
      expect(stale.first.lastKnown.temperatureCelsius, -3.0);
    });
  });

  group('the current hour is not substituted by a different hour', () {
    test('a list too short to reach the current hour yields null', () {
      final hour = DateTime.now().hour;
      final short = List<double>.filled(hour, 99.0); // index `hour` is absent

      final c = OpenMeteoWeatherProvider.parseWeatherResponse({
        'current': {'temperature_2m': -2.0, 'weather_code': 71},
        'hourly': {'snowfall': short, 'visibility': short},
      });

      // Clamping would have returned the LAST hour we happen to hold and
      // presented it as "now" — a real measurement, of the wrong hour.
      expect(c.visibilityMeters, isNull);
    });

    test('a non-numeric hourly entry yields null rather than throwing', () {
      final hour = DateTime.now().hour;
      final bad = List<Object>.filled(hour + 1, 'n/a');

      final c = OpenMeteoWeatherProvider.parseWeatherResponse({
        'current': {'temperature_2m': -2.0, 'weather_code': 71},
        'hourly': {'snowfall': bad, 'visibility': bad},
      });

      expect(c.visibilityMeters, isNull);
    });

    test('the current hour IS read when the list reaches it', () {
      final hour = DateTime.now().hour;
      final vis = List<double>.generate(hour + 1, (i) => 100.0 + i);

      final c = OpenMeteoWeatherProvider.parseWeatherResponse({
        'current': {'temperature_2m': -2.0, 'weather_code': 71},
        'hourly': {'visibility': vis},
      });

      expect(c.visibilityMeters, 100.0 + hour);
    });
  });
}
