/// OsrmRoutingEngine edge-case tests — modifier mapping, instruction building,
/// polyline5 decoding, and response parsing edge cases.
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

/// Builds a MockClient returning a valid OSRM route response with
/// configurable steps.
MockClient _osrmClient({
  required List<Map<String, dynamic>> steps,
  String geometry = '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
  double distance = 25700,
  double duration = 1800,
}) {
  return MockClient((request) async {
    // Encode as UTF-8 bytes with an explicit charset, exactly as a real OSRM
    // server returns — so Japanese street names survive the round trip
    // (http.Response(String, ...) would default to Latin-1 and mangle them).
    return http.Response.bytes(
      utf8.encode(
        jsonEncode({
          'code': 'Ok',
          'routes': [
            {
              'geometry': geometry,
              'distance': distance,
              'duration': duration,
              'legs': [
                {'steps': steps},
              ],
            },
          ],
        }),
      ),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

/// Single step fixture with configurable maneuver fields.
Map<String, dynamic> _step({
  String name = '',
  String type = 'turn',
  String modifier = '',
  double distance = 1000,
  double duration = 60,
  List<double>? location,
}) {
  return {
    'name': name,
    'distance': distance,
    'duration': duration,
    'maneuver': {
      'type': type,
      'modifier': modifier,
      'location': location ?? [136.88, 35.17],
    },
  };
}

const _nagoya = LatLng(35.17, 136.88);
const _okazaki = LatLng(34.97, 137.17);
const _request = RouteRequest(origin: _nagoya, destination: _okazaki);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OsrmRoutingEngine — constructor defaults', () {
    test('default baseUrl is localhost:5000', () {
      final engine = OsrmRoutingEngine();
      expect(engine.baseUrl, 'http://localhost:5000');
    });

    test('custom baseUrl is preserved', () {
      final engine = OsrmRoutingEngine(baseUrl: 'http://custom:9999');
      expect(engine.baseUrl, 'http://custom:9999');
    });
  });

  group('OsrmRoutingEngine — isAvailable', () {
    test('returns true on 200', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('ok', 200)),
      );
      expect(await engine.isAvailable(), isTrue);
      await engine.dispose();
    });

    test('returns false on non-200', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('error', 503)),
      );
      expect(await engine.isAvailable(), isFalse);
      await engine.dispose();
    });

    test('returns false on network error', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => throw http.ClientException('refused')),
      );
      expect(await engine.isAvailable(), isFalse);
      await engine.dispose();
    });
  });

  group('OsrmRoutingEngine — modifier-to-type mapping', () {
    Future<String> typeFor({String type = 'turn', String modifier = ''}) async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [_step(type: type, modifier: modifier)],
        ),
      );
      final result = await engine.calculateRoute(_request);
      await engine.dispose();
      return result.maneuvers.first.type;
    }

    test('depart → depart', () async {
      expect(await typeFor(type: 'depart'), 'depart');
    });

    test('arrive → arrive', () async {
      expect(await typeFor(type: 'arrive'), 'arrive');
    });

    test('roundabout → roundabout_enter', () async {
      expect(await typeFor(type: 'roundabout'), 'roundabout_enter');
    });

    test('rotary → roundabout_enter', () async {
      expect(await typeFor(type: 'rotary'), 'roundabout_enter');
    });

    test('merge → merge', () async {
      expect(await typeFor(type: 'merge'), 'merge');
    });

    test('on ramp + right → ramp_right', () async {
      expect(await typeFor(type: 'on ramp', modifier: 'right'), 'ramp_right');
    });

    test('on ramp + left → ramp_left', () async {
      expect(await typeFor(type: 'on ramp', modifier: 'left'), 'ramp_left');
    });

    test('off ramp + right → ramp_right', () async {
      expect(await typeFor(type: 'off ramp', modifier: 'right'), 'ramp_right');
    });

    test('modifier left → left', () async {
      expect(await typeFor(modifier: 'left'), 'left');
    });

    test('modifier slight left → slight_left', () async {
      expect(await typeFor(modifier: 'slight left'), 'slight_left');
    });

    test('modifier sharp left → sharp_left', () async {
      expect(await typeFor(modifier: 'sharp left'), 'sharp_left');
    });

    test('modifier right → right', () async {
      expect(await typeFor(modifier: 'right'), 'right');
    });

    test('modifier slight right → slight_right', () async {
      expect(await typeFor(modifier: 'slight right'), 'slight_right');
    });

    test('modifier sharp right → sharp_right', () async {
      expect(await typeFor(modifier: 'sharp right'), 'sharp_right');
    });

    test('modifier straight → straight', () async {
      expect(await typeFor(modifier: 'straight'), 'straight');
    });

    test('modifier uturn → u_turn_left', () async {
      expect(await typeFor(modifier: 'uturn'), 'u_turn_left');
    });

    test('unknown modifier with type → falls back to type', () async {
      expect(
        await typeFor(type: 'notification', modifier: 'unknown_thing'),
        'notification',
      );
    });

    test('empty modifier and empty type → proceed (never a fabricated straight)', () async {
      expect(await typeFor(type: '', modifier: ''), 'proceed');
    });

    test('ramp without a stated side → side-less ramp (never fabricates left)', () async {
      expect(await typeFor(type: 'on ramp', modifier: ''), 'ramp');
      expect(await typeFor(type: 'off ramp', modifier: 'straight'), 'ramp');
    });

    test('exit roundabout → roundabout_exit', () async {
      expect(await typeFor(type: 'exit roundabout'), 'roundabout_exit');
      expect(await typeFor(type: 'exit rotary'), 'roundabout_exit');
    });
  });

  group('OsrmRoutingEngine — instruction building', () {
    // These tests exercise the ENGLISH builder, so they request English
    // explicitly — the request default is now 'ja-JP' (HER's locale).
    Future<String> instructionFor({
      String name = '',
      String type = 'turn',
      String modifier = '',
      String language = 'en',
    }) async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [_step(name: name, type: type, modifier: modifier)],
        ),
      );
      final result = await engine.calculateRoute(
        RouteRequest(
          origin: _nagoya,
          destination: _okazaki,
          language: language,
        ),
      );
      await engine.dispose();
      return result.maneuvers.first.instruction;
    }

    test('depart with name → "Depart on [name]"', () async {
      expect(
        await instructionFor(type: 'depart', name: 'Route 153'),
        'Depart on Route 153',
      );
    });

    test('depart without name → "Depart"', () async {
      expect(await instructionFor(type: 'depart'), 'Depart');
    });

    test('arrive → "Arrive at destination"', () async {
      expect(await instructionFor(type: 'arrive'), 'Arrive at destination');
    });

    test('turn with modifier and name', () async {
      expect(
        await instructionFor(
          type: 'turn',
          modifier: 'slight left',
          name: 'Meiji Dori',
        ),
        'Slight left onto Meiji Dori',
      );
    });

    test('turn with modifier, no name', () async {
      expect(
        await instructionFor(type: 'turn', modifier: 'sharp right'),
        'Sharp right',
      );
    });

    // HER default locale end-to-end through the real engine: the request
    // language defaults to 'ja-JP', so instructions must come back Japanese —
    // this is the gap the fix closes (OSRM used to ignore request.language).
    test('ja-JP default → depart in Japanese', () async {
      expect(
        await instructionFor(type: 'depart', name: 'Route 153', language: 'ja-JP'),
        'Route 153を出発',
      );
    });

    test('ja-JP default → turn in Japanese', () async {
      expect(
        await instructionFor(type: 'turn', modifier: 'left', name: '国道153号', language: 'ja-JP'),
        '国道153号方面へ左折',
      );
    });

    test('ja-JP default → arrive in Japanese', () async {
      expect(
        await instructionFor(type: 'arrive', language: 'ja-JP'),
        '目的地に到着',
      );
    });

    test('unrecognized locale still yields English (graceful, no regression)', () async {
      expect(
        await instructionFor(type: 'depart', name: 'Route 153', language: 'fr-FR'),
        'Depart on Route 153',
      );
    });

    // Mutation guard: reverting utf8.decode(bodyBytes) → response.body makes
    // THIS test fail (a charset-LESS server + a Japanese street name is the
    // exact case the fix targets; response.body would decode it as Latin-1).
    test('Japanese street names survive a charset-less server (UTF-8 guard)', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((request) async {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'geometry': '_p~iF~ps|U',
                  'distance': 1000.0,
                  'duration': 60.0,
                  'legs': [
                    {
                      'steps': [_step(name: '国道153号', type: 'depart')],
                    },
                  ],
                },
              ],
            })),
            200,
            // Deliberately NO content-type at all: package:http defaults
            // JSON-typed bodies to UTF-8 since 1.x, but a missing/mis-declared
            // content-type still decodes response.body as Latin-1 and mangles
            // the kanji — the real-world misconfigured-proxy case.
            headers: {},
          );
        }),
      );
      final result = await engine.calculateRoute(
        RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      await engine.dispose();
      expect(result.maneuvers.first.instruction, '国道153号を出発');
    });

    // Mutation guard: replacing the engine's roundaboutExit threading with
    // null makes THIS test fail — the exit ordinal is safety-relevant (a
    // multi-exit roundabout in low visibility needs the ordinal), and the
    // localizer unit test alone cannot prove the OSRM json→instruction wiring.
    test('OSRM maneuver.exit reaches the ja instruction (exit-ordinal guard)', () async {
      final step = _step(name: '国道153号', type: 'roundabout');
      (step['maneuver'] as Map<String, dynamic>)['exit'] = 2;
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(steps: [step]),
      );
      final result = await engine.calculateRoute(
        RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      await engine.dispose();
      expect(result.maneuvers.first.instruction, contains('2番目の出口'));
      expect(
        result.maneuvers.first.instruction,
        'ロータリーに入り2番目の出口で国道153号方面へ進む',
      );
    });
  });

  group('OsrmRoutingEngine — polyline5 decoding', () {
    test('decodes known polyline to correct coordinates', () async {
      // '_p~iF~ps|U_ulLnnqC_mqNvxq`@' is the standard Google polyline example.
      // Expected: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [
            _step(type: 'depart'),
            _step(type: 'arrive'),
          ],
          geometry: '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.shape.length, 3);
      expect(result.shape[0].latitude, closeTo(38.5, 0.001));
      expect(result.shape[0].longitude, closeTo(-120.2, 0.001));
      expect(result.shape[1].latitude, closeTo(40.7, 0.01));
      expect(result.shape[1].longitude, closeTo(-120.95, 0.01));

      await engine.dispose();
    });

    test('empty geometry produces empty shape', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [_step(type: 'depart')],
          geometry: '',
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.shape, isEmpty);

      await engine.dispose();
    });
  });

  group('OsrmRoutingEngine — response edge cases', () {
    test('empty routes array throws RoutingException', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'Ok', 'routes': <dynamic>[]}),
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

    test('null routes field throws RoutingException', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient(
          (_) async => http.Response(jsonEncode({'code': 'Ok'}), 200),
        ),
      );

      expect(
        () => engine.calculateRoute(_request),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    test('network error throws RoutingException', () async {
      final engine = OsrmRoutingEngine(
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

    test('missing maneuver location defaults to (0, 0)', () async {
      final engine = OsrmRoutingEngine(
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
                          'name': 'Test',
                          'distance': 100,
                          'duration': 10,
                          'maneuver': {'type': 'depart'},
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

      final result = await engine.calculateRoute(_request);
      expect(result.maneuvers.first.position, const LatLng(0, 0));

      await engine.dispose();
    });

    test('distance is converted from meters to kilometers', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [_step(type: 'depart')],
          distance: 15000,
          duration: 900,
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.totalDistanceKm, closeTo(15.0, 0.01));

      await engine.dispose();
    });

    test('summary format is correct', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [_step(type: 'depart')],
          distance: 25700,
          duration: 1800,
        ),
      );

      final result = await engine.calculateRoute(_request);
      expect(result.summary, '25.7 km, 30 min');

      await engine.dispose();
    });
  });
}
