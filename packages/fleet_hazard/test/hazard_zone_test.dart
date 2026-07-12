import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime(2026, 3, 8);

  ZoneObservation makeObs({
    RoadCondition condition = RoadCondition.icy,
    double confidence = 0.8,
  }) {
    return ZoneObservation(
      position: const LatLng(35.05, 137.25),
      timestamp: now,
      condition: condition,
      confidence: confidence,
    );
  }

  group('HazardZone', () {
    test('vehicleCount is the stored unique-vehicle count', () {
      // After anonymization, vehicleCount can no longer be derived from the
      // retained observations (they carry no vehicleId); it is supplied at
      // aggregation time and stored.
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [makeObs(), makeObs(), makeObs()],
        severity: HazardSeverity.icy,
        vehicleCount: 2,
      );

      expect(zone.vehicleCount, 2);
    });

    test('retained observations carry no re-identification key', () {
      // Two observations built from FleetReports of DIFFERENT vehicles but
      // identical position/condition/timestamp/confidence are equal — proof
      // that vehicleId is gone (it cannot distinguish them).
      final a = ZoneObservation.fromReport(
        FleetReport(
          vehicleId: 'V-001',
          position: const LatLng(35.05, 137.25),
          timestamp: now,
          condition: RoadCondition.icy,
          confidence: 0.8,
        ),
      );
      final b = ZoneObservation.fromReport(
        FleetReport(
          vehicleId: 'V-999',
          position: const LatLng(35.05, 137.25),
          timestamp: now,
          condition: RoadCondition.icy,
          confidence: 0.8,
        ),
      );

      expect(a, equals(b));
      expect(a.props.contains('V-001'), isFalse);
      expect(a.props.contains('V-999'), isFalse);
    });

    test('averageConfidence is computed across observations', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [
          makeObs(confidence: 0.6),
          makeObs(confidence: 1.0),
        ],
        severity: HazardSeverity.icy,
        vehicleCount: 2,
      );

      expect(zone.averageConfidence, closeTo(0.8, 0.001));
    });

    // INVERTED at 0.6.0. This test used to assert `averageConfidence == 0` for a zone
    // with no observations — i.e. it asserted the fabrication as correct behaviour.
    // A zone nobody has reported is not a zone everybody doubts. It knows nothing, and
    // it must now SAY nothing (null), never a number a consumer could act on.
    test('averageConfidence is NULL (not 0) when there are no observations', () {
      const zone = HazardZone(
        center: LatLng(35.05, 137.25),
        radiusMeters: 500,
        reports: [],
        severity: HazardSeverity.snowy,
        vehicleCount: 0,
      );

      expect(zone.averageConfidence, isNull);
    });

    test('equatable: same values are equal', () {
      final reports = [makeObs(confidence: 0.9)];
      final a = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );
      final b = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('equatable: different vehicleCount is not equal', () {
      final reports = [makeObs()];
      final one = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );
      final two = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 2,
      );

      expect(one, isNot(equals(two)));
    });

    test('equatable: different severity is not equal', () {
      final reports = [makeObs(condition: RoadCondition.snowy)];
      final snowy = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.snowy,
        vehicleCount: 1,
      );
      final icy = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );

      expect(snowy, isNot(equals(icy)));
    });

    test('equatable: different radius is not equal', () {
      final reports = [makeObs()];
      final small = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 700,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );
      final large = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 1000,
        reports: reports,
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );

      expect(small, isNot(equals(large)));
    });

    test('toString includes severity and report count', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 1000,
        reports: [makeObs()],
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );

      final str = zone.toString();
      expect(str, contains('icy'));
      expect(str, contains('1 reports'));
      expect(str, contains('1000m'));
    });

    test('toString does not leak a vehicleId', () {
      final zone = HazardZone(
        center: const LatLng(35.05, 137.25),
        radiusMeters: 1000,
        reports: [makeObs()],
        severity: HazardSeverity.icy,
        vehicleCount: 1,
      );

      expect(zone.reports.first.toString(), isNot(contains('V-')));
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
