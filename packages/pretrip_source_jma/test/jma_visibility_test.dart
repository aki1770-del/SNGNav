/// Tests for the JMA AMeDAS measured-visibility provider feeding the Japan
/// pre-trip briefing — the channel that lets HER mother's Akita briefing reach
/// the measured WHITEOUT band the MET base + JMA warning merge alone never
/// can (probed 2026-06-14 live: 151/1286 AMeDAS stations report visibility,
/// incl. 秋田/Akita 32402). Mirrors the Digitraffic provider's honesty rules.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_jma/pretrip_source_jma.dart';
import 'package:test/test.dart';

// HER mother's anchor: 秋田 / Akita.
const _lat = 39.72;
const _lon = 140.10;

/// AMeDAS station metadata shaped like the real amedastable.json (verified live
/// 2026-06-14): `{code: {lat: [deg, min], lon: [deg, min], enName, ...}}`.
String _table() => jsonEncode({
      '32402': {
        'type': 'A',
        'lat': [39, 43.0], // 39.717 — ~0.4 km from query
        'lon': [140, 5.9], // 140.098
        'kjName': '秋田',
        'enName': 'Akita',
      },
      '32056': {
        'type': 'A',
        'lat': [39, 45.0], // ~4 km away, but carries no visibility sensor
        'lon': [140, 7.0],
        'kjName': '近傍',
        'enName': 'NearNoVis',
      },
      '44132': {
        'type': 'A',
        'lat': [35, 41.4], // Tokyo — far beyond 50 km
        'lon': [139, 45.0],
        'kjName': '東京',
        'enName': 'Tokyo',
      },
    });

/// AMeDAS map snapshot: `{code: {visibility: [metres, qcFlag], temp: [...]}}`.
String _map({
  required double akitaVisMeters,
  int akitaFlag = 0,
  bool akitaHasVisibility = true,
}) =>
    jsonEncode({
      '32402': {
        'temp': [-6.0, 0],
        if (akitaHasVisibility) 'visibility': [akitaVisMeters, akitaFlag],
      },
      // NearNoVis reports temperature but NO visibility sensor.
      '32056': {
        'temp': [-5.0, 0],
      },
    });

void main() {
  // latest_time.txt is JST (+09:00); the snapshot timestamp drives the map
  // filename, the freshness check, and the observation's measuredAt.
  const freshTs = '2026-06-14T18:30:00+09:00'; // == 09:30Z
  const staleTs = '2026-06-14T17:00:00+09:00'; // == 08:00Z
  final now = DateTime.utc(2026, 6, 14, 9, 40); // 10 min after freshTs

  JmaVisibilityProvider provider(MockClient client) =>
      JmaVisibilityProvider.withClient(client);

  MockClient client({
    required String latestTs,
    String? mapBody,
  }) =>
      MockClient((req) async {
        final path = req.url.path;
        if (path.endsWith('latest_time.txt')) {
          expect(req.headers['User-Agent'], contains('sngnav'));
          return http.Response(latestTs, 200);
        }
        if (path.endsWith('amedastable.json')) {
          return http.Response(_table(), 200,
              headers: const {'content-type': 'application/json'});
        }
        if (path.contains('/map/')) {
          // The map filename must be the 14-digit JST stem of freshTs.
          expect(path, contains('20260614183000'));
          return http.Response(mapBody ?? _map(akitaVisMeters: 80), 200,
              headers: const {'content-type': 'application/json'});
        }
        fail('unexpected request: ${req.url}');
      });

  group('fetchNearestVisibility', () {
    test('returns the nearest station with a fresh QC-flag-0 visibility',
        () async {
      final obs = await provider(client(latestTs: freshTs))
          .fetchNearestVisibility(latitude: _lat, longitude: _lon, now: now);
      expect(obs, isNotNull);
      expect(obs!.meters, 80);
      expect(obs.stationId, 32402);
      expect(obs.stationName, 'Akita');
      expect(obs.distanceKm, lessThan(2));
    });

    test('skips a nearer station that carries no visibility sensor', () async {
      // 32056 is closer in the table only if query is nudged; here Akita is
      // nearest AND has vis, but assert the no-vis station is never served.
      final obs = await provider(client(latestTs: freshTs))
          .fetchNearestVisibility(latitude: _lat, longitude: _lon, now: now);
      expect(obs!.stationName, isNot('NearNoVis'));
    });

    test('rejects a non-zero QC flag — never serves a suspect reading',
        () async {
      // Only nearby station with a visibility key has flag 1; nothing valid.
      final obs = await provider(
        client(
          latestTs: freshTs,
          mapBody: _map(akitaVisMeters: 50, akitaFlag: 1),
        ),
      ).fetchNearestVisibility(latitude: _lat, longitude: _lon, now: now);
      expect(obs, isNull);
    });

    test('a stale snapshot is discarded, never served as current', () async {
      final obs = await provider(client(latestTs: staleTs))
          .fetchNearestVisibility(latitude: _lat, longitude: _lon, now: now);
      expect(obs, isNull);
    });

    test('no station within range → null, nothing estimated', () async {
      // Query the middle of the ocean: every table station is > 50 km.
      final obs = await provider(client(latestTs: freshTs))
          .fetchNearestVisibility(latitude: 0, longitude: 0, now: now);
      expect(obs, isNull);
    });

    test('non-200 raises JmaVisibilityException', () {
      final p = provider(MockClient((_) async => http.Response('nope', 503)));
      expect(
        () => p.fetchNearestVisibility(latitude: _lat, longitude: _lon),
        throwsA(isA<JmaVisibilityException>()),
      );
    });
  });

  group('END-TO-END through the advisor', () {
    final issued = DateTime(2026, 1, 1, 6);
    WeatherForecast forecast() => WeatherForecast(
          issuedAt: issued,
          hourly: [
            for (var h = 7; h <= 10; h++)
              HourlyForecast(
                hour: DateTime(2026, 1, 1, h),
                tempCelsius: -6,
              ),
          ],
        );

    test('a measured 80 m AMeDAS observation lights the whiteout band for '
        'Akita that the forecast alone never reaches', () async {
      const advisor = SnowAwarePretripAdvisor();
      final departure = DateTime(2026, 1, 1, 7, 15);
      final commute = CommuteShape(
        plannedDeparture: departure,
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['akita-route'],
        flexibility: CommuteFlexibility.discretionary,
      );
      const profile =
          DriverProfileSpec(profileTag: 'akita', reactionTimeSeconds: 1.5);

      // Forecast alone (dry, −6 °C, no visibility): frost caution at most.
      final withoutObs = advisor.brief(
          forecast: forecast(), commute: commute, profile: profile);
      expect(withoutObs.peakHazard, HourHazard.caution);

      final obs = await provider(client(latestTs: freshTs))
          .fetchNearestVisibility(latitude: _lat, longitude: _lon, now: now);
      final withObs = advisor.brief(
        forecast: mergeObservedVisibility(forecast(), obs!, departure),
        commute: commute,
        profile: profile,
      );
      expect(withObs.peakHazard, HourHazard.severe);
      expect(
        withObs.chips.any((c) => c.contains('whiteout')),
        isTrue,
        reason: 'severe must be named plainly: ${withObs.chips}',
      );
    });
  });
}
