library;

import 'dart:io';

import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

const _defaultBaseUrl = 'http://localhost:8005';
const _machineERequest = RouteRequest(
  origin: LatLng(35.1709, 136.9066),
  destination: LatLng(34.9551, 137.1771),
);

void main() {
  final runLocalValhalla =
      Platform.environment['RUN_LOCAL_VALHALLA_TEST'] == '1';
  final baseUrl =
      Platform.environment['VALHALLA_BASE_URL'] ?? _defaultBaseUrl;

  group('Valhalla local integration', () {
    test(
      'real local Valhalla returns a route and records latency',
      () async {
        final engine = ValhallaRoutingEngine(
          baseUrl: baseUrl,
          availabilityTimeout: const Duration(seconds: 2),
          routeTimeout: const Duration(seconds: 10),
        );

        addTearDown(() async {
          await engine.dispose();
        });

        final available = await engine.isAvailable();
        expect(
          available,
          isTrue,
          reason: 'Expected local Valhalla at $baseUrl to respond to /status',
        );

        final result = await engine.calculateRoute(_machineERequest);

        expect(result.engineInfo.name, 'valhalla');
        expect(result.hasGeometry, isTrue);
        expect(result.shape.length, greaterThanOrEqualTo(2));
        expect(result.maneuvers, isNotEmpty);
        expect(result.totalDistanceKm, greaterThan(0));
        expect(result.totalTimeSeconds, greaterThan(0));
        expect(
          result.engineInfo.queryLatency,
          lessThan(const Duration(seconds: 5)),
          reason: 'Local Valhalla should beat the public multi-second baseline',
        );
      },
      skip: runLocalValhalla
          ? false
          : 'Set RUN_LOCAL_VALHALLA_TEST=1 to run against a real local Valhalla instance',
    );
  });
}