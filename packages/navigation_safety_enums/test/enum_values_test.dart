import 'package:navigation_safety_enums/navigation_safety_enums.dart';
import 'package:test/test.dart';

void main() {
  group('AlertSeverity', () {
    test('cardinality is 3', () {
      expect(AlertSeverity.values.length, 3);
    });

    test('declaration order (load-bearing for .index comparison)', () {
      expect(AlertSeverity.values, const [
        AlertSeverity.info,
        AlertSeverity.warning,
        AlertSeverity.critical,
      ]);
    });

    test('names match expected', () {
      expect(AlertSeverity.info.name, 'info');
      expect(AlertSeverity.warning.name, 'warning');
      expect(AlertSeverity.critical.name, 'critical');
    });

    test('byName round-trip', () {
      expect(AlertSeverity.values.byName('info'), AlertSeverity.info);
      expect(AlertSeverity.values.byName('warning'), AlertSeverity.warning);
      expect(AlertSeverity.values.byName('critical'), AlertSeverity.critical);
    });

    test('.index ordering is monotonic (info < warning < critical)', () {
      expect(AlertSeverity.info.index, lessThan(AlertSeverity.warning.index));
      expect(AlertSeverity.warning.index,
          lessThan(AlertSeverity.critical.index));
    });
  });

  group('CircadianPhase', () {
    test('cardinality is 6', () {
      expect(CircadianPhase.values.length, 6);
    });

    test('declaration order', () {
      expect(CircadianPhase.values, const [
        CircadianPhase.earlyMorning,
        CircadianPhase.morning,
        CircadianPhase.afternoon,
        CircadianPhase.evening,
        CircadianPhase.night,
        CircadianPhase.lateNight,
      ]);
    });

    test('multipliers respect caution-add-only floor (>= 1.0) and cap (<= 1.5)',
        () {
      for (final phase in CircadianPhase.values) {
        expect(phase.multiplier, greaterThanOrEqualTo(1.0));
        expect(phase.multiplier, lessThanOrEqualTo(1.5));
      }
      expect(CircadianPhase.morning.multiplier, 1.0);
      expect(CircadianPhase.lateNight.multiplier, 1.5);
    });

    test('circadianPhaseFromHour boundary mapping', () {
      expect(circadianPhaseFromHour(0), CircadianPhase.lateNight);
      expect(circadianPhaseFromHour(3), CircadianPhase.lateNight);
      expect(circadianPhaseFromHour(4), CircadianPhase.earlyMorning);
      expect(circadianPhaseFromHour(7), CircadianPhase.earlyMorning);
      expect(circadianPhaseFromHour(8), CircadianPhase.morning);
      expect(circadianPhaseFromHour(11), CircadianPhase.morning);
      expect(circadianPhaseFromHour(12), CircadianPhase.afternoon);
      expect(circadianPhaseFromHour(15), CircadianPhase.afternoon);
      expect(circadianPhaseFromHour(16), CircadianPhase.evening);
      expect(circadianPhaseFromHour(19), CircadianPhase.evening);
      expect(circadianPhaseFromHour(20), CircadianPhase.night);
      expect(circadianPhaseFromHour(23), CircadianPhase.night);
    });

    test('circadianPhaseFromHour rejects out-of-range', () {
      expect(() => circadianPhaseFromHour(-1), throwsRangeError);
      expect(() => circadianPhaseFromHour(24), throwsRangeError);
    });
  });

  group('DriverState', () {
    test('cardinality is 4', () {
      expect(DriverState.values.length, 4);
    });

    test('declaration order', () {
      expect(DriverState.values, const [
        DriverState.alert,
        DriverState.fatigued,
        DriverState.distracted,
        DriverState.impairedVisibility,
      ]);
    });

    test('byName round-trip', () {
      expect(DriverState.values.byName('alert'), DriverState.alert);
      expect(DriverState.values.byName('fatigued'), DriverState.fatigued);
      expect(DriverState.values.byName('distracted'), DriverState.distracted);
      expect(DriverState.values.byName('impairedVisibility'),
          DriverState.impairedVisibility);
    });
  });

  group('DriverProfile', () {
    test('cardinality is 6', () {
      expect(DriverProfile.values.length, 6);
    });

    test('declaration order (snowZoneExperienced is fallback default)', () {
      expect(DriverProfile.values, const [
        DriverProfile.ageingRural,
        DriverProfile.snowZoneExperienced,
        DriverProfile.noviceUrban,
        DriverProfile.professional,
        DriverProfile.agriculturalForestry,
        DriverProfile.foreignTouristSnowZone,
      ]);
    });

    test('byName round-trip on all values', () {
      for (final profile in DriverProfile.values) {
        expect(DriverProfile.values.byName(profile.name), profile);
      }
    });

    test('foreignTouristSnowZone is present (added in 0.3.0 of NSC)', () {
      expect(
        DriverProfile.values.any((p) => p == DriverProfile.foreignTouristSnowZone),
        isTrue,
      );
    });
  });
}
