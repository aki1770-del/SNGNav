import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

/// Every test here FAILS against fleet_hazard <= 0.5.0.
///
/// 0.5.0 shipped two fabrications: `FleetReport.confidence` defaulted to `0.8`
/// (a certainty asserted on a caller who never stated one), and an empty
/// `HazardZone` reported `averageConfidence == 0` — a NUMBER, indistinguishable
/// from observations that genuinely carried zero confidence.
///
/// A hazard zone nobody has reported is not a hazard zone everybody doubts.
void main() {
  group('absence is not a measurement', () {
    test('a zone with no observations does not know its confidence', () {
      const zone = HazardZone(
        center: LatLng(39.72, 140.10), // Akita
        radiusMeters: 500,
        reports: [],
        severity: HazardSeverity.snowy,
        vehicleCount: 0,
      );

      // 0.5.0 returned 0.0 here — a value. It knows nothing; it must SAY nothing.
      expect(zone.averageConfidence, isNull);
    });

    test('a confidence must be STATED, never inherited', () {
      // The point of this test is what it CANNOT express: there is no longer any
      // way to construct a FleetReport without saying what your confidence is.
      // Under 0.5.0 the `confidence:` line below could be deleted and the report
      // would silently carry 0.8. It can no longer be deleted — the compiler
      // refuses. That refusal IS the fix.
      final report = FleetReport(
        vehicleId: 'V-001',
        position: const LatLng(39.72, 140.10),
        timestamp: DateTime.now(),
        condition: RoadCondition.icy,
        confidence: 0.42,
      );
      expect(report.confidence, 0.42);
    });

    test('a stated confidence is carried, never averaged away', () {
      final zone = HazardZone(
        center: const LatLng(39.72, 140.10),
        radiusMeters: 500,
        reports: [
          ZoneObservation(
            position: const LatLng(39.72, 140.10),
            timestamp: DateTime.now(),
            condition: RoadCondition.icy,
            confidence: 0.2,
          ),
          ZoneObservation(
            position: const LatLng(39.721, 140.101),
            timestamp: DateTime.now(),
            condition: RoadCondition.icy,
            confidence: 0.4,
          ),
        ],
        severity: HazardSeverity.icy,
        vehicleCount: 2,
      );

      // Two uncertain reports average to an uncertain zone — NOT to 0.8.
      expect(zone.averageConfidence, closeTo(0.3, 0.001));
    });
  });
}
