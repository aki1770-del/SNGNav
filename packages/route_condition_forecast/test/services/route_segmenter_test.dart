import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:test/test.dart';

RouteManeuver _maneuver(int i, LatLng pos, {double km = 5.0, double t = 300}) =>
    RouteManeuver(
      index: i,
      instruction: 'Step $i',
      type: i == 0 ? 'depart' : 'straight',
      lengthKm: km,
      timeSeconds: t,
      position: pos,
    );

const _engineInfo = EngineInfo(name: 'mock');

void main() {
  group('RouteSegmenter.byManeuver', () {
    test('empty maneuvers returns empty list', () {
      final route = RouteResult(
        shape: const [],
        maneuvers: const [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '',
        engineInfo: _engineInfo,
      );
      expect(RouteSegmenter.byManeuver(route), isEmpty);
    });

    test('single maneuver uses last shape point as end', () {
      const p0 = LatLng(35.17, 136.88);
      const last = LatLng(35.20, 136.90);
      final route = RouteResult(
        shape: const [p0, last],
        maneuvers: [_maneuver(0, p0, km: 3.0)],
        totalDistanceKm: 3.0,
        totalTimeSeconds: 180,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byManeuver(route);
      expect(segs.length, 1);
      expect(segs[0].start, equals(p0));
      expect(segs[0].end, equals(last));
      expect(segs[0].distanceKm, 3.0);
    });

    test('two maneuvers — first ends at second maneuver position', () {
      const p0 = LatLng(35.17, 136.88);
      const p1 = LatLng(35.18, 136.89);
      const pEnd = LatLng(35.20, 136.90);
      final route = RouteResult(
        shape: const [p0, p1, pEnd],
        maneuvers: [_maneuver(0, p0, km: 2.0), _maneuver(1, p1, km: 3.0)],
        totalDistanceKm: 5.0,
        totalTimeSeconds: 300,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byManeuver(route);
      expect(segs.length, 2);
      expect(segs[0].end, equals(p1));
      expect(segs[1].end, equals(pEnd));
    });

    test('segment indices are sequential', () {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      const p2 = LatLng(35.2, 136.2);
      final route = RouteResult(
        shape: const [p0, p1, p2],
        maneuvers: [
          _maneuver(0, p0),
          _maneuver(1, p1),
          _maneuver(2, p2),
        ],
        totalDistanceKm: 10,
        totalTimeSeconds: 600,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byManeuver(route);
      for (int i = 0; i < segs.length; i++) {
        expect(segs[i].index, i);
      }
    });

    test('segments carry maneuver reference', () {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      final m = _maneuver(0, p0, km: 5.0);
      final route = RouteResult(
        shape: const [p0, p1],
        maneuvers: [m],
        totalDistanceKm: 5,
        totalTimeSeconds: 300,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byManeuver(route);
      expect(segs[0].maneuver, equals(m));
    });
  });

  group('RouteSegmenter.byDistance', () {
    test('segments shorter than maxKm are not subdivided', () {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      final route = RouteResult(
        shape: const [p0, p1],
        maneuvers: [_maneuver(0, p0, km: 4.0)],
        totalDistanceKm: 4.0,
        totalTimeSeconds: 240,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byDistance(route, maxKm: 5.0);
      expect(segs.length, 1);
      expect(segs[0].distanceKm, closeTo(4.0, 1e-9));
    });

    test('10 km segment with maxKm=5 produces 2 sub-segments', () {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.2, 136.2);
      final route = RouteResult(
        shape: const [p0, p1],
        maneuvers: [_maneuver(0, p0, km: 10.0)],
        totalDistanceKm: 10.0,
        totalTimeSeconds: 600,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byDistance(route, maxKm: 5.0);
      expect(segs.length, 2);
      for (final s in segs) {
        expect(s.distanceKm, closeTo(5.0, 1e-9));
      }
    });

    test('maneuver preserved only on first sub-segment', () {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.3, 136.3);
      final m = _maneuver(0, p0, km: 15.0);
      final route = RouteResult(
        shape: const [p0, p1],
        maneuvers: [m],
        totalDistanceKm: 15.0,
        totalTimeSeconds: 900,
        summary: '',
        engineInfo: _engineInfo,
      );
      final segs = RouteSegmenter.byDistance(route, maxKm: 5.0);
      expect(segs.length, 3);
      expect(segs[0].maneuver, equals(m));
      expect(segs[1].maneuver, isNull);
      expect(segs[2].maneuver, isNull);
    });
  });
}
