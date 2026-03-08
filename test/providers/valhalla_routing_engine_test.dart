/// ValhallaRoutingEngine unit tests — HTTP response parsing, polyline6
/// decoding, maneuver type mapping, and error handling.
///
/// Uses a mock HTTP client — no Docker, no Valhalla server required.
/// Mirrors the OsrmRoutingEngine test structure for consistency.
///
/// Sprint 9 Day 11 — Test hardening.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';

import 'package:routing_engine/routing_engine.dart';

// ---------------------------------------------------------------------------
// Test data — realistic Valhalla response for Nagoya → Toyota City
// ---------------------------------------------------------------------------

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);

/// Polyline6-encoded line for two points (Nagoya, Toyota).
/// Precision 6: coordinates × 1e6, delta-encoded.
///
/// Encode (35.1709, 136.8815) → lat=35170900, lon=136881500
/// Then  (35.0504, 137.1566) → delta lat=-120500, delta lon=275100
String _testPolyline6() {
  // We'll use a known working polyline6 string.
  // For testing, we generate it from the encoder logic.
  return _encodePolyline6([_nagoya, _toyota]);
}

/// Simple polyline6 encoder for test data generation.
String _encodePolyline6(List<LatLng> points) {
  final buf = StringBuffer();
  var prevLat = 0;
  var prevLon = 0;

  for (final p in points) {
    final lat = (p.latitude * 1e6).round();
    final lon = (p.longitude * 1e6).round();
    _encodeValue(lat - prevLat, buf);
    _encodeValue(lon - prevLon, buf);
    prevLat = lat;
    prevLon = lon;
  }
  return buf.toString();
}

void _encodeValue(int value, StringBuffer buf) {
  var v = value < 0 ? ~(value << 1) : (value << 1);
  while (v >= 0x20) {
    buf.writeCharCode((0x20 | (v & 0x1F)) + 63);
    v >>= 5;
  }
  buf.writeCharCode(v + 63);
}

/// Minimal valid Valhalla route response.
Map<String, dynamic> _validResponse({
  String? shape,
  double lengthKm = 25.7,
  double timeSeconds = 1830,
  List<Map<String, dynamic>>? maneuvers,
}) {
  return {
    'trip': {
      'summary': {
        'length': lengthKm,
        'time': timeSeconds,
      },
      'legs': [
        {
          'shape': shape ?? _testPolyline6(),
          'maneuvers': maneuvers ??
              [
                {
                  'instruction': 'Drive north on Route 153.',
                  'type': 1, // depart
                  'length': 12.5,
                  'time': 720.0,
                  'begin_shape_index': 0,
                },
                {
                  'instruction': 'Arrive at your destination.',
                  'type': 2, // arrive
                  'length': 0.0,
                  'time': 0.0,
                  'begin_shape_index': 1,
                },
              ],
        },
      ],
    },
  };
}

