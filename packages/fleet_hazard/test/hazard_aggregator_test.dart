import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.now();

  FleetReport makeReport({
    required String id,
    required double lat,
    required double lon,
    RoadCondition condition = RoadCondition.icy,
    double confidence = 0.8,
  }) {
    return FleetReport(
      vehicleId: id,
      position: LatLng(lat, lon),
      timestamp: now,
      condition: condition,
      confidence: confidence,
    );
  }

  group('HazardAggregator.aggregate', () {
    test('returns empty list for no reports', () {
      expect(HazardAggregator.aggregate([]), isEmpty);
    });

    test('returns empty list for non-hazard reports only', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.0, lon: 137.0, condition: RoadCondition.dry),
        makeReport(id: 'V-002', lat: 35.1, lon: 137.1, condition: RoadCondition.wet),
      ];

      expect(HazardAggregator.aggregate(reports), isEmpty);
    });

    test('creates single zone for one hazard report', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.05, lon: 137.25),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].reports.length, 1);
      expect(zones[0].center.latitude, closeTo(35.05, 0.001));
      expect(zones[0].center.longitude, closeTo(137.25, 0.001));
    });

    test('single report zone has minimum radius', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.05, lon: 137.25),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].radiusMeters, HazardAggregator.minZoneRadius);
    });

    test('clusters nearby hazard reports into one zone', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.050, lon: 137.250),
        makeReport(id: 'V-002', lat: 35.052, lon: 137.252),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].reports.length, 2);
      expect(zones[0].vehicleCount, 2);
    });

    test('separates distant hazard reports into different zones', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.05, lon: 137.25),
        makeReport(id: 'V-002', lat: 35.20, lon: 137.40),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 2);
      expect(zones[0].reports.length, 1);
      expect(zones[1].reports.length, 1);
    });

    test('filters out non-hazard reports from clusters', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.05, lon: 137.25, condition: RoadCondition.icy),
        makeReport(id: 'V-002', lat: 35.052, lon: 137.252, condition: RoadCondition.dry),
        makeReport(id: 'V-003', lat: 35.051, lon: 137.251, condition: RoadCondition.snowy),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].reports.length, 2);
    });

    test('zone severity is icy when any report is icy', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.05, lon: 137.25, condition: RoadCondition.snowy),
        makeReport(id: 'V-002', lat: 35.052, lon: 137.252, condition: RoadCondition.icy),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].severity, HazardSeverity.icy);
    });

    test('zone severity is snowy when no icy reports', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.05, lon: 137.25, condition: RoadCondition.snowy),
        makeReport(id: 'V-002', lat: 35.052, lon: 137.252, condition: RoadCondition.snowy),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].severity, HazardSeverity.snowy);
    });

    test('zone center is average of report positions', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.050, lon: 137.250),
        makeReport(id: 'V-002', lat: 35.054, lon: 137.254),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].center.latitude, closeTo(35.052, 0.001));
      expect(zones[0].center.longitude, closeTo(137.252, 0.001));
    });

    test('zone radius is capped at maxZoneRadius', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.00, lon: 137.00),
        makeReport(id: 'V-002', lat: 35.04, lon: 137.04),
      ];

      final zones = HazardAggregator.aggregate(
        reports,
        clusterRadius: 10000,
      );
      expect(
        zones[0].radiusMeters,
        lessThanOrEqualTo(HazardAggregator.maxZoneRadius),
      );
    });

    test('custom cluster radius controls grouping', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.050, lon: 137.250),
        makeReport(id: 'V-002', lat: 35.054, lon: 137.254),
      ];

      final grouped = HazardAggregator.aggregate(reports, clusterRadius: 3000);
      expect(grouped.length, 1);

      final separated = HazardAggregator.aggregate(reports, clusterRadius: 100);
      expect(separated.length, 2);
    });

    test('single-linkage clusters chain of nearby reports', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.050, lon: 137.250),
        makeReport(id: 'V-002', lat: 35.055, lon: 137.255),
        makeReport(id: 'V-003', lat: 35.060, lon: 137.260),
      ];

      final zones = HazardAggregator.aggregate(
        reports,
        clusterRadius: 1000,
      );
      expect(zones.length, 1);
      expect(zones[0].reports.length, 3);
    });

    test('average confidence is preserved in built zone', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.050, lon: 137.250, confidence: 0.6),
        makeReport(id: 'V-002', lat: 35.052, lon: 137.252, confidence: 1.0),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].averageConfidence, closeTo(0.8, 0.001));
    });

    test('returns unmodifiable report list inside zone', () {
      final reports = [
        makeReport(id: 'V-001', lat: 35.050, lon: 137.250),
      ];

      final zones = HazardAggregator.aggregate(reports);
      expect(
        () => zones[0].reports.add(
          makeReport(id: 'V-002', lat: 35.051, lon: 137.251),
        ),
        throwsUnsupportedError,
      );
    });
  });
}