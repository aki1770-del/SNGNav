import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('DriverState enum exhaustivity', () {
    test('has the four documented values', () {
      expect(DriverState.values, hasLength(4));
      expect(DriverState.values, containsAll([
        DriverState.alert,
        DriverState.fatigued,
        DriverState.distracted,
        DriverState.impairedVisibility,
      ]));
    });
  });

  group('DriverContext value-object', () {
    test('default constructor + accessors', () {
      const ctx = DriverContext(
        profile: DriverProfile.snowZoneExperienced,
        state: DriverState.alert,
      );
      expect(ctx.profile, DriverProfile.snowZoneExperienced);
      expect(ctx.state, DriverState.alert);
    });

    test('combineWith factory equals default constructor', () {
      const a = DriverContext(
        profile: DriverProfile.ageingRural,
        state: DriverState.fatigued,
      );
      final b = DriverContext.combineWith(
        profile: DriverProfile.ageingRural,
        state: DriverState.fatigued,
      );
      expect(a, b);
    });

    test('value-object equality + hash', () {
      const a = DriverContext(
        profile: DriverProfile.noviceUrban,
        state: DriverState.distracted,
      );
      const b = DriverContext(
        profile: DriverProfile.noviceUrban,
        state: DriverState.distracted,
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('inequality on different profile', () {
      const a = DriverContext(
        profile: DriverProfile.noviceUrban,
        state: DriverState.alert,
      );
      const b = DriverContext(
        profile: DriverProfile.ageingRural,
        state: DriverState.alert,
      );
      expect(a, isNot(b));
    });

    test('inequality on different state', () {
      const a = DriverContext(
        profile: DriverProfile.noviceUrban,
        state: DriverState.alert,
      );
      const b = DriverContext(
        profile: DriverProfile.noviceUrban,
        state: DriverState.fatigued,
      );
      expect(a, isNot(b));
    });

    test('withState preserves profile, swaps state', () {
      const a = DriverContext(
        profile: DriverProfile.foreignTouristSnowZone,
        state: DriverState.alert,
      );
      final b = a.withState(DriverState.impairedVisibility);
      expect(b.profile, a.profile);
      expect(b.state, DriverState.impairedVisibility);
    });
  });

  group('forDriverContext — alert state == forProfile (back-compat invariant)',
      () {
    for (final profile in DriverProfile.values) {
      test('${profile.name}: alert state matches forProfile baseline', () {
        final base = NavigationSafetyConfig.forProfile(profile);
        final ctx = NavigationSafetyConfig.forDriverContext(
          DriverContext(profile: profile, state: DriverState.alert),
        );
        expect(ctx.warningTemperatureCelsius, base.warningTemperatureCelsius);
        expect(ctx.warningVisibilityMeters, base.warningVisibilityMeters);
        expect(ctx.infoVisibilityMeters, base.infoVisibilityMeters);
        expect(ctx.criticalVisibilityMeters, base.criticalVisibilityMeters);
      });
    }
  });

  group('forDriverContext — conservative-only contract', () {
    for (final profile in DriverProfile.values) {
      for (final state in DriverState.values) {
        test('${profile.name} × ${state.name}: warningTemp >= baseline', () {
          final base = NavigationSafetyConfig.forProfile(profile);
          final tuned = NavigationSafetyConfig.forDriverContext(
            DriverContext(profile: profile, state: state),
          );
          expect(
            tuned.warningTemperatureCelsius,
            greaterThanOrEqualTo(base.warningTemperatureCelsius),
          );
        });
        test('${profile.name} × ${state.name}: warningVisibility >= baseline',
            () {
          final base = NavigationSafetyConfig.forProfile(profile);
          final tuned = NavigationSafetyConfig.forDriverContext(
            DriverContext(profile: profile, state: state),
          );
          expect(
            tuned.warningVisibilityMeters,
            greaterThanOrEqualTo(base.warningVisibilityMeters),
          );
        });
      }
    }
  });

  group('forDriverContext — state-specific deltas', () {
    test('fatigued lifts warningTemperature by +1°C', () {
      final base = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final tuned = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.snowZoneExperienced,
          state: DriverState.fatigued,
        ),
      );
      expect(
        tuned.warningTemperatureCelsius,
        base.warningTemperatureCelsius + 1,
      );
    });

    test('impairedVisibility scales visibility tiers up (>= ×1.25)', () {
      final base = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final tuned = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.snowZoneExperienced,
          state: DriverState.impairedVisibility,
        ),
      );
      expect(
        tuned.warningVisibilityMeters,
        greaterThanOrEqualTo((base.warningVisibilityMeters * 1.25).ceil()),
      );
      expect(
        tuned.infoVisibilityMeters,
        greaterThanOrEqualTo((base.infoVisibilityMeters * 1.25).ceil()),
      );
    });

    test('distracted with speed in DrivingContext expands warning visibility',
        () {
      final base = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: const DrivingContext(speedMps: 25.0),
      );
      final tuned = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.snowZoneExperienced,
          state: DriverState.distracted,
        ),
        environmentalContext: const DrivingContext(speedMps: 25.0),
      );
      expect(
        tuned.warningVisibilityMeters,
        greaterThan(base.warningVisibilityMeters),
      );
    });

    test('distracted without speed leaves visibility unchanged', () {
      final base = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final tuned = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.snowZoneExperienced,
          state: DriverState.distracted,
        ),
      );
      expect(
        tuned.warningVisibilityMeters,
        base.warningVisibilityMeters,
      );
    });
  });

  group('forDriverContext — composes with environmental DrivingContext', () {
    test('environmental context still applies under alert state', () {
      final envOnly = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.ageingRural,
        context: const DrivingContext(speedMps: 20.0),
      );
      final composed = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.ageingRural,
          state: DriverState.alert,
        ),
        environmentalContext: const DrivingContext(speedMps: 20.0),
      );
      expect(
        composed.warningVisibilityMeters,
        envOnly.warningVisibilityMeters,
      );
    });

    test('null environmentalContext == bare forDriverContext', () {
      final a = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.noviceUrban,
          state: DriverState.fatigued,
        ),
      );
      final b = NavigationSafetyConfig.forDriverContext(
        const DriverContext(
          profile: DriverProfile.noviceUrban,
          state: DriverState.fatigued,
        ),
        environmentalContext: null,
      );
      expect(a, b);
    });
  });

  group('Back-compat — 0.5.0 surface unchanged', () {
    test('forProfile defaults match 0.5.0 (snowZoneExperienced)', () {
      final cfg = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      expect(cfg.warningTemperatureCelsius, 0);
      expect(cfg.warningVisibilityMeters, 200);
    });

    test('forProfileWithContext speedMps still drives 0.5.0 calibration', () {
      final cfg = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: const DrivingContext(speedMps: 30.0),
      );
      expect(
        cfg.warningVisibilityMeters,
        greaterThanOrEqualTo(200),
      );
    });
  });
}
