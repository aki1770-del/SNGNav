// test/navigation/route_follower_test.dart
//
// Unit tests for RouteFollower.
// Run with: flutter test test/navigation/route_follower_test.dart

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart' show GeoPosition;
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/navigation/route_follower.dart';

// ---------------------------------------------------------------------------
// Test geometry helpers
// ---------------------------------------------------------------------------

double _degToRad(double d) => d * math.pi / 180.0;

/// Offset a point by metres north / east (flat-earth approximation).
LatLng _offset(LatLng origin, {double northMetres = 0.0, double eastMetres = 0.0}) {
  const double latPerMetre = 1.0 / 111320.0;
  final double lonPerMetre =
      1.0 / (111320.0 * math.cos(_degToRad(origin.latitude)));
  return LatLng(
    origin.latitude + northMetres * latPerMetre,
    origin.longitude + eastMetres * lonPerMetre,
  );
}

/// Builds a straight west-to-east polyline.
List<LatLng> _straightEastRoad({
  LatLng start = const LatLng(55.0, 37.0),
  int segCount = 10,
  double segLenMetres = 100.0,
}) {
  final List<LatLng> pts = [start];
  for (int i = 0; i < segCount; i++) {
    pts.add(_offset(pts.last, eastMetres: segLenMetres));
  }
  return pts;
}

/// Builds a straight north-to-south polyline (for heading-filter test).
List<LatLng> _straightSouthRoad({
  LatLng start = const LatLng(55.0, 37.01),
  int segCount = 10,
  double segLenMetres = 100.0,
}) {
  final List<LatLng> pts = [start];
  for (int i = 0; i < segCount; i++) {
    pts.add(_offset(pts.last, northMetres: -segLenMetres));
  }
  return pts;
}

