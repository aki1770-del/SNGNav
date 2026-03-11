import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 3, 8);

  FleetReport makeReport({
    required String id,
    RoadCondition condition = RoadCondition.icy,
    double confidence = 0.8,
  }) {
    return FleetReport(
      vehicleId: id,
      position: const LatLng(35.05, 137.25),
      timestamp: now,
      condition: condition,
      confidence: confidence,
    );
  }

  group('HazardZone', () {
    test('vehicleCount counts unique vehicle ids', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [
          makeReport(id: 'V-001'),
          makeReport(id: 'V-001'),
          makeReport(id: 'V-002'),
        ],
        severity: HazardSeverity.icy,
      );

      expect(zone.vehicleCount, 2);
    });

    test('averageConfidence is computed across reports', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [
          makeReport(id: 'V-001', confidence: 0.6),
          makeReport(id: 'V-002', confidence: 1.0),
        ],
        severity: HazardSeverity.icy,
      );

      expect(zone.averageConfidence, closeTo(0.8, 0.001));
    });

    test('averageConfidence is zero for empty reports', () {
      const zone = HazardZone(
        center: LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [],
        severity: HazardSeverity.snowy,
      );

      expect(zone.averageConfidence, 0);
    });

    test('equatable: same values are equal', () {
      final reports = [makeReport(id: 'V-001', confidence: 0.9)];
      final a = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
      );
      final b = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equatable: different severity is not equal', () {
      final reports = [makeReport(id: 'V-001', condition: RoadCondition.snowy)];
      final snowy = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.snowy,
      );
      final icy = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
      );

      expect(snowy, isNot(equals(icy)));
    });

    test('equatable: different radius is not equal', () {
      final reports = [makeReport(id: 'V-001')];
      final small = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
      );
      final large = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 1000,
        reports: reports,
        severity: HazardSeverity.icy,
      );

      expect(small, isNot(equals(large)));
    });

    test('toString includes severity and report count', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 1000,
        reports: [makeReport(id: 'V-001')],
        severity: HazardSeverity.icy,
      );

      final str = zone.toString();
      expect(str, contains('icy'));
      expect(str, contains('1 reports'));
      expect(str, contains('1000m'));
    });
  });

  group('HazardSeverity', () {
    test('has exactly 2 values', () {
      expect(HazardSeverity.values, hasLength(2));
    });

    test('values are icy and snowy', () {
      expect(
        HazardSeverity.values.map((value) => value.name),
        containsAll(['icy', 'snowy']),
      );
    });
  });
}