/// FEM-7 — Routing engine contract tests.
///
/// Implementation-agnostic tests that verify the RoutingEngine interface
/// contract. Both OSRM and Valhalla must satisfy these invariants.
///
/// Tests:
///   - Contract: info returns non-empty name, calculateRoute returns
///     RouteResult with shape/maneuvers/engineInfo, dispose completes
///   - OSRM contract compliance
///   - Valhalla contract compliance
///   - RouteResult invariants (hasGeometry, ETA, Equatable)
///   - EngineInfo invariants (name, toString)
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

/// OSRM response fixture — valid Nagoya → Okazaki route.
http.Client _osrmSuccessClient() => MockClient((request) async {
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

/// Valhalla response fixture — valid Nagoya → Okazaki route.
http.Client _valhallaSuccessClient() => MockClient((request) async {
      return http.Response(
        jsonEncode({
          'trip': {
            'summary': {'length': 25.7, 'time': 1800},
            'legs': [
              {
                'shape': '_izlhA_c`|oO_seK_seK',
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

const _nagoya = LatLng(35.17, 136.88);
const _okazaki = LatLng(34.97, 137.17);

/// Runs the full contract suite against any [RoutingEngine].
///
/// Every implementation must satisfy these invariants:
///   1. info.name is non-empty
///   2. calculateRoute returns a RouteResult with matching engineInfo
///   3. RouteResult contains shape, maneuvers, distance, time
///   4. dispose completes without error
void runContractTests(
  String engineName,
  RoutingEngine Function() factory,
) {
  group('$engineName — RoutingEngine contract', () {
    late RoutingEngine engine;

    setUp(() {
      engine = factory();
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('info.name is non-empty', () {
      expect(engine.info.name, isNotEmpty);
    });

    test('info.name matches engine identity', () {
      expect(engine.info.name.toLowerCase(), contains(engineName.toLowerCase()));
    });

    test('calculateRoute returns RouteResult', () async {
      final result = await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      expect(result, isA<RouteResult>());
    });

    test('RouteResult.engineInfo matches engine.info', () async {
      final result = await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      expect(result.engineInfo.name, engine.info.name);
    });

    test('RouteResult has non-negative distance and time', () async {
      final result = await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      expect(result.totalDistanceKm, greaterThanOrEqualTo(0));
      expect(result.totalTimeSeconds, greaterThanOrEqualTo(0));
    });

    test('RouteResult has shape with at least 2 points', () async {
      final result = await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      expect(result.hasGeometry, isTrue);
      expect(result.shape.length, greaterThanOrEqualTo(2));
    });

    test('RouteResult has at least one maneuver', () async {
      final result = await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      expect(result.maneuvers, isNotEmpty);
    });

    test('maneuvers have valid fields', () async {
      final result = await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      for (final m in result.maneuvers) {
        expect(m.type, isNotEmpty);
        expect(m.lengthKm, greaterThanOrEqualTo(0));
        expect(m.timeSeconds, greaterThanOrEqualTo(0));
      }
    });

    test('dispose can be called after calculateRoute', () async {
      await engine.calculateRoute(
        const RouteRequest(origin: _nagoya, destination: _okazaki),
      );
      // dispose is called in tearDown — this test verifies no exception
    });
  });
}

void main() {
  // =========================================================================
  // Run contract tests against both engine implementations
  // =========================================================================

  runContractTests(
    'osrm',
    () => OsrmRoutingEngine(
      baseUrl: 'http://test',
      client: _osrmSuccessClient(),
    ),
  );

  runContractTests(
    'valhalla',
    () => ValhallaRoutingEngine(
      baseUrl: 'http://test',
      client: _valhallaSuccessClient(),
    ),
  );

  // =========================================================================
  // Cross-engine consistency
  // =========================================================================
  group('Cross-engine consistency', () {
    test('both engines produce RouteResult for the same request', () async {
      final osrm = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: _osrmSuccessClient(),
      );
      final valhalla = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: _valhallaSuccessClient(),
      );

      const request = RouteRequest(origin: _nagoya, destination: _okazaki);

      final osrmResult = await osrm.calculateRoute(request);
      final valhallaResult = await valhalla.calculateRoute(request);

      // Both produce valid results
      expect(osrmResult.hasGeometry, isTrue);
      expect(valhallaResult.hasGeometry, isTrue);

      // Engine info differs
      expect(osrmResult.engineInfo.name, isNot(valhallaResult.engineInfo.name));

      await osrm.dispose();
      await valhalla.dispose();
    });
  });

  // =========================================================================
  // Error contract: engines must throw RoutingException on failure
  // =========================================================================
  group('Error contract', () {
    test('OSRM throws RoutingException on server error', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('error', 500)),
      );
      expect(
        () => engine.calculateRoute(
          const RouteRequest(origin: _nagoya, destination: _okazaki),
        ),
        throwsA(isA<RoutingException>()),
      );
      await engine.dispose();
    });

    test('Valhalla throws RoutingException on server error', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://test',
        client: MockClient((_) async => http.Response('error', 500)),
      );
      expect(
        () => engine.calculateRoute(
          const RouteRequest(origin: _nagoya, destination: _okazaki),
        ),
        throwsA(isA<RoutingException>()),
      );
      await engine.dispose();
    });
  });
}
