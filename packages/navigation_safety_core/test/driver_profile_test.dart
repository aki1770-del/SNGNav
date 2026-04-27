import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('DriverProfile enum value set', () {
    test('contains the v1 five profiles', () {
      expect(
        DriverProfile.values,
        equals(<DriverProfile>[
          DriverProfile.ageingRural,
          DriverProfile.snowZoneExperienced,
          DriverProfile.noviceUrban,
          DriverProfile.professional,
          DriverProfile.agriculturalForestry,
        ]),
        reason:
            'DriverProfile values changed. NavigationSafetyConfig.forProfile + downstream '
            'UX-default extensions assume a stable enum; any addition / removal / reorder '
            'requires deliberate audit of every consumer that switches on this enum.',
      );
    });
  });

  group('NavigationSafetyConfig.forProfile', () {
    test('snowZoneExperienced returns historical defaults', () {
      final c = NavigationSafetyConfig.forProfile(DriverProfile.snowZoneExperienced);
      final standard = NavigationSafetyConfig();
      expect(c, equals(standard));
    });

    test('professional matches snowZoneExperienced thresholds in v1', () {
      // Professional drivers' minimum-distraction optimization lives in
      // the Flutter UX layer; thresholds today match the standard profile.
      final pro = NavigationSafetyConfig.forProfile(DriverProfile.professional);
      final standard = NavigationSafetyConfig.forProfile(DriverProfile.snowZoneExperienced);
      expect(pro, equals(standard));
    });

    test('agriculturalForestry matches snowZoneExperienced thresholds in v1', () {
      final ag = NavigationSafetyConfig.forProfile(DriverProfile.agriculturalForestry);
      final standard = NavigationSafetyConfig.forProfile(DriverProfile.snowZoneExperienced);
      expect(ag, equals(standard));
    });

    test('ageingRural is more conservative than standard on every dimension', () {
      final ageing = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
      final standard = NavigationSafetyConfig.forProfile(DriverProfile.snowZoneExperienced);

      // Higher score floors → harder to be classified "safe", warns earlier
      expect(ageing.safeScoreFloor, greaterThan(standard.safeScoreFloor));
      expect(ageing.infoScoreFloor, greaterThan(standard.infoScoreFloor));
      expect(ageing.warningScoreFloor, greaterThan(standard.warningScoreFloor));

      // Higher temperature thresholds → warns at warmer temps (earlier in cooling)
      expect(ageing.infoTemperatureCelsius, greaterThan(standard.infoTemperatureCelsius));
      expect(ageing.warningTemperatureCelsius, greaterThan(standard.warningTemperatureCelsius));
      expect(ageing.criticalTemperatureCelsius, greaterThan(standard.criticalTemperatureCelsius));

      // Higher visibility thresholds → warns at better visibility (earlier in degradation)
      expect(ageing.infoVisibilityMeters, greaterThan(standard.infoVisibilityMeters));
      expect(ageing.warningVisibilityMeters, greaterThan(standard.warningVisibilityMeters));
      expect(ageing.criticalVisibilityMeters, greaterThan(standard.criticalVisibilityMeters));
    });

    test('noviceUrban has elevated visibility-warning thresholds', () {
      final novice = NavigationSafetyConfig.forProfile(DriverProfile.noviceUrban);
      final standard = NavigationSafetyConfig.forProfile(DriverProfile.snowZoneExperienced);

      // Novice drivers warned earlier on visibility (less low-vis experience)
      expect(novice.infoVisibilityMeters, greaterThan(standard.infoVisibilityMeters));
      expect(novice.warningVisibilityMeters, greaterThan(standard.warningVisibilityMeters));
      expect(novice.criticalVisibilityMeters, greaterThan(standard.criticalVisibilityMeters));

      // Higher safe-score floor (need more comfort margin to be "safe")
      expect(novice.safeScoreFloor, greaterThan(standard.safeScoreFloor));
    });

    test('every profile produces a valid config', () {
      for (final profile in DriverProfile.values) {
        // Constructor validates ordering invariants; if any profile produced
        // invalid thresholds the constructor would have thrown.
        final c = NavigationSafetyConfig.forProfile(profile);
        expect(c.safeScoreFloor, inInclusiveRange(0, 1));
        expect(c.infoScoreFloor, inInclusiveRange(0, 1));
        expect(c.warningScoreFloor, inInclusiveRange(0, 1));
        expect(c.safeScoreFloor, greaterThanOrEqualTo(c.infoScoreFloor));
        expect(c.infoScoreFloor, greaterThanOrEqualTo(c.warningScoreFloor));
      }
    });
  });

  group('back-compatibility', () {
    test('default constructor unchanged from 0.1.0 baseline', () {
      // Regression guard: pre-0.2.0 callers depending on these specific
      // default values must not break.
      final c = NavigationSafetyConfig();
      expect(c.safeScoreFloor, 0.80);
      expect(c.infoScoreFloor, 0.50);
      expect(c.warningScoreFloor, 0.30);
      expect(c.infoTemperatureCelsius, 3);
      expect(c.warningTemperatureCelsius, 0);
      expect(c.criticalTemperatureCelsius, -5);
      expect(c.infoVisibilityMeters, 1000);
      expect(c.warningVisibilityMeters, 200);
      expect(c.criticalVisibilityMeters, 50);
    });
  });
}
