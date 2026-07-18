import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

/// 0.3.0 substituted `const LatLng(0, 0)` — Null Island, a real coordinate in the
/// Gulf of Guinea — whenever it could not resolve a maneuver's position. It is a
/// valid `LatLng` like any other, so a consumer had no way to know it was invented.
///
/// This test fails against 0.3.0.
void main() {
  test('an unplaceable maneuver is never placed in the ocean', () async {
    // A maneuver with NO location, on a route with NO decodable shape: there is
    // no truthful point anywhere on earth for it. 0.3.0 answered LatLng(0, 0).
    final client = MockClient((_) async => http.Response(
          jsonEncode({
            'code': 'Ok',
            'routes': [
              {
                'geometry': '',
                'distance': 100,
                'duration': 60,
                'legs': [
                  {
                    'steps': [
                      {'maneuver': {}, 'distance': 100, 'duration': 60},
                    ],
                  },
                ],
              },
            ],
          }),
          200,
        ));

    final engine = OsrmRoutingEngine(
      baseUrl: 'https://example.invalid',
      client: client,
    );

    final result = await engine.calculateRoute(
      const RouteRequest(
        origin: LatLng(39.72, 140.10), // Akita
        destination: LatLng(39.75, 140.15),
      ),
    );

    for (final m in result.maneuvers) {
      expect(
        m.position.latitude == 0 && m.position.longitude == 0,
        isFalse,
        reason: 'a maneuver was placed at Null Island',
      );
    }
  });
}
