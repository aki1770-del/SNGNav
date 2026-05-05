import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('CircadianPhase — multiplier bounds (caution-add-only)', () {
    test('every phase multiplier is >= 1.0 (caution-add-only floor)', () {
      for (final phase in CircadianPhase.values) {
        expect(
          phase.multiplier,
          greaterThanOrEqualTo(1.0),
          reason: 'CircadianPhase.${phase.name} multiplier must be >= 1.0',
        );
      }
    });

    test('every phase multiplier is <= 1.5 (lateNight cap)', () {
      for (final phase in CircadianPhase.values) {
        expect(
          phase.multiplier,
          lessThanOrEqualTo(1.5),
          reason: 'CircadianPhase.${phase.name} multiplier must be <= 1.5',
        );
      }
    });

    test('morning is the baseline (multiplier == 1.0)', () {
      expect(CircadianPhase.morning.multiplier, equals(1.0));
    });

    test('lateNight is the cap (multiplier == 1.5)', () {
      expect(CircadianPhase.lateNight.multiplier, equals(1.5));
    });

    test('phase ordering by multiplier: morning < evening < afternoon '
        '< earlyMorning < night < lateNight', () {
      // The qualitative ordering follows the chronobiology literature.
      expect(
        CircadianPhase.morning.multiplier,
        lessThan(CircadianPhase.evening.multiplier),
      );
      expect(
        CircadianPhase.evening.multiplier,
        lessThan(CircadianPhase.afternoon.multiplier),
      );
      expect(
        CircadianPhase.afternoon.multiplier,
        lessThan(CircadianPhase.earlyMorning.multiplier),
      );
      expect(
        CircadianPhase.earlyMorning.multiplier,
        lessThan(CircadianPhase.night.multiplier),
      );
      expect(
        CircadianPhase.night.multiplier,
        lessThan(CircadianPhase.lateNight.multiplier),
      );
    });
  });

  group('circadianPhaseFromHour — hour-to-phase mapping', () {
    test('hour 0..3 maps to lateNight', () {
      for (final h in [0, 1, 2, 3]) {
        expect(circadianPhaseFromHour(h), CircadianPhase.lateNight);
      }
    });

    test('hour 4..7 maps to earlyMorning', () {
      for (final h in [4, 5, 6, 7]) {
        expect(circadianPhaseFromHour(h), CircadianPhase.earlyMorning);
      }
    });

    test('hour 8..11 maps to morning', () {
      for (final h in [8, 9, 10, 11]) {
        expect(circadianPhaseFromHour(h), CircadianPhase.morning);
      }
    });

    test('hour 12..15 maps to afternoon', () {
      for (final h in [12, 13, 14, 15]) {
        expect(circadianPhaseFromHour(h), CircadianPhase.afternoon);
      }
    });

    test('hour 16..19 maps to evening', () {
      for (final h in [16, 17, 18, 19]) {
        expect(circadianPhaseFromHour(h), CircadianPhase.evening);
      }
    });

    test('hour 20..23 maps to night', () {
      for (final h in [20, 21, 22, 23]) {
        expect(circadianPhaseFromHour(h), CircadianPhase.night);
      }
    });

    test('out-of-range hour throws RangeError', () {
      expect(() => circadianPhaseFromHour(-1), throwsRangeError);
      expect(() => circadianPhaseFromHour(24), throwsRangeError);
      expect(() => circadianPhaseFromHour(100), throwsRangeError);
    });
  });

  group('CircadianPhase — composition with forDriverContext', () {
    test('lateNight phase raises warningVisibilityMeters above baseline', () {
      const dc = DriverContext(
        profile: DriverProfile.snowZoneExperienced,
        state: DriverState.alert,
      );
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final lifted = NavigationSafetyConfig.forDriverContext(
        dc,
        circadianPhase: CircadianPhase.lateNight,
      );
      expect(
        lifted.warningVisibilityMeters,
        greaterThan(base.warningVisibilityMeters),
      );
    });

    test('morning phase produces same warningVisibilityMeters as no-phase '
        '(multiplier 1.0)', () {
      const dc = DriverContext(
        profile: DriverProfile.snowZoneExperienced,
        state: DriverState.alert,
      );
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final morning = NavigationSafetyConfig.forDriverContext(
        dc,
        circadianPhase: CircadianPhase.morning,
      );
      expect(
        morning.warningVisibilityMeters,
        equals(base.warningVisibilityMeters),
      );
    });

    test('circadian-phase preserves score-floor tiers '
        '(severity-not-profile)', () {
      const dc = DriverContext(
        profile: DriverProfile.ageingRural,
        state: DriverState.alert,
      );
      final base = NavigationSafetyConfig.forDriverContext(dc);
      final lifted = NavigationSafetyConfig.forDriverContext(
        dc,
        circadianPhase: CircadianPhase.lateNight,
      );
      expect(lifted.safeScoreFloor, base.safeScoreFloor);
      expect(lifted.infoScoreFloor, base.infoScoreFloor);
      expect(lifted.warningScoreFloor, base.warningScoreFloor);
    });
  });
}
