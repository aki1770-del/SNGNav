/// Tests for the MET Norway hourly-forecast provider feeding the pre-trip
/// "Before you drive" briefing.
///
/// Coverage:
/// - mapper against a REAL captured locationforecast/2.0/compact response
///   (Nagoya, fetched live 2026-06-12 — fixtures/) — slice counts, field
///   mapping, hourly-only filtering, issuedAt;
/// - mapper honesty rules: visibility/surface ALWAYS null, missing
///   temperature skips the slice, missing meta.updated_at returns null;
/// - HTTP provider via injected MockClient: request shape (User-Agent,
///   4-decimal coordinate truncation), non-200 / malformed-body errors,
///   empty-UA rejection;
/// - end-to-end: a synthetic winter response mapped and handed to
///   [SnowAwarePretripAdvisor] produces a hazard verdict from temperature +
///   precipitation alone (no visibility in the compact product).
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_met_norway/pretrip_source_met_norway.dart';
import 'package:test/test.dart';

const _fixturePath = 'test/fixtures/met_norway_compact_nagoya_2026_06_12.json';

Map<String, dynamic> _loadFixture() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, dynamic>;

/// A minimal synthetic compact response. [slices] is a list of
/// (isoTime, tempC, precipMm-or-null) where precip null means the slice has
/// no next_1_hours block (6-hourly tail shape).
Map<String, dynamic> _syntheticResponse({
  String updatedAt = '2026-01-01T05:30:00Z',
  required List<(String, double?, double?)> slices,
}) => {
  'type': 'Feature',
  'geometry': {
    'type': 'Point',
    'coordinates': [136.8815, 35.1709, 10],
  },
  'properties': {
    'meta': {
      'updated_at': updatedAt,
      'units': {'air_temperature': 'celsius'},
    },
    'timeseries': [
      for (final (time, temp, precip) in slices)
        {
          'time': time,
          'data': {
            'instant': {
              'details': {'air_temperature': ?temp, 'relative_humidity': 80.0},
            },
            if (precip != null)
              'next_1_hours': {
                'summary': {'symbol_code': 'snow'},
                'details': {'precipitation_amount': precip},
              },
          },
        },
    ],
  },
};

