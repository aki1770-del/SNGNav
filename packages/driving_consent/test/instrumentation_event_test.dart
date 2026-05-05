import 'package:driving_consent/driving_consent.dart';
import 'package:test/test.dart';

void main() {
  group('InstrumentationEvent sealed hierarchy', () {
    test('AlertFired is an InstrumentationEvent', () {
      final ev = AlertFired(
        timestamp: DateTime(2026, 5, 5, 9),
        driverPseudonym: 'pseudo-1',
        alertClass: 'snow_road_warning',
        severity: AlertSeverityClass.warning,
        modalDuration: const Duration(seconds: 6),
        dismissalState: AlertDismissalState.ranToCompletion,
        driverProfile: DriverProfileClass.snowZoneExperienced,
      );

      expect(ev, isA<InstrumentationEvent>());
      expect(ev.alertClass, 'snow_road_warning');
      expect(ev.severity, AlertSeverityClass.warning);
    });

    test('VoicePaceAdjusted is an InstrumentationEvent', () {
      final ev = VoicePaceAdjusted(
        timestamp: DateTime(2026, 5, 5, 9),
        driverPseudonym: 'pseudo-1',
        previousRate: 1.0,
        newRate: 0.8,
        adjustmentReason: VoicePaceAdjustmentReason.driverPreference,
        driverProfile: DriverProfileClass.ageingRural,
      );

      expect(ev, isA<InstrumentationEvent>());
      expect(ev.previousRate, 1.0);
      expect(ev.newRate, 0.8);
    });

    test('exhaustive switch over sealed subtypes type-checks', () {
      final events = <InstrumentationEvent>[
        AlertFired(
          timestamp: DateTime(2026, 5, 5, 9),
          driverPseudonym: 'p',
          alertClass: 'a',
          severity: AlertSeverityClass.info,
          modalDuration: const Duration(seconds: 1),
          dismissalState: AlertDismissalState.ranToCompletion,
          driverProfile: DriverProfileClass.defaultProfile,
        ),
        VoicePaceAdjusted(
          timestamp: DateTime(2026, 5, 5, 9, 1),
          driverPseudonym: 'p',
          previousRate: 1.0,
          newRate: 0.9,
          adjustmentReason: VoicePaceAdjustmentReason.driverPreference,
          driverProfile: DriverProfileClass.defaultProfile,
        ),
        CohortMultiplierObserved(
          timestamp: DateTime(2026, 5, 5, 9, 2),
          driverPseudonym: 'p',
          driverProfile: DriverProfileClass.snowZoneExperienced,
          cohortMultiplierClass: CohortMultiplierClass.snowZoneExperienced,
          appliedMultiplier: 1.25,
          observedFitClass: ObservedFitClass.goodFit,
        ),
        TripContextCaptured(
          timestamp: DateTime(2026, 5, 5, 9, 3),
          driverPseudonym: 'p',
          vehicleClass: VehicleClass.passengerCar,
          passengerPresenceClass: PassengerPresenceClass.driverOnly,
          timeOfDayClass: TimeOfDayClass.day,
          consecutiveDrivingDayClass: ConsecutiveDrivingDayClass.firstDay,
          driverProfile: DriverProfileClass.defaultProfile,
        ),
      ];

      // Exhaustive switch: missing a subtype would fail to compile.
      for (final ev in events) {
        final label = switch (ev) {
          AlertFired() => 'alert',
          VoicePaceAdjusted() => 'voice',
          CohortMultiplierObserved() => 'cohort',
          TripContextCaptured() => 'trip',
        };
        expect(label, isNotEmpty);
      }
    });

    test('equatable: same field values are equal', () {
      final t = DateTime(2026, 5, 5, 9);
      final a = AlertFired(
        timestamp: t,
        driverPseudonym: 'p',
        alertClass: 'snow_road_warning',
        severity: AlertSeverityClass.warning,
        modalDuration: const Duration(seconds: 6),
        dismissalState: AlertDismissalState.ranToCompletion,
        driverProfile: DriverProfileClass.snowZoneExperienced,
      );
      final b = AlertFired(
        timestamp: t,
        driverPseudonym: 'p',
        alertClass: 'snow_road_warning',
        severity: AlertSeverityClass.warning,
        modalDuration: const Duration(seconds: 6),
        dismissalState: AlertDismissalState.ranToCompletion,
        driverProfile: DriverProfileClass.snowZoneExperienced,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('TripContextCaptured carries no GPS or destination fields', () {
      // Sakichi-tag: zero GPS, zero destination, zero PII.
      // Verified by inspecting the props list — only coarse class enums
      // and the timestamp/pseudonym carried.
      final ev = TripContextCaptured(
        timestamp: DateTime(2026, 5, 5, 9),
        driverPseudonym: 'p',
        vehicleClass: VehicleClass.passengerCar,
        passengerPresenceClass: PassengerPresenceClass.driverOnly,
        timeOfDayClass: TimeOfDayClass.evening,
        consecutiveDrivingDayClass: ConsecutiveDrivingDayClass.fourToSix,
        driverProfile: DriverProfileClass.foreignTouristSnowZone,
      );

      // Spot-check: each prop is one of the coarse enum classes / opaque
      // pseudonym / timestamp.
      for (final p in ev.props) {
        expect(
          p is DateTime ||
              p is String ||
              p is VehicleClass ||
              p is PassengerPresenceClass ||
              p is TimeOfDayClass ||
              p is ConsecutiveDrivingDayClass ||
              p is DriverProfileClass,
          isTrue,
          reason: 'TripContextCaptured field is not a coarse-class enum: $p',
        );
      }
    });
  });
}
