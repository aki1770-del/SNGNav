/// Tests for the Digitraffic measured-visibility provider feeding the
/// pre-trip briefing — the channel that closes the measured severe-band
/// ceiling (2026-06-12 quant run: 0/620 live forecast slots can reach
/// severe; 453/526 Finnish road stations report real visibility).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';
import 'package:test/test.dart';

// Helsinki-ish query point.
const _lat = 60.2;
const _lon = 24.6;

/// Station metadata GeoJSON shaped like the real /stations response
/// (verified live 2026-06-12).
String _metadata() => jsonEncode({
  'type': 'FeatureCollection',
  'features': [
    {
      'type': 'Feature',
      'id': 1001,
      'geometry': {
        'type': 'Point',
        'coordinates': [24.596399, 60.228227, 0.0],
      },
      'properties': {
        'id': 1001,
        'name': 'vt1_Espoo_Nupuri',
        'collectionStatus': 'GATHERING',
      },
    },
    {
      'type': 'Feature',
      'id': 2002,
      'geometry': {
        'type': 'Point',
        'coordinates': [24.70, 60.25, 0.0],
      },
      'properties': {
        'id': 2002,
        'name': 'vt1_Espoo_Removed',
        'collectionStatus': 'REMOVED_TEMPORARILY',
      },
    },
    {
      'type': 'Feature',
      'id': 3003,
      'geometry': {
        'type': 'Point',
        'coordinates': [25.66, 60.98, 0.0], // ~100 km away
      },
      'properties': {
        'id': 3003,
        'name': 'vt4_Lahti_Far',
        'collectionStatus': 'GATHERING',
      },
    },
  ],
});

String _stationData(
  int id, {
  double? meters,
  double? km,
  required String measuredTime,
}) => jsonEncode({
  'id': id,
  'dataUpdatedTime': measuredTime,
  'sensorValues': [
    {
      'id': 1,
      'stationId': id,
      'name': 'ILMA',
      'unit': '°C',
      'value': -3.0,
      'measuredTime': measuredTime,
    },
    if (km != null)
      {
        'id': 26,
        'stationId': id,
        'name': 'NÄKYVYYS_KM',
        'unit': 'km',
        'value': km,
        'measuredTime': measuredTime,
      },
    if (meters != null)
      {
        'id': 58,
        'stationId': id,
        'name': 'NÄKYVYYS_M',
        'unit': 'm',
        'value': meters,
        'measuredTime': measuredTime,
      },
  ],
});

