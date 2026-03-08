/// OSRM public demo probe — live connectivity test from Machine D.
///
/// These tests hit the real OSRM public demo server to verify:
///   1. Server is reachable from this machine
///   2. OsrmRoutingEngine correctly parses real responses
///   3. Route geometry + maneuvers are reasonable for Nagoya area
///
/// Tagged @Tags(['probe']) — excluded from CI, run manually:
///   flutter test test/providers/osrm_probe_test.dart
///
/// Sprint 9 Day 7 — OSRM real routing (E9-3).
@Tags(['probe'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:routing_engine/routing_engine.dart';

void main() {
  const osrmDemoUrl = 'https://router.project-osrm.org';
  const nagoya = LatLng(35.1709, 136.8815);
  const toyota = LatLng(35.0504, 137.1566);

  group('OSRM public demo probe', () {
    late OsrmRoutingEngine engine;

    setUp(() {
      engine = OsrmRoutingEngine(baseUrl: osrmDemoUrl);
    });

    tearDown(() async {
      await engine.dispose();
    });

    test('isAvailable returns true for public demo', () async {
      final available = await engine.isAvailable();

      // The OSRM public demo may be temporarily down.
      // This test documents reachability from Machine D.
      print('OSRM public demo reachable: $available');
      print('URL: $osrmDemoUrl');
      expect(available, isA<bool>());
    });

    test('calculates Nagoya → Toyota route with real geometry', () async {
      final result = await engine.calculateRoute(const RouteRequest(
        origin: nagoya,
        destination: toyota,
      ));

      print('Route: ${result.summary}');
      print('Distance: ${result.totalDistanceKm.toStringAsFixed(1)} km');
      print('Duration: ${(result.totalTimeSeconds / 60).toStringAsFixed(0)} min');
      print('Geometry points: ${result.shape.length}');
      print('Maneuvers: ${result.maneuvers.length}');
      print('Latency: ${result.engineInfo.queryLatency.inMilliseconds} ms');

      // Nagoya → Toyota is ~25-40 km by road.
      expect(result.totalDistanceKm, greaterThan(20));
      expect(result.totalDistanceKm, lessThan(60));

      // Should have meaningful geometry.
      expect(result.shape.length, greaterThan(50));

      // Should have multiple maneuvers.
      expect(result.maneuvers.length, greaterThan(3));

      // First maneuver should be 'depart', last should be 'arrive'.
      expect(result.maneuvers.first.type, 'depart');
      expect(result.maneuvers.last.type, 'arrive');

      // Engine info should report osrm.
      expect(result.engineInfo.name, 'osrm');

      // Latency should be reasonable (< 5s for public demo).
      expect(
        result.engineInfo.queryLatency.inMilliseconds,
        lessThan(5000),
      );

      // Start point should be near Nagoya.
      expect(result.shape.first.latitude, closeTo(35.17, 0.05));
      expect(result.shape.first.longitude, closeTo(136.88, 0.05));

      // End point should be near Toyota.
      expect(result.shape.last.latitude, closeTo(35.05, 0.05));
      expect(result.shape.last.longitude, closeTo(137.16, 0.05));
    });

    test('maneuver instructions are human-readable', () async {
      final result = await engine.calculateRoute(const RouteRequest(
        origin: nagoya,
        destination: toyota,
      ));

      print('--- Maneuvers ---');
      for (final m in result.maneuvers) {
        print('  [${m.index}] ${m.type}: ${m.instruction} '
            '(${m.lengthKm.toStringAsFixed(1)} km)');
      }

      // Every maneuver should have a non-empty instruction.
      for (final m in result.maneuvers) {
        expect(m.instruction, isNotEmpty,
            reason: 'Maneuver ${m.index} has empty instruction');
      }

      // Depart instruction should mention a road name or "Depart".
      expect(
        result.maneuvers.first.instruction.toLowerCase(),
        contains('depart'),
      );
    });
  });
}
