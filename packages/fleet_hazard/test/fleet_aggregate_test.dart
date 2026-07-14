import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  FleetReport report({
    required String id,
    required RoadCondition condition,
    double lat = 35.050,
    double lon = 137.250,
    Duration age = Duration.zero,
    double confidence = 0.8,
  }) {
    return FleetReport(
      vehicleId: id,
      position: LatLng(lat, lon),
      timestamp: DateTime.now().subtract(age),
      condition: condition,
      confidence: confidence,
    );
  }

  group('the three worlds aggregate() collapsed into one empty list', () {
    // The defect: all three of these produce `[]` from aggregate(). The point
    // of FleetAggregate is that they are no longer indistinguishable.

    test('world 1 — nobody reported the road: isSilent', () {
      final result = HazardAggregator.aggregateWithProvenance([]);

      expect(result.isSilent, isTrue);
      expect(result.isMeasuredClear, isFalse);
      expect(result.isAllUnknown, isFalse);
      expect(result.reportCount, 0);
      expect(result.unknownCount, 0);
      expect(result.zones, isEmpty);
      expect(
        result.freshestReportAt,
        isNull,
        reason:
            'nothing was reported, so there is no freshest report; null '
            'means NOT KNOWN and must never be coalesced into a time',
      );
    });

    test('world 2 — the fleet drove it and it was clear: isMeasuredClear', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(id: 'V-001', condition: RoadCondition.dry),
        report(id: 'V-002', condition: RoadCondition.wet),
      ]);

      expect(result.isMeasuredClear, isTrue);
      expect(result.isSilent, isFalse);
      expect(result.isAllUnknown, isFalse);
      expect(result.reportCount, 2);
      expect(result.unknownCount, 0);
      expect(result.knownCount, 2);
      expect(result.zones, isEmpty);
      expect(result.freshestReportAt, isNotNull);
    });

    test('world 3 — driven, and nobody could read it: isAllUnknown', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(id: 'V-001', condition: RoadCondition.unknown),
        report(id: 'V-002', condition: RoadCondition.unknown),
      ]);

      expect(result.isAllUnknown, isTrue);
      expect(
        result.isMeasuredClear,
        isFalse,
        reason: 'a road nobody could read is NOT a clear road',
      );
      expect(result.isSilent, isFalse);
      expect(result.reportCount, 2);
      expect(result.unknownCount, 2);
      expect(result.knownCount, 0);
      expect(result.zones, isEmpty);
    });

    test('the three worlds are mutually distinguishable', () {
      final silent = HazardAggregator.aggregateWithProvenance([]);
      final clear = HazardAggregator.aggregateWithProvenance([
        report(id: 'V-001', condition: RoadCondition.dry),
      ]);
      final unknown = HazardAggregator.aggregateWithProvenance([
        report(id: 'V-001', condition: RoadCondition.unknown),
      ]);

      // All three still yield zero zones — which is exactly why the bare list
      // could never be trusted.
      expect(silent.zones, isEmpty);
      expect(clear.zones, isEmpty);
      expect(unknown.zones, isEmpty);

      // But each satisfies exactly one predicate, and no two agree.
      expect(
        [silent.isSilent, silent.isMeasuredClear, silent.isAllUnknown],
        [true, false, false],
      );
      expect(
        [clear.isSilent, clear.isMeasuredClear, clear.isAllUnknown],
        [false, true, false],
      );
      expect(
        [unknown.isSilent, unknown.isMeasuredClear, unknown.isAllUnknown],
        [false, false, true],
      );
    });

    test('a partially-unreadable road is neither clear nor silent', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(id: 'V-001', condition: RoadCondition.dry),
        report(id: 'V-002', condition: RoadCondition.unknown),
      ]);

      expect(
        result.isMeasuredClear,
        isFalse,
        reason: 'one vehicle could not read the road; that is not all-clear',
      );
      expect(result.isAllUnknown, isFalse);
      expect(result.isSilent, isFalse);
      expect(result.unknownCount, 1);
      expect(result.knownCount, 1);
    });

    test('a hazard is still found, and is not any of the empty worlds', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(id: 'V-001', condition: RoadCondition.icy),
      ]);

      expect(result.hasHazards, isTrue);
      expect(result.zones, hasLength(1));
      expect(result.zones.single.severity, HazardSeverity.icy);
      expect(result.isSilent, isFalse);
      expect(result.isMeasuredClear, isFalse);
      expect(result.isAllUnknown, isFalse);
      expect(result.reportCount, 1);
    });
  });

  group('recency — the "last 30 min" the API previously could not keep', () {
    test('stale reports are excluded from clustering when maxAge is set', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(
          id: 'V-OLD',
          condition: RoadCondition.icy,
          age: const Duration(hours: 3),
        ),
      ], maxAge: const Duration(minutes: 30));

      expect(result.zones, isEmpty, reason: 'the icy report is 3 hours old');
      expect(result.staleCount, 1);
      expect(result.reportCount, 0);
      expect(
        result.isSilent,
        isTrue,
        reason:
            'every report aged out, so we now know nothing fresh — and '
            'that is silence, not an all-clear',
      );
      expect(result.isMeasuredClear, isFalse);
    });

    test('fresh reports survive the same window', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(
          id: 'V-NEW',
          condition: RoadCondition.icy,
          age: const Duration(minutes: 5),
        ),
      ], maxAge: const Duration(minutes: 30));

      expect(result.zones, hasLength(1));
      expect(result.staleCount, 0);
      expect(result.reportCount, 1);
      expect(result.hasHazards, isTrue);
    });

    test('maxAge splits a mixed-age fleet', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(
          id: 'V-NEW',
          condition: RoadCondition.dry,
          age: const Duration(minutes: 2),
        ),
        report(
          id: 'V-OLD',
          condition: RoadCondition.icy,
          age: const Duration(hours: 5),
        ),
      ], maxAge: const Duration(minutes: 30));

      expect(result.reportCount, 1);
      expect(result.staleCount, 1);
      expect(
        result.isMeasuredClear,
        isTrue,
        reason: 'the only fresh report says dry; the icy one is 5 hours stale',
      );
      expect(result.zones, isEmpty);
    });

    test('freshestReportAt tracks the newest considered report', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(
          id: 'V-001',
          condition: RoadCondition.dry,
          age: const Duration(hours: 2),
        ),
        report(
          id: 'V-002',
          condition: RoadCondition.dry,
          age: const Duration(minutes: 1),
        ),
      ]);

      expect(result.freshestReportAt, isNotNull);
      expect(
        DateTime.now().difference(result.freshestReportAt!),
        lessThan(const Duration(minutes: 2)),
      );
    });

    test('without maxAge no recency filter is applied at all', () {
      final result = HazardAggregator.aggregateWithProvenance([
        report(
          id: 'V-ANCIENT',
          condition: RoadCondition.icy,
          age: const Duration(days: 30),
        ),
      ]);

      expect(
        result.zones,
        hasLength(1),
        reason:
            'a 30-day-old report still counts when no maxAge is given — '
            'stated plainly rather than silently assumed fresh',
      );
      expect(result.staleCount, 0);
      expect(result.reportCount, 1);
    });
  });

  group('regression — aggregate() behavior is unchanged', () {
    // 0.5.1 is an in-range patch. Every existing caller must be unaffected.

    test('still returns an empty list for no reports', () {
      expect(HazardAggregator.aggregate([]), isEmpty);
    });

    test('still returns an empty list for an all-clear fleet', () {
      expect(
        HazardAggregator.aggregate([
          report(id: 'V-001', condition: RoadCondition.dry),
          report(id: 'V-002', condition: RoadCondition.wet),
        ]),
        isEmpty,
      );
    });

    test('still drops unknown reports silently', () {
      expect(
        HazardAggregator.aggregate([
          report(id: 'V-001', condition: RoadCondition.unknown),
        ]),
        isEmpty,
        reason:
            'unchanged by design — the fix is the new accessor, not a '
            'behavior change to the method existing callers already depend on',
      );
    });

    test('still applies NO recency filter', () {
      expect(
        HazardAggregator.aggregate([
          report(
            id: 'V-ANCIENT',
            condition: RoadCondition.icy,
            age: const Duration(days: 365),
          ),
        ]),
        hasLength(1),
      );
    });

    test('still clusters hazards identically to the new method', () {
      final reports = [
        report(id: 'V-001', condition: RoadCondition.icy, lat: 35.050),
        report(id: 'V-002', condition: RoadCondition.snowy, lat: 35.052),
        report(id: 'V-003', condition: RoadCondition.snowy, lat: 35.400),
        report(id: 'V-004', condition: RoadCondition.dry, lat: 35.060),
      ];

      final old = HazardAggregator.aggregate(reports);
      final fresh = HazardAggregator.aggregateWithProvenance(reports);

      expect(old, hasLength(2));
      expect(
        fresh.zones,
        equals(old),
        reason:
            'the new method runs the same clustering; it only adds the '
            'provenance the old one could not report',
      );
    });

    test('still honors a custom clusterRadius identically', () {
      final reports = [
        report(id: 'V-001', condition: RoadCondition.icy, lat: 35.050),
        report(id: 'V-002', condition: RoadCondition.icy, lat: 35.090),
      ];

      final old = HazardAggregator.aggregate(reports, clusterRadius: 1000);
      final fresh = HazardAggregator.aggregateWithProvenance(
        reports,
        clusterRadius: 1000,
      );

      expect(old, hasLength(2), reason: 'too far apart to cluster at 1km');
      expect(fresh.zones, equals(old));
    });
  });
}
