import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

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
        makeReport(id: 'v1', lat: 35.0, lon: 137.0, condition: RoadCondition.dry),
        makeReport(id: 'v2', lat: 35.1, lon: 137.1, condition: RoadCondition.wet),
      ];
      expect(HazardAggregator.aggregate(reports), isEmpty);
    });

    test('creates single zone for one hazard report', () {
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].reports.length, 1);
      expect(zones[0].center.latitude, closeTo(35.05, 0.001));
      expect(zones[0].center.longitude, closeTo(137.25, 0.001));
    });

    test('single report zone has minimum radius', () {
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].radiusMeters, HazardAggregator.minZoneRadius);
    });

    test('clusters nearby hazard reports into one zone', () {
      // Two reports ~500m apart (same general area).
      final reports = [
        makeReport(id: 'v1', lat: 35.050, lon: 137.250),
        makeReport(id: 'v2', lat: 35.052, lon: 137.252),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].reports.length, 2);
      expect(zones[0].vehicleCount, 2);
    });

    test('separates distant hazard reports into different zones', () {
      // Two reports ~20km apart.
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25),
        makeReport(id: 'v2', lat: 35.20, lon: 137.40),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 2);
      expect(zones[0].reports.length, 1);
      expect(zones[1].reports.length, 1);
    });

    test('filters out non-hazard reports from clusters', () {
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25, condition: RoadCondition.icy),
        makeReport(id: 'v2', lat: 35.052, lon: 137.252, condition: RoadCondition.dry),
        makeReport(id: 'v3', lat: 35.051, lon: 137.251, condition: RoadCondition.snowy),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      // Only icy and snowy reports, not the dry one.
      expect(zones[0].reports.length, 2);
    });

    test('zone severity is icy when any report is icy', () {
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25, condition: RoadCondition.snowy),
        makeReport(id: 'v2', lat: 35.052, lon: 137.252, condition: RoadCondition.icy),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].severity, HazardSeverity.icy);
    });

    test('zone severity is snowy when no icy reports', () {
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25, condition: RoadCondition.snowy),
        makeReport(id: 'v2', lat: 35.052, lon: 137.252, condition: RoadCondition.snowy),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].severity, HazardSeverity.snowy);
    });

    test('zone center is average of report positions', () {
      // Two reports ~300m apart — well within default 3km cluster radius.
      final reports = [
        makeReport(id: 'v1', lat: 35.050, lon: 137.250),
        makeReport(id: 'v2', lat: 35.054, lon: 137.254),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones.length, 1);
      expect(zones[0].center.latitude, closeTo(35.052, 0.001));
      expect(zones[0].center.longitude, closeTo(137.252, 0.001));
    });

    test('zone radius is capped at maxZoneRadius', () {
      // Reports spread across a wide area but within cluster radius.
      final reports = [
        makeReport(id: 'v1', lat: 35.00, lon: 137.00),
        makeReport(id: 'v2', lat: 35.04, lon: 137.04),
      ];
      final zones = HazardAggregator.aggregate(
        reports,
        clusterRadius: 10000, // very wide cluster
      );
      expect(
        zones[0].radiusMeters,
        lessThanOrEqualTo(HazardAggregator.maxZoneRadius),
      );
    });

    test('average confidence is computed across reports', () {
      final reports = [
        makeReport(id: 'v1', lat: 35.05, lon: 137.25, confidence: 0.6),
        makeReport(id: 'v2', lat: 35.052, lon: 137.252, confidence: 1.0),
      ];
      final zones = HazardAggregator.aggregate(reports);
      expect(zones[0].averageConfidence, closeTo(0.8, 0.001));
    });

    test('custom cluster radius controls grouping', () {
      // Two reports ~500m apart. Default 3000m groups them; 100m separates.
      final reports = [
        makeReport(id: 'v1', lat: 35.050, lon: 137.250),
        makeReport(id: 'v2', lat: 35.054, lon: 137.254),
      ];

      final grouped = HazardAggregator.aggregate(reports, clusterRadius: 3000);
      expect(grouped.length, 1);

      final separated = HazardAggregator.aggregate(reports, clusterRadius: 100);
      expect(separated.length, 2);
    });

    test('single-linkage clusters chain of nearby reports', () {
      // A-B within 1km, B-C within 1km, but A-C ~2km apart.
      // Single-linkage should put all three in one cluster.
      final reports = [
        makeReport(id: 'v1', lat: 35.050, lon: 137.250), // A
        makeReport(id: 'v2', lat: 35.055, lon: 137.255), // B (~700m from A)
        makeReport(id: 'v3', lat: 35.060, lon: 137.260), // C (~700m from B, ~1.4km from A)
      ];
      final zones = HazardAggregator.aggregate(
        reports,
        clusterRadius: 1000,
      );
      expect(zones.length, 1);
      expect(zones[0].reports.length, 3);
    });
  });

  group('HazardZone', () {
    test('vehicleCount counts unique vehicle IDs', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [
          makeReport(id: 'v1', lat: 35.05, lon: 137.25),
          makeReport(id: 'v1', lat: 35.05, lon: 137.25), // same vehicle
          makeReport(id: 'v2', lat: 35.05, lon: 137.25),
        ],
        severity: HazardSeverity.icy,
      );
      expect(zone.vehicleCount, 2);
    });

    test('averageConfidence handles empty reports', () {
      const zone = HazardZone(
        center: LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [],
        severity: HazardSeverity.snowy,
      );
      expect(zone.averageConfidence, 0);
    });

    test('toString contains severity and report count', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 1000,
        reports: [
          makeReport(id: 'v1', lat: 35.05, lon: 137.25),
        ],
        severity: HazardSeverity.icy,
      );
      expect(zone.toString(), contains('icy'));
      expect(zone.toString(), contains('1 reports'));
    });
  });
}
