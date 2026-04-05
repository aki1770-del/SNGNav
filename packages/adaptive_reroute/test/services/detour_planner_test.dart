import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:adaptive_reroute/adaptive_reroute.dart';
import 'package:test/test.dart';

HazardZone _zone(LatLng center, {double radius = 500}) => HazardZone(
      center: center,
      radiusMeters: radius,
      severity: HazardSeverity.icy,
      reports: [
        FleetReport(
          vehicleId: 'v1',
          position: center,
          timestamp: DateTime.utc(2026, 4, 5),
          condition: RoadCondition.icy,
        ),
      ],
    );

void main() {
  group('DetourPlanner', () {
    const planner = DetourPlanner();
    const sakae = LatLng(35.1709, 136.8815);

    test('empty zones produce no waypoints', () {
      final result = planner.plan([], approachBearing: 90.0);
      expect(result, isEmpty);
    });

    test('one zone produces two waypoints (left and right)', () {
      final zone = _zone(sakae);
      final result = planner.plan([zone], approachBearing: 0.0);
      expect(result.length, 2);
      expect(result.map((w) => w.side).toSet(),
          containsAll([DetourSide.left, DetourSide.right]));
    });

    test('two zones produce four waypoints', () {
      final z1 = _zone(sakae);
      final z2 = _zone(const LatLng(35.18, 136.90));
      final result = planner.plan([z1, z2], approachBearing: 45.0);
      expect(result.length, 4);
    });

    test('waypoint offset is at least zone radius + detour offset', () {
      const zoneCenter = LatLng(35.17, 136.88);
      const radius = 500.0;
      final zone = _zone(zoneCenter, radius: radius);
      const config = AdaptiveRerouteConfig(detourOffsetMeters: 2000.0);
      final planner2 = DetourPlanner(config: config);
      final result = planner2.plan([zone], approachBearing: 90.0);

      for (final wp in result) {
        final dist = const Distance().distance(zoneCenter, wp.position);
        // Should be approximately radius + offset
        expect(dist, greaterThan(radius));
        expect(wp.offsetMeters, closeTo(radius + 2000.0, 1.0));
      }
    });

    test('sourceZone is set on each waypoint', () {
      final zone = _zone(sakae);
      final result = planner.plan([zone], approachBearing: 180.0);
      for (final wp in result) {
        expect(wp.sourceZone, equals(zone));
      }
    });

    test('left and right waypoints are on opposite sides', () {
      const center = LatLng(35.17, 136.88);
      final zone = _zone(center);
      // Approach bearing 0° (north) → left = west, right = east
      final result = planner.plan([zone], approachBearing: 0.0);
      final left = result.firstWhere((w) => w.side == DetourSide.left);
      final right = result.firstWhere((w) => w.side == DetourSide.right);
      // With north approach bearing, left is west (lower lng) and right is east (higher lng)
      expect(left.position.longitude, lessThan(center.longitude));
      expect(right.position.longitude, greaterThan(center.longitude));
    });
  });
}
