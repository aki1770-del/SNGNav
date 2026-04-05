import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:test/test.dart';

void main() {
  group('RouteSegment', () {
    const start = LatLng(35.1709, 136.8815); // Sakae
    const end = LatLng(35.0, 137.1); // Towards Okazaki

    test('midpoint is geometric average of start and end', () {
      final seg = RouteSegment(
        index: 0,
        start: start,
        end: end,
        distanceKm: 20.0,
      );
      expect(seg.midpoint.latitude,
          closeTo((start.latitude + end.latitude) / 2, 1e-9));
      expect(seg.midpoint.longitude,
          closeTo((start.longitude + end.longitude) / 2, 1e-9));
    });

    test('midpoint of coincident points equals the point', () {
      final seg = RouteSegment(
        index: 0,
        start: start,
        end: start,
        distanceKm: 0.0,
      );
      expect(seg.midpoint.latitude, closeTo(start.latitude, 1e-9));
      expect(seg.midpoint.longitude, closeTo(start.longitude, 1e-9));
    });

    test('props equality includes all fields', () {
      final m = RouteManeuver(
        index: 0,
        instruction: 'Depart',
        type: 'depart',
        lengthKm: 20.0,
        timeSeconds: 1200,
        position: start,
      );
      final a = RouteSegment(index: 0, start: start, end: end, distanceKm: 20.0, maneuver: m);
      final b = RouteSegment(index: 0, start: start, end: end, distanceKm: 20.0, maneuver: m);
      expect(a, equals(b));
    });

    test('segments with different index are not equal', () {
      final a = RouteSegment(index: 0, start: start, end: end, distanceKm: 5.0);
      final b = RouteSegment(index: 1, start: start, end: end, distanceKm: 5.0);
      expect(a, isNot(equals(b)));
    });

    test('toString includes index and distance', () {
      final seg = RouteSegment(index: 2, start: start, end: end, distanceKm: 7.5);
      expect(seg.toString(), contains('2'));
      expect(seg.toString(), contains('7.50'));
    });
  });
}
