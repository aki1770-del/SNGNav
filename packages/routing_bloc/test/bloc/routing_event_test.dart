library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_bloc/routing_bloc.dart';

const _origin = LatLng(35.1709, 136.8815);
const _destination = LatLng(35.0504, 137.1566);

void main() {
  group('RoutingEvent props', () {
    test('route request exposes routing payload', () {
      expect(
        const RouteRequested(
          origin: _origin,
          destination: _destination,
          destinationLabel: 'Toyota HQ',
          costing: 'pedestrian',
        ).props,
        [_origin, _destination, 'Toyota HQ', 'pedestrian'],
      );
    });

    test('clear and engine-check events use base empty props', () {
      expect(const RouteClearRequested().props, isEmpty);
      expect(const RoutingEngineCheckRequested().props, isEmpty);
    });
  });
}