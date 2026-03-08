/// OsrmRoutingEngine unit tests — HTTP response parsing, polyline5
/// decoding, error handling, and engine-agnostic RouteResult output.
///
/// Uses a mock HTTP client — no Docker, no OSRM server required.
///
/// Sprint 7 Day 6 — OSRM integration (A63 §3.1, ADR-OL-1).
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:routing_engine/routing_engine.dart';

// ---------------------------------------------------------------------------
// Test data — realistic OSRM response for Nagoya → Toyota City
// ---------------------------------------------------------------------------

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);

/// Polyline5-encoded line for Nagoya → Toyota (simplified 3 points).
/// Encodes: (35.1709, 136.8815) → (35.1100, 137.0200) → (35.0504, 137.1566)
///
/// Encoding verified: each coordinate × 1e5, delta-encoded, varint with
/// sign inversion.
const _testPolyline5 = r'cituEktmbYr{Js`ZnsJwtY';

/// Minimal valid OSRM route response.
Map<String, dynamic> _validResponse({
  String geometry = _testPolyline5,
  double distance = 25700, // meters
  double duration = 1830, // seconds
  List<Map<String, dynamic>>? steps,
}) {
  return {
    'code': 'Ok',
    'routes': [
      {
        'geometry': geometry,
        'distance': distance,
        'duration': duration,
        'legs': [
          {
            'distance': distance,
            'duration': duration,
            'steps': steps ??
                [
                  {
                    'name': 'Route 153',
                    'distance': 12500.0,
                    'duration': 720.0,
                    'maneuver': {
                      'type': 'depart',
                      'modifier': '',
                      'location': [136.8815, 35.1709],
                    },
                  },
                  {
                    'name': 'Tokai-Kanjo Expressway',
                    'distance': 8200.0,
                    'duration': 600.0,
                    'maneuver': {
                      'type': 'turn',
                      'modifier': 'right',
                      'location': [137.0200, 35.1100],
                    },
                  },
                  {
                    'name': '',
                    'distance': 0.0,
                    'duration': 0.0,
                    'maneuver': {
                      'type': 'arrive',
                      'modifier': '',
                      'location': [137.1566, 35.0504],
                    },
                  },
                ],
          },
        ],
      },
    ],
  };
}

/// Create a MockClient that returns the given body for route requests.
MockClient _mockClient(Map<String, dynamic> responseBody,
    {int statusCode = 200}) {
  return MockClient((request) async {
    return http.Response(jsonEncode(responseBody), statusCode);
  });
}