void main() {
  final now = DateTime.utc(2026, 6, 12, 10, 30);
  final fresh = '2026-06-12T10:25:00Z'; // 5 min old at [now]
  final stale = '2026-06-12T08:00:00Z'; // 2.5 h old at [now]

  DigitrafficVisibilityProvider provider(
    MockClient client, {
    double maxDistanceKm = 30,
  }) => DigitrafficVisibilityProvider.withClient(
    client,
    maxDistanceKm: maxDistanceKm,
  );

  group('fetchNearestVisibility', () {
    test(
      'returns the nearest GATHERING station with a fresh NÄKYVYYS_M',
      () async {
        final requests = <String>[];
        final p = provider(
          MockClient((req) async {
            requests.add(req.url.path);
            if (req.url.path.endsWith('/stations')) {
              expect(req.headers['User-Agent'], contains('pretrip_source'));
              expect(req.headers['Accept-Encoding'], contains('gzip'));
              return http.Response(
                _metadata(),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            if (req.url.path.endsWith('/stations/1001/data')) {
              return http.Response(
                _stationData(1001, meters: 120, km: 0.1, measuredTime: fresh),
                200,
                headers: const {
                  'content-type': 'application/json; charset=utf-8',
                },
              );
            }
            fail('unexpected request: ${req.url}');
          }),
        );

        final obs = await p.fetchNearestVisibility(
          latitude: _lat,
          longitude: _lon,
          now: now.toLocal(),
        );

        expect(obs, isNotNull);
        expect(obs!.meters, 120); // NÄKYVYYS_M preferred over KM
        expect(obs.stationId, 1001);
        expect(obs.stationName, 'vt1_Espoo_Nupuri');
        expect(obs.distanceKm, lessThan(5));
        // REMOVED_TEMPORARILY and out-of-range stations were never queried.
        expect(requests.where((p) => p.contains('2002')), isEmpty);
        expect(requests.where((p) => p.contains('3003')), isEmpty);
      },
    );

    test('falls back to NÄKYVYYS_KM × 1000 when no metres sensor', () async {
      final p = provider(
        MockClient((req) async {
          if (req.url.path.endsWith('/stations')) {
            return http.Response(
              _metadata(),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response(
            _stationData(1001, km: 2.0, measuredTime: fresh),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final obs = await p.fetchNearestVisibility(
        latitude: _lat,
        longitude: _lon,
        now: now.toLocal(),
      );
      expect(obs!.meters, 2000);
    });

    test('a stale observation is discarded, never served as current', () async {
      final p = provider(
        MockClient((req) async {
          if (req.url.path.endsWith('/stations')) {
            return http.Response(
              _metadata(),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          return http.Response(
            _stationData(1001, meters: 120, measuredTime: stale),
            200,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final obs = await p.fetchNearestVisibility(
        latitude: _lat,
        longitude: _lon,
        now: now.toLocal(),
      );
      expect(obs, isNull);
    });

    test('no station within range → null, nothing estimated', () async {
      final p = provider(
        MockClient((req) async {
          if (req.url.path.endsWith('/stations')) {
            return http.Response(
              _metadata(),
              200,
              headers: const {
                'content-type': 'application/json; charset=utf-8',
              },
            );
          }
          fail('no data fetch expected when nothing is in range');
        }),
        maxDistanceKm: 1, // nearest real station is ~3 km away
      );
      final obs = await p.fetchNearestVisibility(
        latitude: _lat,
        longitude: _lon,
        now: now.toLocal(),
      );
      expect(obs, isNull);
    });

    test('non-200 raises DigitrafficVisibilityException', () {
      final p = provider(
        MockClient(
          (_) async => http.Response(
            'nope',
            406,
            headers: const {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      expect(
        () => p.fetchNearestVisibility(latitude: _lat, longitude: _lon),
        throwsA(isA<DigitrafficVisibilityException>()),
      );
    });
  });

  group('mergeObservedVisibility', () {
    final issued = DateTime(2026, 1, 1, 6);
    WeatherForecast forecast() => WeatherForecast(
      issuedAt: issued,
      hourly: [
        for (var h = 7; h <= 10; h++)
          HourlyForecast(
            hour: DateTime(2026, 1, 1, h),
            tempCelsius: -4,
            precipitationMmPerHour: 1.0,
          ),
      ],
    );
    final obs = VisibilityObservation(
      meters: 80,
      stationId: 1001,
      stationName: 'test',
      measuredAt: DateTime(2026, 1, 1, 7, 10),
      distanceKm: 3,
    );

    test('sets visibility on the departure-hour slot ONLY', () {
      final merged = mergeObservedVisibility(
        forecast(),
        obs,
        DateTime(2026, 1, 1, 7, 15),
      );
      expect(merged.hourly[0].visibilityMeters, 80);
      for (final s in merged.hourly.skip(1)) {
        expect(
          s.visibilityMeters,
          isNull,
          reason: 'a NOW measurement must never be projected forward',
        );
      }
      // Everything else carried through unchanged.
      expect(merged.hourly[0].tempCelsius, -4);
      expect(merged.issuedAt, issued);
    });

    test('no covering slot → forecast unchanged', () {
      final merged = mergeObservedVisibility(
        forecast(),
        obs,
        DateTime(2026, 1, 1, 23, 0),
      );
      expect(merged.hourly.every((s) => s.visibilityMeters == null), isTrue);
    });

    test('END-TO-END: a measured 80 m observation lights the severe band the '
        'forecast alone never reaches (0/620, 2026-06-12 quant run)', () {
      const advisor = SnowAwarePretripAdvisor();
      final departure = DateTime(2026, 1, 1, 7, 15);

      final withoutObs = advisor.brief(
        forecast: forecast(),
        commute: CommuteShape(
          plannedDeparture: departure,
          plannedDuration: const Duration(minutes: 30),
          routeIdentifiers: const ['fi-route'],
          flexibility: CommuteFlexibility.discretionary,
        ),
        profile: const DriverProfileSpec(
          profileTag: 'fi',
          reactionTimeSeconds: 1.5,
        ),
      );
      // Forecast alone: icing rule → elevated is the ceiling.
      expect(withoutObs.peakHazard, HourHazard.elevated);

      final withObs = advisor.brief(
        forecast: mergeObservedVisibility(forecast(), obs, departure),
        commute: CommuteShape(
          plannedDeparture: departure,
          plannedDuration: const Duration(minutes: 30),
          routeIdentifiers: const ['fi-route'],
          flexibility: CommuteFlexibility.discretionary,
        ),
        profile: const DriverProfileSpec(
          profileTag: 'fi',
          reactionTimeSeconds: 1.5,
        ),
      );
      // Real sensor at 80 m: whiteout-class severe, named in the chips.
      expect(withObs.peakHazard, HourHazard.severe);
      expect(
        withObs.chips.any((c) => c.contains('whiteout')),
        isTrue,
        reason: 'severe must be named plainly: ${withObs.chips}',
      );
    });
  });
}