void main() {
  group('mapLocationForecastToWeatherForecast — real captured response', () {
    test('maps the full hourly timeseries with honest nulls', () {
      final forecast = mapLocationForecastToWeatherForecast(_loadFixture());

      expect(forecast, isNotNull);
      // The captured response has 90 slices, 63 of them hourly
      // (next_1_hours present) — only those map.
      expect(forecast!.hourly.length, 63);
      expect(forecast.issuedAt.toUtc(), DateTime.utc(2026, 6, 12, 9, 15, 55));

      final first = forecast.hourly.first;
      expect(first.hour.toUtc(), DateTime.utc(2026, 6, 12, 9));
      expect(first.tempCelsius, 23.7);
      expect(first.humidityRH, 65.4);
      expect(first.precipitationMmPerHour, 0.0);

      // Honesty: the compact product has neither visibility nor surface
      // state — every slice must carry null, never an estimate.
      for (final slot in forecast.hourly) {
        expect(slot.visibilityMeters, isNull);
        expect(slot.estimatedRoadCondition, isNull);
      }

      // Ordered earliest-first per the contract convention.
      for (var i = 1; i < forecast.hourly.length; i++) {
        expect(
          forecast.hourly[i].hour.isAfter(forecast.hourly[i - 1].hour),
          isTrue,
        );
      }
    });
  });

  group('mapLocationForecastToWeatherForecast — honesty rules', () {
    test('slices without next_1_hours (6-hourly tail) are skipped', () {
      final forecast = mapLocationForecastToWeatherForecast(
        _syntheticResponse(
          slices: [
            ('2026-01-01T06:00:00Z', -4.0, 1.5),
            ('2026-01-01T12:00:00Z', -2.0, null), // 6-hourly shape — skipped
          ],
        ),
      );
      expect(forecast!.hourly.length, 1);
      expect(forecast.hourly.single.hour.toUtc(), DateTime.utc(2026, 1, 1, 6));
    });

    test('a slice missing air_temperature is skipped, not guessed', () {
      final forecast = mapLocationForecastToWeatherForecast(
        _syntheticResponse(
          slices: [
            ('2026-01-01T06:00:00Z', null, 1.5),
            ('2026-01-01T07:00:00Z', -4.0, 1.5),
          ],
        ),
      );
      expect(forecast!.hourly.length, 1);
      expect(forecast.hourly.single.tempCelsius, -4.0);
    });

    test('missing meta.updated_at returns null — no invented issue time', () {
      final response = _syntheticResponse(
        slices: [('2026-01-01T06:00:00Z', -4.0, 1.5)],
      );
      ((response['properties'] as Map<String, dynamic>)['meta']
              as Map<String, dynamic>)
          .remove('updated_at');
      expect(mapLocationForecastToWeatherForecast(response), isNull);
    });

    test('no usable hourly slices returns null', () {
      expect(
        mapLocationForecastToWeatherForecast(
          _syntheticResponse(slices: [('2026-01-01T12:00:00Z', -2.0, null)]),
        ),
        isNull,
      );
      expect(mapLocationForecastToWeatherForecast(const {}), isNull);
    });
  });

  group('MetNorwayHourlyForecastProvider — HTTP behaviour', () {
    test('sends identifying UA and 4-decimal truncated coordinates', () async {
      late http.Request seen;
      final provider = MetNorwayHourlyForecastProvider.withClient(
        MockClient((request) async {
          seen = request;
          return http.Response(
            jsonEncode(
              _syntheticResponse(slices: [('2026-01-01T06:00:00Z', -4.0, 1.5)]),
            ),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final forecast = await provider.fetchForecast(
        latitude: 35.17091234,
        longitude: 136.88159876,
      );

      expect(forecast, isNotNull);
      expect(seen.headers['User-Agent'], contains('sngnav'));
      // MET Norway terms: max 4 decimals — truncated, not rounded.
      expect(seen.url.queryParameters['lat'], '35.1709');
      expect(seen.url.queryParameters['lon'], '136.8815');
    });

    test('non-200 raises MetNorwayForecastException', () {
      final provider = MetNorwayHourlyForecastProvider.withClient(
        MockClient((_) async => http.Response('throttled', 429)),
      );
      expect(
        () => provider.fetchForecast(latitude: 35.0, longitude: 136.0),
        throwsA(isA<MetNorwayForecastException>()),
      );
    });

    test('malformed JSON raises MetNorwayForecastException', () {
      final provider = MetNorwayHourlyForecastProvider.withClient(
        MockClient((_) async => http.Response('not json {', 200)),
      );
      expect(
        () => provider.fetchForecast(latitude: 35.0, longitude: 136.0),
        throwsA(isA<MetNorwayForecastException>()),
      );
    });

    test('empty User-Agent is rejected before any request', () {
      var called = false;
      final provider = MetNorwayHourlyForecastProvider.withClient(
        MockClient((_) async {
          called = true;
          return http.Response('{}', 200);
        }),
        userAgent: '   ',
      );
      expect(
        () => provider.fetchForecast(latitude: 35.0, longitude: 136.0),
        throwsA(isA<MetNorwayForecastException>()),
      );
      expect(called, isFalse);
    });
  });

  group('end-to-end: live-shaped winter response → pre-trip verdict', () {
    test('snow at -4 °C fires the icing rule from temperature + precipitation '
        'alone (no visibility in the compact product)', () {
      // Snowy departure hour, clearing two hours later — the canonical
      // wait-advised morning, expressed purely in compact-product fields.
      final forecast = mapLocationForecastToWeatherForecast(
        _syntheticResponse(
          slices: [
            ('2026-01-01T07:00:00Z', -4.0, 2.5),
            ('2026-01-01T08:00:00Z', -3.0, 1.0),
            ('2026-01-01T09:00:00Z', -1.0, 0.0),
            ('2026-01-01T10:00:00Z', 0.0, 0.0),
          ],
        ),
      )!;

      const advisor = SnowAwarePretripAdvisor();
      final briefing = advisor.brief(
        forecast: forecast,
        commute: CommuteShape(
          plannedDeparture: DateTime.utc(2026, 1, 1, 7, 15).toLocal(),
          plannedDuration: const Duration(minutes: 30),
          routeIdentifiers: const ['live-commute'],
          flexibility: CommuteFlexibility.discretionary,
        ),
        profile: const DriverProfileSpec(
          profileTag: 'demo',
          reactionTimeSeconds: 1.5,
        ),
      );

      // Precipitation at -4 °C is the advisor's icing surface → elevated,
      // and a clear window exists within the horizon → wait advised.
      expect(briefing.peakHazard, HourHazard.elevated);
      expect(briefing.verdict, PretripVerdict.waitAdvised);
      expect(
        briefing.recommendation!.suggestedDelay,
        greaterThan(Duration.zero),
      );
    });

    test('the real June Nagoya capture maps to a clear verdict', () {
      final forecast = mapLocationForecastToWeatherForecast(_loadFixture())!;
      const advisor = SnowAwarePretripAdvisor();
      final briefing = advisor.brief(
        forecast: forecast,
        // Depart within the captured forecast's first hour.
        commute: CommuteShape(
          plannedDeparture: DateTime.utc(2026, 6, 12, 9, 15).toLocal(),
          plannedDuration: const Duration(minutes: 30),
          routeIdentifiers: const ['live-commute'],
          flexibility: CommuteFlexibility.discretionary,
        ),
        profile: const DriverProfileSpec(
          profileTag: 'demo',
          reactionTimeSeconds: 1.5,
        ),
      );
      // 23.7 °C clearsky June morning — the honest verdict is "clear", and
      // nothing in the pipeline fabricated a winter hazard from null fields.
      expect(briefing.verdict, PretripVerdict.clear);
    });
  });
}
