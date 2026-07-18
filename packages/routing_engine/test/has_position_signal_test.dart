import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

/// 0.3.2 adds `RouteManeuver.hasPosition`: it must be `true` for a maneuver
/// whose position was resolved from the response, and `false` for one whose
/// position the engine had to substitute (clamp) because it could not resolve
/// the real one. These tests prove the signal FIRES both ways.
void main() {
  group('Valhalla — hasPosition signal', () {
    // '_izlhA_c`|oO' decodes to a short polyline; index 0 is inside it, index
    // 999 is far past it. A resolvable maneuver -> hasPosition true; an
    // out-of-range begin_shape_index -> clamped -> hasPosition false.
    MockClient valhalla(List<Map<String, dynamic>> maneuvers) =>
        MockClient((_) async => http.Response(
              jsonEncode({
                'trip': {
                  'summary': {'length': 5.0, 'time': 300},
                  'legs': [
                    {
                      'shape': '_izlhA_c`|oO_seK_seK',
                      'maneuvers': maneuvers,
                    },
                  ],
                },
              }),
              200,
            ));

    const request = RouteRequest(
      origin: LatLng(35.17, 136.88),
      destination: LatLng(34.97, 137.17),
    );

    test('resolved begin_shape_index -> hasPosition true', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla([
          {
            'instruction': 'Drive east.',
            'type': 1,
            'length': 5.0,
            'time': 300,
            'begin_shape_index': 0,
          },
        ]),
      );
      final result = await engine.calculateRoute(request);
      expect(result.maneuvers, isNotEmpty);
      expect(result.maneuvers.first.hasPosition, isTrue);
      expect(result.maneuvers.first.positionResolved, isTrue);
    });

    test('out-of-range begin_shape_index -> hasPosition false, but position '
        'is still a non-null LatLng on the route', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla([
          {
            'instruction': 'Turn somewhere unknowable.',
            'type': 1,
            'length': 5.0,
            'time': 300,
            'begin_shape_index': 999, // past the decoded shape
          },
        ]),
      );
      final result = await engine.calculateRoute(request);
      expect(result.maneuvers, isNotEmpty);
      final m = result.maneuvers.first;
      expect(m.hasPosition, isFalse, reason: 'clamped position must be flagged');
      // Backward-compat: position is STILL a usable non-null LatLng (the clamp),
      // never Null Island.
      expect(m.position, isA<LatLng>());
      expect(m.position.latitude == 0 && m.position.longitude == 0, isFalse);
      expect(m.toString(), contains('position unknown'));
    });

    test('missing begin_shape_index (silent "at route start") -> hasPosition '
        'false', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: valhalla([
          {
            'instruction': 'Depart.',
            'type': 1,
            'length': 5.0,
            'time': 300,
            // no begin_shape_index at all
          },
        ]),
      );
      final result = await engine.calculateRoute(request);
      expect(result.maneuvers, isNotEmpty);
      expect(result.maneuvers.first.hasPosition, isFalse);
    });
  });

  group('OSRM — hasPosition signal', () {
    const request = RouteRequest(
      origin: LatLng(39.72, 140.10),
      destination: LatLng(39.75, 140.15),
    );

    test('present maneuver.location -> hasPosition true; missing location on a '
        'later step -> hasPosition false (clamped, not fabricated)', () async {
      final client = MockClient((_) async => http.Response(
            jsonEncode({
              'code': 'Ok',
              'routes': [
                {
                  // A real 2-point geometry so a clamp target exists.
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
                          // no location -> engine must clamp, and flag it
                          'maneuver': {},
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

      final engine =
          OsrmRoutingEngine(baseUrl: 'https://x', client: client);
      final result = await engine.calculateRoute(request);
      expect(result.maneuvers.length, greaterThanOrEqualTo(2));
      expect(result.maneuvers[0].hasPosition, isTrue);
      expect(result.maneuvers[1].hasPosition, isFalse);
      // The clamped one is still a real, non-null, non-Null-Island coordinate.
      expect(
        result.maneuvers[1].position.latitude == 0 &&
            result.maneuvers[1].position.longitude == 0,
        isFalse,
      );
    });
  });
}
