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
    return http.Response(
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
      200,
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
    Future<String> typeFor({
      String type = 'turn',
      String modifier = '',
    }) async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(steps: [
          _step(type: type, modifier: modifier),
        ]),
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
      expect(
          await typeFor(type: 'off ramp', modifier: 'right'), 'ramp_right');
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
          'notification');
    });

    test('empty modifier and empty type → straight', () async {
      expect(await typeFor(type: '', modifier: ''), 'straight');
    });
  });

  group('OsrmRoutingEngine — instruction building', () {
    Future<String> instructionFor({
      String name = '',
      String type = 'turn',
      String modifier = '',
    }) async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(steps: [
          _step(name: name, type: type, modifier: modifier),
        ]),
      );
      final result = await engine.calculateRoute(_request);
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
      expect(
        await instructionFor(type: 'arrive'),
        'Arrive at destination',
      );
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
  });

  group('OsrmRoutingEngine — polyline5 decoding', () {
    test('decodes known polyline to correct coordinates', () async {
      // '_p~iF~ps|U_ulLnnqC_mqNvxq`@' is the standard Google polyline example.
      // Expected: (38.5, -120.2), (40.7, -120.95), (43.252, -126.453)
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmClient(
          steps: [_step(type: 'depart'), _step(type: 'arrive')],
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
        client: MockClient((_) async => http.Response(
              jsonEncode({'code': 'Ok', 'routes': []}),
              200,
            )),
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
        client: MockClient((_) async => http.Response(
              jsonEncode({'code': 'Ok'}),
              200,
            )),
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
        client:
            MockClient((_) async => throw http.ClientException('conn refused')),
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
        client: MockClient((_) async => http.Response(
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
            )),
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
