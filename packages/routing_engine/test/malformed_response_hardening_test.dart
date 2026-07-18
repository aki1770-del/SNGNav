import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

/// 0.3.3 hardening: malformed-but-plausible routing responses must NEVER throw
/// a raw crash out of `calculateRoute`. Each of these threw
/// RangeError/TypeError/FormatException up to 0.3.1. The safe outcome is either
/// a usable RouteResult (flagged unresolved) or a RoutingException the consumer
/// already catches — never a raw crash, never a fabricated (0,0).
void main() {
  const request = RouteRequest(
    origin: LatLng(35.17, 136.88),
    destination: LatLng(34.97, 137.17),
  );

  MockClient valhalla(Object maneuver, {String shape = '_izlhA_c`|oO_seK_seK'}) =>
      MockClient((_) async => http.Response(
            jsonEncode({
              'trip': {
                'summary': {'length': 5.0, 'time': 300},
                'legs': [
                  {
                    'shape': shape,
                    'maneuvers': [maneuver],
                  },
                ],
              },
            }),
            200,
          ));

  group('Valhalla — no crash on malformed maneuvers', () {
    test('V-1 negative begin_shape_index -> no throw, real non-(0,0) point, '
        'flagged unresolved', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla({
          'instruction': 'x',
          'type': 1,
          'length': 5.0,
          'time': 300,
          'begin_shape_index': -1,
        }),
      );
      final result = await engine.calculateRoute(request); // must not throw
      final m = result.maneuvers.single;
      expect(m.hasPosition, isFalse);
      expect(m.position.latitude == 0 && m.position.longitude == 0, isFalse);
    });

    test('V-2 begin_shape_index as a JSON double -> no throw', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla({
          'instruction': 'x',
          'type': 1,
          'length': 5.0,
          'time': 300,
          'begin_shape_index': 1.0,
        }),
      );
      final result = await engine.calculateRoute(request);
      expect(result.maneuvers.single.hasPosition, isTrue); // 1.0 -> index 1, in range
    });

    test('V-3 maneuver type as a JSON double -> no throw', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla({
          'instruction': 'x',
          'type': 6.0, // -> 'right'
          'length': 5.0,
          'time': 300,
          'begin_shape_index': 0,
        }),
      );
      final result = await engine.calculateRoute(request);
      expect(result.maneuvers.single.type, 'right');
    });
  });

  group('OSRM — no crash on malformed location', () {
    test('O-2 non-numeric maneuver.location -> no throw, unresolved+clamped',
        () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  'geometry': 'yzvpFucvbMoBc@',
                  'distance': 200,
                  'duration': 120,
                  'legs': [
                    {
                      'steps': [
                        {
                          'maneuver': {
                            'location': [140.10, 39.72],
                          },
                          'distance': 100,
                          'duration': 60,
                        },
                        {
                          'maneuver': {
                            'location': ['a', 'b'], // malformed
                          },
                          'distance': 100,
                          'duration': 60,
                        },
                      ],
                    },
                  ],
                },
              ],
            }),
            200,
          ));
      final engine = OsrmRoutingEngine(baseUrl: 'https://x', client: client);
      final result = await engine.calculateRoute(request); // must not throw
      expect(result.maneuvers.length, 2);
      expect(result.maneuvers[1].hasPosition, isFalse);
      expect(
        result.maneuvers[1].position.latitude == 0 &&
            result.maneuvers[1].position.longitude == 0,
        isFalse,
      );
    });
  });

  group('Both — non-JSON body on HTTP 200 -> RoutingException, not a raw crash',
      () {
    test('Valhalla', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: MockClient((_) async =>
            http.Response('<html>captive portal</html>', 200)),
      );
      expect(
        () => engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test('OSRM', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'https://x',
        client: MockClient((_) async =>
            http.Response('<html>captive portal</html>', 200)),
      );
      expect(
        () => engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test('OSRM — JSON array (wrong shape) on 200 -> RoutingException', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'https://x',
        client: MockClient((_) async => http.Response('[1,2,3]', 200)),
      );
      expect(
        () => engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });
  });

  group('crash backstop — residual parse throws become RoutingException', () {
    test('Valhalla — a non-object element in legs -> RoutingException, not a '
        'raw TypeError', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'trip': {
                  'summary': {'length': 5.0, 'time': 300},
                  'legs': ['this is not a leg object'],
                },
              }),
              200,
            )),
      );
      expect(
        () => engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test('Valhalla — instruction sent as a number -> RoutingException, not a '
        'raw cast crash', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla({
          'instruction': 123, // not a String
          'type': 1,
          'length': 5.0,
          'time': 300,
          'begin_shape_index': 0,
        }),
      );
      expect(
        () => engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test('OSRM — a step name sent as a number -> RoutingException, not a raw '
        'cast crash', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'https://x',
        client: MockClient((_) async => http.Response(
              jsonEncode({
                'code': 'Ok',
                'routes': [
                  {
                    'geometry': 'yzvpFucvbMoBc@',
                    'distance': 200,
                    'duration': 120,
                    'legs': [
                      {
                        'steps': [
                          {
                            'name': 999, // not a String
                            'maneuver': {
                              'location': [140.10, 39.72],
                              'type': 'depart',
                            },
                            'distance': 100,
                            'duration': 60,
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
      expect(
        () => engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });
  });
}
