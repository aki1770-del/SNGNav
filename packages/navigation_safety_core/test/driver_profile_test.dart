import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('DriverProfile enum value set', () {
    test('contains the v1 six profiles', () {
      // 0.3.0: foreignTouristSnowZone added. The previous 5-profile taxonomy
      // mis-mapped foreign-tourist-in-snow-zone to either snowZoneExperienced
      // (catastrophically wrong — they have neither experience nor local
      // equipment) or noviceUrban (location-wrong). See KNOWN_LIMITATIONS.md.
      expect(
        DriverProfile.values,
        equals(<DriverProfile>[
          DriverProfile.ageingRural,
          DriverProfile.snowZoneExperienced,
          DriverProfile.noviceUrban,
          DriverProfile.professional,
          DriverProfile.agriculturalForestry,
          DriverProfile.foreignTouristSnowZone,
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

    test('ageingRural threshold magnitudes match 0.3.0 calibration', () {
      // 0.3.0 corrections per literature:
      // - infoTemperatureCelsius: 5°C → 4°C (alert-fatigue per arxiv 2410.06388
      //   + AAA-FTS report; 5°C combined with 1500m visibility fired on most
      //   autumn evenings, desensitizing drivers before actual black-ice events)
      // - warningTemperatureCelsius: 1°C → 2°C (margin above black-ice
      //   formation envelope at road-surface ≤0°C; 1°C left no margin)
      // See KNOWN_LIMITATIONS.md "Threshold magnitudes".
      final ageing = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
      expect(ageing.infoTemperatureCelsius, 4);
      expect(ageing.warningTemperatureCelsius, 2);
    });

    test('noviceUrban threshold magnitudes match 0.3.0 calibration', () {
      // 0.3.0 correction per literature:
      // - warningVisibilityMeters: 250m → 320m. Novice hazard-perception RT
      //   is 3.58s vs 1.32s experienced (PubMed 16313881); at 60 km/h that's
      //   ~37m additional reaction-distance from RT alone, so 250m (+50m
      //   over standard) left no braking margin. 320m gives RT-margin +
      //   braking margin per Konstantopoulos PubMed 22664714.
      // See KNOWN_LIMITATIONS.md "Threshold magnitudes".
      final novice = NavigationSafetyConfig.forProfile(DriverProfile.noviceUrban);
      expect(novice.warningVisibilityMeters, 320);
    });

    test('foreignTouristSnowZone is most-conservative on every dimension', () {
      // 0.3.0: closes the V100 gap where foreign-tourist-in-snow-zone was
      // previously mis-mapped. Combines novice-equivalent unfamiliarity with
      // the local conditions + likely non-winterised rental vehicle +
      // language-localization gaps in road signage. The loom shifts caution
      // further than any other profile.
      final tourist = NavigationSafetyConfig.forProfile(DriverProfile.foreignTouristSnowZone);

      for (final other in DriverProfile.values.where((p) => p != DriverProfile.foreignTouristSnowZone)) {
        final c = NavigationSafetyConfig.forProfile(other);

        // Score floors: highest (hardest to be classified "safe").
        expect(tourist.safeScoreFloor, greaterThanOrEqualTo(c.safeScoreFloor),
            reason: 'foreignTouristSnowZone safeScoreFloor must be >= $other');
        expect(tourist.infoScoreFloor, greaterThanOrEqualTo(c.infoScoreFloor),
            reason: 'foreignTouristSnowZone infoScoreFloor must be >= $other');
        expect(tourist.warningScoreFloor, greaterThanOrEqualTo(c.warningScoreFloor),
            reason: 'foreignTouristSnowZone warningScoreFloor must be >= $other');

        // Temperature thresholds: warns at warmer temps (earliest in cooling).
        expect(tourist.infoTemperatureCelsius, greaterThanOrEqualTo(c.infoTemperatureCelsius),
            reason: 'foreignTouristSnowZone infoTemperatureCelsius must be >= $other');
        expect(tourist.warningTemperatureCelsius, greaterThanOrEqualTo(c.warningTemperatureCelsius),
            reason: 'foreignTouristSnowZone warningTemperatureCelsius must be >= $other');
        expect(tourist.criticalTemperatureCelsius, greaterThanOrEqualTo(c.criticalTemperatureCelsius),
            reason: 'foreignTouristSnowZone criticalTemperatureCelsius must be >= $other');

        // Visibility thresholds: warns at better visibility (earliest in degradation).
        expect(tourist.infoVisibilityMeters, greaterThanOrEqualTo(c.infoVisibilityMeters),
            reason: 'foreignTouristSnowZone infoVisibilityMeters must be >= $other');
        expect(tourist.warningVisibilityMeters, greaterThanOrEqualTo(c.warningVisibilityMeters),
            reason: 'foreignTouristSnowZone warningVisibilityMeters must be >= $other');
        expect(tourist.criticalVisibilityMeters, greaterThanOrEqualTo(c.criticalVisibilityMeters),
            reason: 'foreignTouristSnowZone criticalVisibilityMeters must be >= $other');
      }
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