/// Create a MockClient that throws a network error.
MockClient _errorClient() {
  return MockClient((request) async {
    throw http.ClientException('Connection refused');
  });
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('OsrmRoutingEngine', () {
    group('info', () {
      test('engine name is osrm', () {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));
        expect(engine.info.name, 'osrm');
      });
    });

    group('isAvailable', () {
      test('returns true when server responds 200', () async {
        final client = MockClient((request) async {
          expect(request.url.path, contains('/nearest/v1/driving/'));
          return http.Response('{"code":"Ok"}', 200);
        });
        final engine = OsrmRoutingEngine(client: client);

        expect(await engine.isAvailable(), isTrue);
      });

      test('returns false when server unreachable', () async {
        final engine = OsrmRoutingEngine(client: _errorClient());

        expect(await engine.isAvailable(), isFalse);
      });
    });

    group('calculateRoute', () {
      test('sends GET with correct URL format (lon,lat order)', () async {
        Uri? capturedUri;
        final client = MockClient((request) async {
          capturedUri = request.url;
          return http.Response(jsonEncode(_validResponse()), 200);
        });
        final engine = OsrmRoutingEngine(
          baseUrl: 'http://localhost:5000',
          client: client,
        );

        await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(capturedUri, isNotNull);
        // OSRM uses lon,lat (not lat,lon).
        expect(capturedUri!.path,
            contains('/route/v1/driving/136.8815,35.1709;137.1566,35.0504'));
        expect(capturedUri!.queryParameters['steps'], 'true');
        expect(capturedUri!.queryParameters['overview'], 'full');
        expect(capturedUri!.queryParameters['geometries'], 'polyline');
      });

      test('parses valid response into RouteResult', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.totalDistanceKm, closeTo(25.7, 0.01));
        expect(result.totalTimeSeconds, 1830);
        expect(result.maneuvers, hasLength(3));
        expect(result.engineInfo.name, 'osrm');
        expect(result.shape, isNotEmpty);
      });

      test('decodes polyline5 geometry correctly', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        // Polyline5 should decode to approximately our test coordinates.
        expect(result.shape.length, greaterThanOrEqualTo(2));
        expect(result.shape.first.latitude, closeTo(35.1709, 0.01));
        expect(result.shape.first.longitude, closeTo(136.8815, 0.01));
      });

      test('parses maneuver types correctly', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'depart');
        expect(result.maneuvers[1].type, 'right');
        expect(result.maneuvers[2].type, 'arrive');
      });

      test('builds human-readable instructions', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].instruction, 'Depart on Route 153');
        expect(result.maneuvers[1].instruction,
            'Right onto Tokai-Kanjo Expressway');
        expect(result.maneuvers[2].instruction, 'Arrive at destination');
      });

      test('converts distance from meters to km', () async {
        final engine = OsrmRoutingEngine(
          client: _mockClient(_validResponse(distance: 5000)),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.totalDistanceKm, closeTo(5.0, 0.01));
      });

      test('records query latency in engineInfo', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.engineInfo.queryLatency, isNotNull);
        expect(
            result.engineInfo.queryLatency.inMicroseconds, greaterThan(0));
      });

      test('generates summary string', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.summary, contains('25.7 km'));
        expect(result.summary, contains('31 min'));
      });

      test('parses maneuver positions (lon,lat → LatLng)', () async {
        final engine = OsrmRoutingEngine(client: _mockClient(_validResponse()));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        // First maneuver at Nagoya.
        expect(result.maneuvers[0].position.latitude, closeTo(35.1709, 0.001));
        expect(
            result.maneuvers[0].position.longitude, closeTo(136.8815, 0.001));
      });
    });

    group('error handling', () {
      test('throws RoutingException on HTTP error', () async {
        final engine = OsrmRoutingEngine(
          client: _mockClient({'error': 'bad request'}, statusCode: 400),
        );

        expect(
          () => engine.calculateRoute(const RouteRequest(
            origin: _nagoya,
            destination: _toyota,
          )),
          throwsA(isA<RoutingException>()),
        );
      });

      test('throws RoutingException on OSRM error code', () async {
        final engine = OsrmRoutingEngine(
          client: _mockClient({
            'code': 'NoRoute',
            'message': 'No route found',
          }),
        );

        expect(
          () => engine.calculateRoute(const RouteRequest(
            origin: _nagoya,
            destination: _toyota,
          )),
          throwsA(isA<RoutingException>().having(
            (e) => e.message,
            'message',
            contains('No route found'),
          )),
        );
      });

      test('throws RoutingException on empty routes array', () async {
        final engine = OsrmRoutingEngine(
          client: _mockClient({'code': 'Ok', 'routes': []}),
        );

        expect(
          () => engine.calculateRoute(const RouteRequest(
            origin: _nagoya,
            destination: _toyota,
          )),
          throwsA(isA<RoutingException>()),
        );
      });

      test('throws RoutingException on network error', () async {
        final engine = OsrmRoutingEngine(client: _errorClient());

        expect(
          () => engine.calculateRoute(const RouteRequest(
            origin: _nagoya,
            destination: _toyota,
          )),
          throwsA(isA<RoutingException>().having(
            (e) => e.message,
            'message',
            contains('network error'),
          )),
        );
      });
    });

    group('maneuver type mapping', () {
      test('maps roundabout type', () async {
        final response = _validResponse(steps: [
          {
            'name': 'Circle Rd',
            'distance': 200.0,
            'duration': 30.0,
            'maneuver': {
              'type': 'roundabout',
              'modifier': 'right',
              'location': [136.88, 35.17],
            },
          },
        ]);
        final engine = OsrmRoutingEngine(client: _mockClient(response));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'roundabout_enter');
      });

      test('maps merge type', () async {
        final response = _validResponse(steps: [
          {
            'name': 'Highway',
            'distance': 500.0,
            'duration': 20.0,
            'maneuver': {
              'type': 'merge',
              'modifier': 'slight left',
              'location': [136.88, 35.17],
            },
          },
        ]);
        final engine = OsrmRoutingEngine(client: _mockClient(response));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'merge');
      });

      test('maps slight left modifier', () async {
        final response = _validResponse(steps: [
          {
            'name': 'Side Rd',
            'distance': 300.0,
            'duration': 40.0,
            'maneuver': {
              'type': 'turn',
              'modifier': 'slight left',
              'location': [136.88, 35.17],
            },
          },
        ]);
        final engine = OsrmRoutingEngine(client: _mockClient(response));

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'slight_left');
      });
    });

    group('dispose', () {
      test('completes without error', () async {
        final client = MockClient((request) async {
          return http.Response('{}', 200);
        });
        final engine = OsrmRoutingEngine(client: client);
        await engine.dispose();
        // If we reach here, dispose succeeded.
        expect(true, isTrue);
      });
    });
  });
}