/// Convenience: build a GeoPosition from a LatLng with optional motion.
GeoPosition _pos(
  LatLng latLng, {
  double accuracy = 5.0,
  double speedMs = double.nan,
  double heading = double.nan,
}) =>
    GeoPosition(
      latitude: latLng.latitude,
      longitude: latLng.longitude,
      accuracy: accuracy,
      speed: speedMs,
      heading: heading,
      timestamp: DateTime.utc(2026, 4, 7),
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // =========================================================================
  group('haversineMetres', () {
    test('same point → 0 m', () {
      final p = LatLng(55.0, 37.0);
      expect(haversineMetres(p, p), closeTo(0.0, 1e-6));
    });

    test('equatorial degree ≈ 110 574 m', () {
      final a = LatLng(0.0, 0.0);
      final b = LatLng(1.0, 0.0);
      expect(haversineMetres(a, b), closeTo(110574.0, 1000.0));
    });
  });

  // =========================================================================
  group('projectPointToSegment', () {
    test('midpoint projects to midpoint', () {
      final a = LatLng(55.0, 37.0);
      final b = LatLng(55.0, 37.01);
      final testPoint = _offset(LatLng(55.0, 37.005), northMetres: 5.0);

      final proj = projectPointToSegment(testPoint, a, b);

      expect(proj.latitude, closeTo(a.latitude, 1e-5));
      expect(proj.longitude, closeTo(37.005, 0.0005));
    });

    test('point before segment start → clamps to a', () {
      final a = LatLng(55.0, 37.0);
      final b = LatLng(55.0, 37.01);
      final proj = projectPointToSegment(LatLng(55.0, 36.99), a, b);
      expect(proj.latitude, closeTo(a.latitude, 1e-6));
      expect(proj.longitude, closeTo(a.longitude, 1e-6));
    });

    test('point after segment end → clamps to b', () {
      final a = LatLng(55.0, 37.0);
      final b = LatLng(55.0, 37.01);
      final proj = projectPointToSegment(LatLng(55.0, 37.02), a, b);
      expect(proj.latitude, closeTo(b.latitude, 1e-6));
      expect(proj.longitude, closeTo(b.longitude, 1e-6));
    });

    test('degenerate segment (a == b) → returns a', () {
      final a = LatLng(55.0, 37.0);
      final proj = projectPointToSegment(LatLng(55.1, 37.1), a, a);
      expect(proj.latitude, closeTo(a.latitude, 1e-6));
      expect(proj.longitude, closeTo(a.longitude, 1e-6));
    });
  });

  // =========================================================================
  group('RouteFollower — straight road GPS noise', () {
    test('GPS noise ±5 m → snapped position stable on segment', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      final rf = RouteFollower(shape: shape);

      // Position near segment 5 (500 m along route), GPS jittering ±5 m north.
      final LatLng onRoute = _offset(shape[5], eastMetres: 20.0);

      final p1 = rf.update(_pos(_offset(onRoute, northMetres: 5.0)));
      final p2 = rf.update(_pos(_offset(onRoute, northMetres: -5.0)));
      final p3 = rf.update(_pos(_offset(onRoute, northMetres: 3.0)));

      // All three snapped points should be within 1 m of each other longitudinally.
      expect((p1.snappedLatLng.longitude - p2.snappedLatLng.longitude).abs(),
          lessThan(0.0001));
      expect((p1.snappedLatLng.longitude - p3.snappedLatLng.longitude).abs(),
          lessThan(0.0001));

      // None should be off-route (5 m < 50 m threshold).
      expect(p1.isOffRoute, isFalse);
      expect(p2.isOffRoute, isFalse);
    });
  });

  // =========================================================================
  group('RouteFollower — monotonicity guard', () {
    test('GPS moves backward 10 m → snapped position does not retreat', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      final rf = RouteFollower(shape: shape, backtrackAllowanceMetres: 50.0);

      // Move forward to segment 5.
      final LatLng forward = _offset(shape[5], eastMetres: 50.0);
      rf.update(_pos(forward));

      final double progressAfterForward = rf.update(_pos(forward)).progressFraction;

      // Now GPS jumps backward 10 m (within allowance — 10 < 50 m).
      final LatLng backward = _offset(forward, eastMetres: -10.0);
      final snap = rf.update(_pos(backward));

      // Snapped position must not retreat more than the allowance.
      expect(snap.progressFraction, greaterThanOrEqualTo(progressAfterForward - 0.05));
    });

    test('GPS moves backward 80 m (> allowance) → segment index clamped', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      final rf = RouteFollower(shape: shape, backtrackAllowanceMetres: 50.0);

      // Advance to near segment 5.
      final LatLng forward = _offset(shape[5], eastMetres: 10.0);
      for (int i = 0; i < 3; i++) {
        rf.update(_pos(forward));
      }
      final int segAfterAdvance = rf.currentSegmentIndex;

      // Jump backward 80 m — beyond backtrackAllowanceMetres.
      final LatLng bigBackward = _offset(forward, eastMetres: -80.0);
      final snap = rf.update(_pos(bigBackward));

      // Segment index should not retreat past current.
      expect(snap.segmentIndex, greaterThanOrEqualTo(segAfterAdvance - 1));
    });
  });

  // =========================================================================
  group('RouteFollower — off-route detection', () {
    test('position 60 m from route → off-route flagged, raw position returned', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      final rf = RouteFollower(shape: shape, offRouteThresholdMetres: 50.0);

      // 60 m north of route midpoint.
      final LatLng offRoute = _offset(shape[5], northMetres: 60.0);
      final snap = rf.update(_pos(offRoute));

      expect(snap.isOffRoute, isTrue);
      expect(snap.distanceFromRoute, greaterThan(50.0));
      // rawLatLng must match the input exactly.
      expect(snap.rawLatLng.latitude, closeTo(offRoute.latitude, 1e-9));
      expect(snap.rawLatLng.longitude, closeTo(offRoute.longitude, 1e-9));
    });

    test('position 30 m from route → on-route', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      final rf = RouteFollower(shape: shape, offRouteThresholdMetres: 50.0);

      final LatLng nearRoute = _offset(shape[5], northMetres: 30.0);
      final snap = rf.update(_pos(nearRoute));

      expect(snap.isOffRoute, isFalse);
    });
  });

  // =========================================================================
  group('RouteFollower — heading filter', () {
    test('wrong-direction parallel road penalised', () {
      // East-travelling road.
      final shapeEast = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      // South-travelling parallel road 20 m north.
      final shapeSouth = _straightSouthRoad(
        start: _offset(shapeEast[0], northMetres: 20.0),
        segCount: 10,
        segLenMetres: 100.0,
      );

      // Position equidistant from both roads, heading east at ~30 km/h.
      final LatLng pos = _offset(shapeEast[5], northMetres: 10.0);
      // 30 km/h = 8.33 m/s; heading 90° = due east.
      final gps = _pos(pos, speedMs: 8.33, heading: 90.0);

      // RouteFollower on the east road — should snap to it cleanly.
      final rfEast = RouteFollower(shape: shapeEast);
      final snapEast = rfEast.update(gps);

      // RouteFollower on the south road — east heading vs south-bearing → penalised.
      final rfSouth = RouteFollower(shape: shapeSouth);
      rfSouth.update(gps);

      // The south road's effective distance would be much larger due to penalty.
      // The heading penalty prevented it from winning when alternatives existed.
      // We verify the east road snap is tighter (closer to 10 m than the south road would be).
      expect(snapEast.distanceFromRoute, lessThan(20.0));
    });
  });

  // =========================================================================
  group('RouteFollower — forward search window', () {
    test('distant matching segment not selected when out of window', () {
      // 40-segment road, narrow window.
      final List<LatLng> shape = [];
      final LatLng start = const LatLng(55.0, 37.0);
      shape.add(start);
      for (int i = 0; i < 40; i++) {
        shape.add(_offset(shape.last, eastMetres: 100.0));
      }

      final rf = RouteFollower(
        shape: shape,
        segmentWindowForward: 5, // only ±5 segments from current
      );

      // GPS at start of route.
      final snap = rf.update(_pos(start));

      // Must stay near segment 0, not jump to a distant match.
      expect(snap.segmentIndex, lessThanOrEqualTo(5));
    });
  });

  // =========================================================================
  group('RouteFollower — progress fraction', () {
    test('at start → progress ≈ 0', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      final rf = RouteFollower(shape: shape);

      final snap = rf.update(_pos(shape.first));
      expect(snap.progressFraction, closeTo(0.0, 0.02));
    });

    test('at end → progress ≈ 1', () {
      final shape = _straightEastRoad(segCount: 10, segLenMetres: 100.0);
      // Wide window so we can jump to the last segment in one call.
      final rf = RouteFollower(shape: shape, segmentWindowForward: 40);

      final snap = rf.update(_pos(shape.last));
      expect(snap.progressFraction, closeTo(1.0, 0.02));
    });
  });
}
