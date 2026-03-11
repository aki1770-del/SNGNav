import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('FleetReport', () {
    test('snowy report isHazard is true', () {
      final report = FleetReport(
        vehicleId: 'V-001',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.snowy,
      );

      expect(report.isHazard, true);
    });

    test('icy report isHazard is true', () {
      final report = FleetReport(
        vehicleId: 'V-002',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.icy,
      );

      expect(report.isHazard, true);
    });

    test('dry report isHazard is false', () {
      final report = FleetReport(
        vehicleId: 'V-003',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.dry,
      );

      expect(report.isHazard, false);
    });

    test('wet report isHazard is false', () {
      final report = FleetReport(
        vehicleId: 'V-004',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.wet,
      );

      expect(report.isHazard, false);
    });

    test('unknown report isHazard is false', () {
      final report = FleetReport(
        vehicleId: 'V-005',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.unknown,
      );

      expect(report.isHazard, false);
    });

    test('recent report isRecent is true with default max age', () {
      final report = FleetReport(
        vehicleId: 'V-006',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        condition: RoadCondition.snowy,
      );

      expect(report.isRecent(), true);
    });

    test('stale report isRecent is false with default max age', () {
      final report = FleetReport(
        vehicleId: 'V-007',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
        condition: RoadCondition.snowy,
      );

      expect(report.isRecent(), false);
    });

    test('custom max age is respected', () {
      final report = FleetReport(
        vehicleId: 'V-008',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
        condition: RoadCondition.snowy,
      );

      expect(report.isRecent(maxAge: const Duration(minutes: 30)), true);
    });

    test('default confidence is 0.8', () {
      final report = FleetReport(
        vehicleId: 'V-009',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.wet,
      );

      expect(report.confidence, 0.8);
    });

    test('equatable: same values are equal', () {
      final timestamp = DateTime(2026, 3, 8);
      final a = FleetReport(
        vehicleId: 'V-010',
        position: const LatLng(35.05, 137.25),
        timestamp: timestamp,
        condition: RoadCondition.icy,
        confidence: 0.9,
      );
      final b = FleetReport(
        vehicleId: 'V-010',
        position: const LatLng(35.05, 137.25),
        timestamp: timestamp,
        condition: RoadCondition.icy,
        confidence: 0.9,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equatable: different condition is not equal', () {
      final timestamp = DateTime(2026, 3, 8);
      final snowy = FleetReport(
        vehicleId: 'V-011',
        position: const LatLng(35.05, 137.25),
        timestamp: timestamp,
        condition: RoadCondition.snowy,
      );
      final icy = FleetReport(
        vehicleId: 'V-011',
        position: const LatLng(35.05, 137.25),
        timestamp: timestamp,
        condition: RoadCondition.icy,
      );

      expect(snowy, isNot(equals(icy)));
    });

    test('equatable: different confidence is not equal', () {
      final timestamp = DateTime(2026, 3, 8);
      final low = FleetReport(
        vehicleId: 'V-012',
        position: const LatLng(35.05, 137.25),
        timestamp: timestamp,
        condition: RoadCondition.snowy,
        confidence: 0.6,
      );
      final high = FleetReport(
        vehicleId: 'V-012',
        position: const LatLng(35.05, 137.25),
        timestamp: timestamp,
        condition: RoadCondition.snowy,
        confidence: 0.9,
      );

      expect(low, isNot(equals(high)));
    });

    test('toString includes vehicle id, condition, and confidence', () {
      final report = FleetReport(
        vehicleId: 'V-013',
        position: const LatLng(35.05, 137.25),
        timestamp: DateTime(2026, 3, 8),
        condition: RoadCondition.icy,
        confidence: 0.95,
      );

      final str = report.toString();
      expect(str, contains('V-013'));
      expect(str, contains('icy'));
      expect(str, contains('conf=0.95'));
    });
  });

  group('RoadCondition', () {
    test('has exactly 5 values', () {
      expect(RoadCondition.values, hasLength(5));
    });

    test('values contain dry, wet, snowy, icy, unknown', () {
      expect(
        RoadCondition.values.map((value) => value.name),
        containsAll(['dry', 'wet', 'snowy', 'icy', 'unknown']),
      );
    });
  });
}