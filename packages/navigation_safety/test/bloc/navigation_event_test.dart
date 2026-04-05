library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';

const _origin = LatLng(35.1709, 136.8815);
const _destination = LatLng(35.0504, 137.1566);

final _route = RouteResult(
  shape: const [_origin, _destination],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Depart',
      type: 'depart',
      lengthKm: 10,
      timeSeconds: 600,
      position: _origin,
    ),
  ],
  totalDistanceKm: 10,
  totalTimeSeconds: 600,
  summary: 'Test route',
  engineInfo: const EngineInfo(name: 'mock'),
);

void main() {
  group('NavigationEvent props', () {
    test('base events keep empty props', () {
      expect(const NavigationStopped().props, isEmpty);
      expect(const ManeuverAdvanced().props, isEmpty);
      expect(const SafetyAlertDismissed().props, isEmpty);
    });

    test('started event exposes route and destination label', () {
      expect(
        NavigationStarted(route: _route, destinationLabel: 'Toyota').props,
        [_route, 'Toyota'],
      );
    });

    test('route deviation exposes optional reason', () {
      expect(const RouteDeviationDetected().props, [null]);
      expect(
        const RouteDeviationDetected(reason: 'off-route').props,
        ['off-route'],
      );
    });

    test('reroute and safety alert expose their payload props', () {
      expect(RerouteCompleted(newRoute: _route).props, [_route]);
      expect(
        const SafetyAlertReceived(
          message: 'Ice ahead',
          severity: AlertSeverity.warning,
          dismissible: false,
        ).props,
        ['Ice ahead', AlertSeverity.warning, false, null],
      );
    });
  });
}