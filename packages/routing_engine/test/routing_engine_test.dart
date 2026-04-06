/// Routing engine unit tests — verifies OSRM and Valhalla response parsing,
/// polyline decoding, error handling, and model construction.
///
/// Tests:
///   - OSRM: response parsing, polyline5 decoding, error handling
///   - Valhalla: response parsing, polyline6 decoding, error handling
///   - RouteResult: model construction, ETA, hasGeometry
///   - RouteRequest: equality, default values
///   - RoutingException: message formatting
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

void main() {
  group('OsrmRoutingEngine', () {
    test('parses valid route response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'geometry': '_p~iF~ps|U_ulLnnqC_mqNvxq`@',
                'distance': 25700,
                'duration': 1800,
                'legs': [
                  {
                    'steps': [
                      {
                        'name': 'Route 153',
                        'distance': 25700,
                        'duration': 1800,
                        'maneuver': {
                          'type': 'depart',
                          'modifier': 'right',
                          'location': [136.88, 35.17],
                        },
                      },
                      {
                        'name': '',
                        'distance': 0,
                        'duration': 0,
                        'maneuver': {
                          'type': 'arrive',
                          'location': [137.17, 34.97],
                        },
                      },
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        );
      });

      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: client,
      );

      final result = await engine.calculateRoute(RouteRequest(
        origin: const LatLng(35.17, 136.88),
        destination: const LatLng(34.97, 137.17),
      ));

      expect(result.totalDistanceKm, closeTo(25.7, 0.1));
      expect(result.totalTimeSeconds, 1800);
      expect(result.maneuvers.length, 2);
      expect(result.maneuvers.first.type, 'depart');
      expect(result.maneuvers.last.type, 'arrive');
      expect(result.engineInfo.name, 'osrm');
      expect(result.hasGeometry, isTrue);

      await engine.dispose();
    });

    test('throws on HTTP error', () async {
      final client = MockClient((_) async => http.Response('Server Error', 500));
      final engine = OsrmRoutingEngine(baseUrl: 'http://test', client: client);

      expect(
        () => engine.calculateRoute(RouteRequest(
          origin: const LatLng(35.17, 136.88),
          destination: const LatLng(34.97, 137.17),
        )),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    test('throws on OSRM error code', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({'code': 'NoRoute', 'message': 'No route found'}),
          200,
        );
      });
      final engine = OsrmRoutingEngine(baseUrl: 'http://test', client: client);

      expect(
        () => engine.calculateRoute(RouteRequest(
          origin: const LatLng(35.17, 136.88),
          destination: const LatLng(34.97, 137.17),
        )),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    test('info returns osrm', () {
      final engine = OsrmRoutingEngine(baseUrl: 'http://test');
      expect(engine.info.name, 'osrm');
    });
  });

  group('ValhallaRoutingEngine', () {
    test('parses valid route response', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'trip': {
              'summary': {'length': 25.7, 'time': 1800},
              'legs': [
                {
                  'shape': 'o}@o}@o}@o}@',
                  'maneuvers': [
                    {
                      'instruction': 'Drive east.',
                      'type': 1,
                      'length': 25.7,
                      'time': 1800,
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

      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: client,
      );

      final result = await engine.calculateRoute(RouteRequest(
        origin: const LatLng(35.17, 136.88),
        destination: const LatLng(34.97, 137.17),
      ));

      expect(result.totalDistanceKm, closeTo(25.7, 0.1));
      expect(result.totalTimeSeconds, 1800);
      expect(result.maneuvers.length, 2);
      expect(result.maneuvers.first.type, 'depart');
      expect(result.maneuvers.last.type, 'arrive');
      expect(result.engineInfo.name, 'valhalla');

      await engine.dispose();
    });

    test('throws on HTTP error', () async {
      final client = MockClient((_) async {
        return http.Response(
          jsonEncode({'error': 'Bad request'}),
          400,
        );
      });
      final engine = ValhallaRoutingEngine(baseUrl: 'http://test', client: client);

      expect(
        () => engine.calculateRoute(RouteRequest(
          origin: const LatLng(35.17, 136.88),
          destination: const LatLng(34.97, 137.17),
        )),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    test('throws on missing trip field', () async {
      final client = MockClient((_) async {
        return http.Response(jsonEncode({}), 200);
      });
      final engine = ValhallaRoutingEngine(baseUrl: 'http://test', client: client);

      expect(
        () => engine.calculateRoute(RouteRequest(
          origin: const LatLng(35.17, 136.88),
          destination: const LatLng(34.97, 137.17),
        )),
        throwsA(isA<RoutingException>()),
      );

      await engine.dispose();
    });

    test('info returns valhalla', () {
      final engine = ValhallaRoutingEngine(baseUrl: 'http://test');
      expect(engine.info.name, 'valhalla');
    });
  });

  group('RouteResult', () {
    test('eta computes from totalTimeSeconds', () {
      const result = RouteResult(
        shape: [],
        maneuvers: [],
        totalDistanceKm: 10.0,
        totalTimeSeconds: 600,
        summary: '10 km, 10 min',
        engineInfo: EngineInfo(name: 'test'),
      );
      expect(result.eta.inMinutes, 10);
    });

    test('hasGeometry requires at least 2 points', () {
      const noGeom = RouteResult(
        shape: [],
        maneuvers: [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '',
        engineInfo: EngineInfo(name: 'test'),
      );
      expect(noGeom.hasGeometry, isFalse);

      final withGeom = RouteResult(
        shape: const [LatLng(0, 0), LatLng(1, 1)],
        maneuvers: const [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '',
        engineInfo: const EngineInfo(name: 'test'),
      );
      expect(withGeom.hasGeometry, isTrue);
    });

    test('route models expose value props and debug strings', () {
      const maneuver = RouteManeuver(
        index: 1,
        instruction: 'Turn right',
        type: 'right',
        lengthKm: 1.2,
        timeSeconds: 90,
        position: LatLng(35.1, 136.9),
      );
      const engine = EngineInfo(
        name: 'osrm',
        version: '1.0',
        queryLatency: Duration(milliseconds: 42),
      );
      const route = RouteResult(
        shape: [LatLng(35.1, 136.9), LatLng(35.2, 137.0)],
        maneuvers: [maneuver],
        totalDistanceKm: 12.34,
        totalTimeSeconds: 780,
        summary: 'Nagoya to Toyota',
        engineInfo: engine,
      );

      expect(
        maneuver.props,
        [1, 'Turn right', 'right', 1.2, 90, const LatLng(35.1, 136.9)],
      );
      expect(maneuver.toString(), contains('Turn right'));
      expect(engine.props, ['osrm', '1.0', const Duration(milliseconds: 42)]);
      expect(engine.toString(), 'EngineInfo(osrm v1.0, 42ms)');
      expect(route.props, [route.shape, route.maneuvers, 12.34, 780, 'Nagoya to Toyota', engine]);
      expect(route.toString(), 'RouteResult(12.3km, 13min, 2 pts, osrm)');
    });
  });

  group('RouteRequest', () {
    test('defaults to auto costing and ja-JP', () {
      const req = RouteRequest(
        origin: LatLng(35.17, 136.88),
        destination: LatLng(34.97, 137.17),
      );
      expect(req.costing, 'auto');
      expect(req.language, 'ja-JP');
    });

    test('equality works', () {
      const a = RouteRequest(
        origin: LatLng(35.17, 136.88),
        destination: LatLng(34.97, 137.17),
      );
      const b = RouteRequest(
        origin: LatLng(35.17, 136.88),
        destination: LatLng(34.97, 137.17),
      );
      expect(a, equals(b));
    });

    test('props include routing parameters', () {
      const req = RouteRequest(
        origin: LatLng(35.17, 136.88),
        destination: LatLng(34.97, 137.17),
        costing: 'truck',
        language: 'en-US',
      );

      expect(
        req.props,
        [
          const LatLng(35.17, 136.88),
          const LatLng(34.97, 137.17),
          'truck',
          'en-US',
        ],
      );
    });
  });

  group('RoutingException', () {
    test('toString includes message', () {
      const e = RoutingException('test error');
      expect(e.toString(), contains('test error'));
    });
  });
}