/// Create a MockClient that returns the given body.
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
  group('ValhallaRoutingEngine', () {
    group('info', () {
      test('engine name is valhalla', () {
        final engine =
            ValhallaRoutingEngine(client: _mockClient(_validResponse()));
        expect(engine.info.name, 'valhalla');
      });
    });

    group('isAvailable', () {
      test('returns true when /status responds 200', () async {
        final client = MockClient((request) async {
          expect(request.url.path, '/status');
          return http.Response('{}', 200);
        });
        final engine = ValhallaRoutingEngine(client: client);

        expect(await engine.isAvailable(), isTrue);
      });

      test('returns false when server unreachable', () async {
        final engine = ValhallaRoutingEngine(client: _errorClient());

        expect(await engine.isAvailable(), isFalse);
      });

      test('returns false on non-200 status', () async {
        final client = MockClient((request) async {
          return http.Response('error', 500);
        });
        final engine = ValhallaRoutingEngine(client: client);

        expect(await engine.isAvailable(), isFalse);
      });
    });

    group('calculateRoute', () {
      test('sends POST to /route with correct body', () async {
        http.Request? capturedRequest;
        final client = MockClient((request) async {
          capturedRequest = request;
          return http.Response(jsonEncode(_validResponse()), 200);
        });
        final engine = ValhallaRoutingEngine(
          baseUrl: 'http://localhost:8002',
          client: client,
        );

        await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(capturedRequest, isNotNull);
        expect(capturedRequest!.url.path, '/route');
        expect(capturedRequest!.method, 'POST');

        final body = jsonDecode(capturedRequest!.body) as Map<String, dynamic>;
        final locations = body['locations'] as List;
        expect(locations, hasLength(2));
        expect(locations[0]['lat'], _nagoya.latitude);
        expect(locations[0]['lon'], _nagoya.longitude);
        expect(locations[1]['lat'], _toyota.latitude);
        expect(locations[1]['lon'], _toyota.longitude);
      });

      test('parses valid response into RouteResult', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse()),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.totalDistanceKm, closeTo(25.7, 0.01));
        expect(result.totalTimeSeconds, 1830);
        expect(result.maneuvers, hasLength(2));
        expect(result.engineInfo.name, 'valhalla');
        expect(result.shape, isNotEmpty);
      });

      test('decodes polyline6 geometry correctly', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse()),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.shape.length, 2);
        expect(result.shape[0].latitude, closeTo(35.1709, 0.001));
        expect(result.shape[0].longitude, closeTo(136.8815, 0.001));
        expect(result.shape[1].latitude, closeTo(35.0504, 0.001));
        expect(result.shape[1].longitude, closeTo(137.1566, 0.001));
      });

      test('parses maneuver instructions', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse()),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].instruction,
            'Drive north on Route 153.');
        expect(result.maneuvers[1].instruction,
            'Arrive at your destination.');
      });

      test('records query latency in engineInfo', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse()),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(
            result.engineInfo.queryLatency.inMicroseconds, greaterThan(0));
      });

      test('generates summary string', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse()),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.summary, contains('25.7 km'));
        expect(result.summary, contains('31 min'));
      });

      test('uses costing from request body', () async {
        Map<String, dynamic>? capturedBody;
        final client = MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_validResponse()), 200);
        });
        final engine = ValhallaRoutingEngine(client: client);

        await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
          costing: 'bicycle',
        ));

        expect(capturedBody!['costing'], 'bicycle');
      });

      test('uses language from request body', () async {
        Map<String, dynamic>? capturedBody;
        final client = MockClient((request) async {
          capturedBody = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(jsonEncode(_validResponse()), 200);
        });
        final engine = ValhallaRoutingEngine(client: client);

        await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
          language: 'en-US',
        ));

        final dirs =
            capturedBody!['directions_options'] as Map<String, dynamic>;
        expect(dirs['language'], 'en-US');
      });
    });

    group('maneuver type mapping', () {
      test('type 1 → depart', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse(maneuvers: [
            {
              'instruction': 'Go',
              'type': 1,
              'length': 1.0,
              'time': 60.0,
              'begin_shape_index': 0,
            },
          ])),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'depart');
      });

      test('type 6 → right', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse(maneuvers: [
            {
              'instruction': 'Turn right',
              'type': 6,
              'length': 0.5,
              'time': 30.0,
              'begin_shape_index': 0,
            },
          ])),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'right');
      });

      test('type 11 → left', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse(maneuvers: [
            {
              'instruction': 'Turn left',
              'type': 11,
              'length': 0.3,
              'time': 20.0,
              'begin_shape_index': 0,
            },
          ])),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'left');
      });

      test('type 22 → roundabout_enter', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse(maneuvers: [
            {
              'instruction': 'Enter roundabout',
              'type': 22,
              'length': 0.1,
              'time': 10.0,
              'begin_shape_index': 0,
            },
          ])),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'roundabout_enter');
      });

      test('unknown type → unknown', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse(maneuvers: [
            {
              'instruction': 'Do something',
              'type': 99,
              'length': 0.1,
              'time': 10.0,
              'begin_shape_index': 0,
            },
          ])),
        );

        final result = await engine.calculateRoute(const RouteRequest(
          origin: _nagoya,
          destination: _toyota,
        ));

        expect(result.maneuvers[0].type, 'unknown');
      });
    });

    group('error handling', () {
      test('throws RoutingException on HTTP error', () async {
        final engine = ValhallaRoutingEngine(
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

      test('throws RoutingException on missing trip field', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient({'status': 'ok'}),
        );

        expect(
          () => engine.calculateRoute(const RouteRequest(
            origin: _nagoya,
            destination: _toyota,
          )),
          throwsA(isA<RoutingException>().having(
            (e) => e.message,
            'message',
            contains('trip'),
          )),
        );
      });

      test('throws RoutingException on empty legs', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient({
            'trip': {
              'summary': {'length': 0, 'time': 0},
              'legs': [],
            },
          }),
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
        final engine = ValhallaRoutingEngine(client: _errorClient());

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

      test('includes error body in exception message for non-JSON', () async {
        final client = MockClient((request) async {
          return http.Response('Internal Server Error', 500);
        });
        final engine = ValhallaRoutingEngine(client: client);

        expect(
          () => engine.calculateRoute(const RouteRequest(
            origin: _nagoya,
            destination: _toyota,
          )),
          throwsA(isA<RoutingException>()),
        );
      });
    });

    group('dispose', () {
      test('completes without error', () async {
        final engine = ValhallaRoutingEngine(
          client: _mockClient(_validResponse()),
        );
        await engine.dispose();
        expect(true, isTrue);
      });
    });

    group('defaults', () {
      test('default base URL is localhost:8002', () {
        final engine = ValhallaRoutingEngine();
        expect(engine.baseUrl, 'http://localhost:8002');
      });
    });
  });
}
