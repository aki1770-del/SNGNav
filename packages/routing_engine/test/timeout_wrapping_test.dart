import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

/// 0.3.4 hardening: a network-layer throw that is not an `http.ClientException`
/// — most commonly `TimeoutException` from the request timeout — must surface
/// as the documented `RoutingException`, never escape `calculateRoute()` raw.
/// Up to and including 0.3.3 both engines caught only `http.ClientException`,
/// so a slow or hung routing server crashed the caller instead of raising the
/// error type this package documents.
void main() {
  const request = RouteRequest(
    origin: LatLng(35.17, 136.88),
    destination: LatLng(34.97, 137.17),
  );

  MockClient throwing(Object error) => MockClient((_) async => throw error);

  group('Valhalla — non-ClientException network errors', () {
    test(
        'T-1 TimeoutException -> RoutingException '
        '(was: raw TimeoutException escaping calculateRoute)', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: throwing(
          TimeoutException('slow server', const Duration(seconds: 15)),
        ),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test('T-2 generic Exception -> RoutingException', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: throwing(Exception('connection reset')),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });
  });

  group('OSRM — non-ClientException network errors', () {
    test(
        'T-3 TimeoutException -> RoutingException '
        '(was: raw TimeoutException escaping calculateRoute)', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://x',
        client: throwing(
          TimeoutException('slow server', const Duration(seconds: 15)),
        ),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test('T-4 generic Exception -> RoutingException', () async {
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://x',
        client: throwing(Exception('connection reset')),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });
  });

  group('contract preserved (regression)', () {
    test('T-5 http.ClientException still -> RoutingException', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: throwing(http.ClientException('boom')),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(isA<RoutingException>()),
      );
    });

    test(
        'T-6 deliberate RoutingException (HTTP 500) passes through '
        'unwrapped, message intact', () async {
      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response('server error', 500)),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.toString(),
            'message',
            // A double-wrap (deliberate RoutingException re-caught by the
            // network-layer catch) would prepend 'network error' — the
            // absence assertion is what kills that mutant.
            allOf(contains('500'), isNot(contains('network error'))),
          ),
        ),
      );
    });

    test(
        'T-6b (OSRM analog) deliberate RoutingException (HTTP 500) passes '
        'through unwrapped, message intact — never double-wrapped', () async {
      // Kills the mutant where the `on RoutingException { rethrow; }`
      // clause in OsrmRoutingEngine.calculateRoute is deleted: the
      // deliberate HTTP-status RoutingException would then be re-caught by
      // `on Exception` and re-wrapped as 'OSRM network error:
      // RoutingException: …'. A bare isA<RoutingException> +
      // contains('500') check survives that double-wrap; the
      // isNot(contains('network error')) assertion does not.
      final engine = OsrmRoutingEngine(
        baseUrl: 'http://x',
        client: MockClient((_) async => http.Response('server error', 500)),
      );
      await expectLater(
        engine.calculateRoute(request),
        throwsA(
          isA<RoutingException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('OSRM route failed (500)'),
              isNot(contains('network error')),
            ),
          ),
        ),
      );
    });
  });
}
