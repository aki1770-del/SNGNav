/// ValhallaRoutingEngine edge-case tests — maneuver type mapping, polyline6
/// decoding, request body construction, and error handling edge cases.
///
/// Supplements routing_engine_test.dart and routing_engine_contract_test.dart
/// with coverage for internal methods tested through the public API.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a MockClient returning a valid Valhalla route response with
/// configurable maneuvers.
MockClient valhallaClient({
  List<Map<String, dynamic>>? maneuvers,
  String shape = 'o}@o}@o}@o}@',
  double length = 25.7,
  double time = 1800,
}) {
  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'trip': {
          'summary': {'length': length, 'time': time},
          'legs': [
            {
              'shape': shape,
              'maneuvers':
                  maneuvers ??
                  [
                    {
                      'instruction': 'Drive east.',
                      'type': 1,
                      'length': length,
                      'time': time,
                      'begin_shape_index': 0,
                    },
                    {
                      'instruction': 'You have arrived.',
                      'type': 2,
                      'length': 0,
                      'time': 0,
                      'begin_shape_index': 1,
                    },
                  ],
            },
          ],
        },
      }),
      200,
    );
  });
}

const _nagoya = LatLng(35.17, 136.88);
const _okazaki = LatLng(34.97, 137.17);
const _request = RouteRequest(origin: _nagoya, destination: _okazaki);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ValhallaRoutingEngine — constructor defaults', () {
    test('default baseUrl is localhost:8002', () {
      final engine = ValhallaRoutingEngine();
      expect(engine.baseUrl, 'http://localhost:8002');
    });

    test('local constructor uses localhost:8005 by default', () {
      final engine = ValhallaRoutingEngine.local();
      expect(engine.baseUrl, 'http://localhost:8005');
    });

    test('custom baseUrl is preserved', () {
      final engine = ValhallaRoutingEngine(baseUrl: 'http://custom:9999');
      expect(engine.baseUrl, 'http://custom:9999');
    });

    test('local constructor accepts custom host and port', () {
      final engine = ValhallaRoutingEngine.local(host: 'machine-e', port: 9000);
      expect(engine.baseUrl, 'http://machine-e:9000');
    });

    test('custom timeouts are preserved', () {
      final engine = ValhallaRoutingEngine.local(
        availabilityTimeout: const Duration(seconds: 1),
        routeTimeout: const Duration(seconds: 20),
      );
      expect(engine.availabilityTimeout, const Duration(seconds: 1));
      expect(engine.routeTimeout, const Duration(seconds: 20));
    });
  });

  group('ValhallaRoutingEngine — isAvailable', () {
    test('returns true on 200', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('ok', 200)),
      );
      expect(await engine.isAvailable(), isTrue);
      await engine.dispose();
    });

    test('returns false on non-200', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('error', 503)),
      );
      expect(await engine.isAvailable(), isFalse);
      await engine.dispose();
    });

    test('returns false on network error', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      expect(await engine.isAvailable(), isFalse);
      await engine.dispose();
    });
  });

  group('ValhallaRoutingEngine — maneuver type mapping', () {
    Future<String> typeFor(int typeCode) async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(
          maneuvers: [
            {
              'instruction': 'Test',
              'type': typeCode,
              'length': 1.0,
              'time': 60,
              'begin_shape_index': 0,
            },
          ],
        ),
      );
      final result = await engine.calculateRoute(_request);
      await engine.dispose();
      return result.maneuvers.first.type;
    }

    test('type 0 → none', () async {
      expect(await typeFor(0), 'none');
    });

    test('type 1 → depart', () async {
      expect(await typeFor(1), 'depart');
    });

    test('type 2 → arrive', () async {
      expect(await typeFor(2), 'arrive');
    });

    test('type 3 → straight', () async {
      expect(await typeFor(3), 'straight');
    });

    test('type 4 → arrive (second arrive code)', () async {
      expect(await typeFor(4), 'arrive');
    });

    test('type 5 → slight_right', () async {
      expect(await typeFor(5), 'slight_right');
    });

    test('type 6 → right', () async {
      expect(await typeFor(6), 'right');
    });

    test('type 7 → sharp_right', () async {
      expect(await typeFor(7), 'sharp_right');
    });

    test('type 8 → u_turn_right', () async {
      expect(await typeFor(8), 'u_turn_right');
    });

    test('type 9 → u_turn_left', () async {
      expect(await typeFor(9), 'u_turn_left');
    });

    test('type 10 → sharp_left', () async {
      expect(await typeFor(10), 'sharp_left');
    });

    test('type 11 → left', () async {
      expect(await typeFor(11), 'left');
    });

    test('type 12 → slight_left', () async {
      expect(await typeFor(12), 'slight_left');
    });

    test('type 13 → ramp_straight', () async {
      expect(await typeFor(13), 'ramp_straight');
    });

    test('type 14 → ramp_right', () async {
      expect(await typeFor(14), 'ramp_right');
    });

    test('type 15 → ramp_left', () async {
      expect(await typeFor(15), 'ramp_left');
    });

    test('type 21 → merge', () async {
      expect(await typeFor(21), 'merge');
    });

    test('type 22 → roundabout_enter', () async {
      expect(await typeFor(22), 'roundabout_enter');
    });

    test('type 23 → roundabout_exit', () async {
      expect(await typeFor(23), 'roundabout_exit');
    });

    test('type 24 → ferry_enter', () async {
      expect(await typeFor(24), 'ferry_enter');
    });

    test('type 33 → merge_right', () async {
      expect(await typeFor(33), 'merge_right');
    });

    test('type 34 → merge_left', () async {
      expect(await typeFor(34), 'merge_left');
    });

    test('unknown type (99) → unknown', () async {
      expect(await typeFor(99), 'unknown');
    });
  });

  group('ValhallaRoutingEngine — polyline6 decoding', () {
    test('decodes polyline6 to non-empty shape', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(shape: 'o}@o}@o}@o}@'),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.shape.length, greaterThanOrEqualTo(2));
      // Polyline6 divides by 1e6 — values are 10x smaller than polyline5.
      // Verify coordinates are finite numbers (test fixture is synthetic).
      for (final point in result.shape) {
        expect(point.latitude.isFinite, isTrue);
        expect(point.longitude.isFinite, isTrue);
      }

      await engine.dispose();
    });

    test('empty shape produces empty points', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(
          shape: '',
          maneuvers: [
            {
              'instruction': 'Test',
              'type': 1,
              'length': 1.0,
              'time': 60,
              'begin_shape_index': 0,
            },
          ],
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.shape, isEmpty);

      await engine.dispose();
    });

    test(
      'polyline6 and polyline5 produce different coordinates for same bytes',
      () async {
        // The same encoded string should yield different coordinates at
        // precision 5 (1e5) vs precision 6 (1e6). Valhalla uses 6.
        final valhallaEngine = ValhallaRoutingEngine(
          baseUrl: 'http://test',
          client: valhallaClient(shape: '_p~iF~ps|U'),
        );
        final valhallaResult = await valhallaEngine.calculateRoute(_request);

        final osrmEngine = OsrmRoutingEngine(
          baseUrl: 'http://test',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'code': 'Ok',
                'routes': [
                  {
                    'geometry': '_p~iF~ps|U',
                    'distance': 100,
                    'duration': 10,
                    'legs': [
                      {
                        'steps': [
                          {
                            'name': '',
                            'distance': 100,
                            'duration': 10,
                            'maneuver': {
                              'type': 'depart',
                              'location': [0, 0],
                            },
                          },
                        ],
                      },
                    ],
                  },
                ],
              }),
              200,
            ),
          ),
        );
        final osrmResult = await osrmEngine.calculateRoute(_request);

        // Both decode one point, but coordinates differ by factor of 10.
        expect(valhallaResult.shape, isNotEmpty);
        expect(osrmResult.shape, isNotEmpty);
        expect(
          valhallaResult.shape[0].latitude,
          isNot(closeTo(osrmResult.shape[0].latitude, 0.001)),
        );

        await valhallaEngine.dispose();
        await osrmEngine.dispose();
      },
    );
  });

  group('ValhallaRoutingEngine — request body', () {
    test('POST body includes costing and directions_options', () async {
      Map<String, dynamic>? capturedBody;

      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'trip': {
                'summary': {'length': 1.0, 'time': 60},
                'legs': [
                  {
                    'shape': 'o}@o}@',
                    'maneuvers': [
                      {
                        'instruction': 'Go',
                        'type': 1,
                        'length': 1.0,
                        'time': 60,
                        'begin_shape_index': 0,
                      },
                    ],
                  },
                ],
              },
            }),
            200,
          );
        }),
      );

      await engine.calculateRoute(_request);

      expect(capturedBody, isNotNull);
      expect(capturedBody!['costing'], 'auto');
      expect(capturedBody!['locations'], isList);
      expect((capturedBody!['locations'] as List).length, 2);
      expect(capturedBody!['directions_options']['language'], 'ja-JP');
      expect(capturedBody!['directions_options']['units'], 'kilometers');
      expect(capturedBody!['costing_options']['auto']['use_highways'], 0.8);
      expect(capturedBody!['costing_options']['auto']['use_tolls'], 0.5);

      await engine.dispose();
    });
  });

  group('ValhallaRoutingEngine — error handling', () {
    test('JSON error body extracts error field', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'error': 'No route found'}), 400),
        ),
      );

      expect(
        () => engine.calculateRoute(_request),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.toString(),
            'message',
            contains('No route found'),
          ),
        ),
      );

      await engine.dispose();
    });

    test('non-JSON error body uses raw body', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('Bad Gateway', 502)),
      );

      expect(
        () => engine.calculateRoute(_request),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.toString(),
            'message',
            contains('Bad Gateway'),
          ),
        ),
      );

      await engine.dispose();
    });

    test('empty legs throws RoutingException', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'trip': {
                'summary': {'length': 0, 'time': 0},
                'legs': <dynamic>[],
              },
            }),
            200,
          ),
        ),
      );

      expect(
        () => engine.calculateRoute(_request),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    test('network error throws RoutingException', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient(
          (_) async => throw http.ClientException('conn refused'),
        ),
      );

      expect(
        () => engine.calculateRoute(_request),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    // An unresolvable begin_shape_index is absence of a maneuver position —
    // never Null Island. Up to 0.5.0 the case below silently produced
    // LatLng(0, 0), a real coordinate in the Gulf of Guinea, presented as
    // the maneuver's place. 0.5.1 skips the unlocatable maneuver instead.
    test(
      'begin_shape_index beyond decoded points SKIPS the maneuver (never 0,0)',
      () async {
        final engine = ValhallaRoutingEngine(
          baseUrl: 'http://test',
          client: valhallaClient(
            shape: 'o}@o}@',
            maneuvers: [
              {
                'instruction': 'Test',
                'type': 1,
                'length': 1.0,
                'time': 60,
                'begin_shape_index': 999,
              },
            ],
          ),
        );

        final result = await engine.calculateRoute(_request);

        // The unlocatable maneuver is dropped, not given a fabricated
        // position.
        expect(result.maneuvers, isEmpty);
        expect(
          result.maneuvers.map((m) => m.position),
          isNot(contains(const LatLng(0, 0))),
        );
        // Route-level fields are unaffected by the skip.
        expect(result.shape, isNotEmpty);
        expect(result.totalDistanceKm, closeTo(25.7, 0.01));

        await engine.dispose();
      },
    );

    test(
      'one located and one unlocated maneuver yields only the located one',
      () async {
        final engine = ValhallaRoutingEngine(
          baseUrl: 'http://test',
          client: valhallaClient(
            shape: 'o}@o}@',
            maneuvers: [
              {
                'instruction': 'Real',
                'type': 1,
                'length': 1.0,
                'time': 60,
                'begin_shape_index': 0,
              },
              // Unlocated: index points past the decoded polyline.
              {
                'instruction': 'Ghost',
                'type': 2,
                'length': 0.5,
                'time': 30,
                'begin_shape_index': 999,
              },
            ],
          ),
        );

        final result = await engine.calculateRoute(_request);

        expect(result.maneuvers, hasLength(1));
        expect(result.maneuvers.single.instruction, 'Real');
        // NO maneuver sits at Null Island.
        expect(
          result.maneuvers.map((m) => m.position),
          isNot(contains(const LatLng(0, 0))),
        );

        await engine.dispose();
      },
    );

    test('missing begin_shape_index skips the maneuver (never the route start)',
        () async {
      // Previously a missing index defaulted to 0 — silently claiming the
      // maneuver happens at the route origin. An unstated index is not
      // "at the start".
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(
          shape: 'o}@o}@',
          maneuvers: [
            {'instruction': 'Test', 'type': 1, 'length': 1.0, 'time': 60},
          ],
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.maneuvers, isEmpty);

      await engine.dispose();
    });

    test('negative begin_shape_index skips the maneuver (never throws)',
        () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(
          shape: 'o}@o}@',
          maneuvers: [
            {
              'instruction': 'Test',
              'type': 1,
              'length': 1.0,
              'time': 60,
              'begin_shape_index': -1,
            },
          ],
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.maneuvers, isEmpty);

      await engine.dispose();
    });
  });

  group('ValhallaRoutingEngine — summary and distance', () {
    test('distance is in kilometers (Valhalla native unit)', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(length: 42.5, time: 2400),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.totalDistanceKm, closeTo(42.5, 0.01));

      await engine.dispose();
    });

    test('summary format is correct', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaClient(length: 25.7, time: 1800),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.summary, '25.7 km, 30 min');

      await engine.dispose();
    });

    // Mutation guard: reverting utf8.decode(bodyBytes) → response.body makes
    // THIS test fail. Valhalla returns fully-localized instruction text
    // (Japanese via directions_options.language), so a charset-LESS server
    // mojibakes the entire narration — a larger exposure than OSRM's
    // street names.
    test('Japanese instructions survive a charset-less server (UTF-8 guard)',
        () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'trip': {
                'summary': {'length': 5.0, 'time': 300},
                'legs': [
                  {
                    'shape': 'o}@o}@o}@o}@',
                    'maneuvers': [
                      {
                        'instruction': '国道153号を直進します。',
                        'type': 8,
                        'length': 5.0,
                        'time': 300,
                        'begin_shape_index': 0,
                      },
                    ],
                  },
                ],
              },
            })),
            200,
            // Deliberately NO content-type: a missing/mis-declared type
            // decodes response.body as Latin-1 (http defaults JSON to UTF-8
            // only when the type says json) — the misconfigured-proxy case.
            headers: {},
          );
        }),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.maneuvers.first.instruction, '国道153号を直進します。');

      await engine.dispose();
    });
  });
  group('ValhallaRoutingEngine — absent summary is not a measured zero', () {
    // Absence of a length is absence of a measurement — never "0.0 km, 0 min".
    // This file already enforces that contract for maneuver positions
    // ("missing begin_shape_index yields NO position"); it had never been
    // carried across to the two numbers the driver actually hears. Worse than
    // the OSRM twin: an entirely absent `summary` object coalesced to `{}`,
    // so a response carrying no summary at all produced a zero-length route —
    // while a missing `trip` and missing `legs` both throw, two lines above.
    MockClient valhallaWithoutSummary({bool dropSummary = false, List<String> omit = const []}) =>
        MockClient((_) async {
      final summary = <String, dynamic>{'length': 1.0, 'time': 60};
      for (final k in omit) {
        summary.remove(k);
      }
      final trip = <String, dynamic>{
        'legs': [
          {
            'shape': 'o}@o}@o}@o}@',
            'maneuvers': <Map<String, dynamic>>[],
          },
        ],
      };
      if (!dropSummary) trip['summary'] = summary;
      return http.Response(jsonEncode({'trip': trip}), 200);
    });

    test('absent length is refused, never rendered as 0.0 km', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaWithoutSummary(omit: ['length']),
      );
      await expectLater(
        () => engine.calculateRoute(_request),
        throwsA(isA<RoutingException>()),
      );
      await engine.dispose();
    });

    test('absent time is refused, never rendered as 0 min', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaWithoutSummary(omit: ['time']),
      );
      await expectLater(
        () => engine.calculateRoute(_request),
        throwsA(isA<RoutingException>()),
      );
      await engine.dispose();
    });

    test('an entirely absent summary object is refused', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaWithoutSummary(dropSummary: true),
      );
      await expectLater(
        () => engine.calculateRoute(_request),
        throwsA(isA<RoutingException>()),
      );
      await engine.dispose();
    });

    // The loom refuses the FALSE thread, not the whole cloth.
    test('a present summary is unaffected', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: valhallaWithoutSummary(),
      );
      final result = await engine.calculateRoute(_request);
      expect(result.totalDistanceKm, closeTo(1.0, 0.001));
      expect(result.totalTimeSeconds, closeTo(60, 0.001));
      await engine.dispose();
    });
  });

}
