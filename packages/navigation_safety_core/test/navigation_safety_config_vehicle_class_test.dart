import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('forProfileWithContext + vehicleOverrides', () {
    test('null vehicleOverrides => baseline-plus-context unchanged', () {
      final base = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: const DrivingContext(speedMps: 22.2),
      );
      final viaOverrideArg = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: const DrivingContext(speedMps: 22.2),
      );
      // Same call, same result; sanity check.
      expect(viaOverrideArg, equals(base));
    });

    test(
      'vehicleOverrides supplied but token null => baseline-plus-context unchanged',
      () {
        final baselineCtx = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(speedMps: 22.2),
        );
        final withOverrides = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(speedMps: 22.2),
          vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        );
        expect(withOverrides, equals(baselineCtx));
      },
    );

    test(
      'vehicleOverrides supplied + unknown token => baseline-plus-context unchanged',
      () {
        final baselineCtx = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(
            speedMps: 22.2,
            vehicleClassToken: 'unknown-class',
          ),
        );
        final withOverrides = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(
            speedMps: 22.2,
            vehicleClassToken: 'unknown-class',
          ),
          vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        );
        expect(withOverrides, equals(baselineCtx));
      },
    );

    test(
      'kei-car token raises warning thresholds vs baseline-plus-context',
      () {
        final baselineCtx = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
          context: const DrivingContext(speedMps: 18.0),
        );
        final withKeiCar = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.ageingRural,
          context: const DrivingContext(
            speedMps: 18.0,
            vehicleClassToken: 'kei-car',
          ),
          vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        );
        // Visibility lifted by +50m; temperature lifted by +1°C.
        expect(
          withKeiCar.warningVisibilityMeters,
          baselineCtx.warningVisibilityMeters + 50,
        );
        expect(
          withKeiCar.warningTemperatureCelsius,
          baselineCtx.warningTemperatureCelsius + 1,
        );
      },
    );

    test(
      'kei-car composes with humidity + ambient (override applied last)',
      () {
        // First compute the baseline-plus-context (no vehicle override) so
        // the test asserts on the post-context state, not just the
        // per-profile baseline.
        final baselineCtx = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(
            humidityRH: 0.4,
            ambientTempCelsius: 1.0,
          ),
        );
        final withKeiCar = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(
            humidityRH: 0.4,
            ambientTempCelsius: 1.0,
            vehicleClassToken: 'kei-car',
          ),
          vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        );
        // Vehicle override applies AFTER humidity-driven temperature lift.
        expect(
          withKeiCar.warningTemperatureCelsius,
          baselineCtx.warningTemperatureCelsius + 1,
        );
      },
    );

    test('kei-car preserves score-floor tiers (severity-not-profile)', () {
      final baselineCtx = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.foreignTouristSnowZone,
        context: const DrivingContext(
          speedMps: 25.0,
          vehicleClassToken: 'kei-car',
        ),
        vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
      );
      final raw = NavigationSafetyConfig.forProfile(
        DriverProfile.foreignTouristSnowZone,
      );
      expect(baselineCtx.safeScoreFloor, raw.safeScoreFloor);
      expect(baselineCtx.infoScoreFloor, raw.infoScoreFloor);
      expect(baselineCtx.warningScoreFloor, raw.warningScoreFloor);
    });

    test(
      'kei-car preserves critical thresholds (severity-not-profile critical-tier)',
      () {
        final baselineCtx = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          context: const DrivingContext(
            speedMps: 30.0,
            vehicleClassToken: 'kei-car',
          ),
          vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        );
        final raw = NavigationSafetyConfig.forProfile(
          DriverProfile.snowZoneExperienced,
        );
        expect(
          baselineCtx.criticalVisibilityMeters,
          raw.criticalVisibilityMeters,
        );
        expect(
          baselineCtx.criticalTemperatureCelsius,
          raw.criticalTemperatureCelsius,
        );
      },
    );

    test(
      'context==null + vehicleOverrides supplied => returns per-profile baseline',
      () {
        // Documented edge: with no context there is no token, so the
        // override is a no-op even when a registry is supplied.
        final result = NavigationSafetyConfig.forProfileWithContext(
          DriverProfile.snowZoneExperienced,
          vehicleOverrides: VehicleThresholdOverrides.withKeiCarDefault(),
        );
        final baseline = NavigationSafetyConfig.forProfile(
          DriverProfile.snowZoneExperienced,
        );
        expect(result, equals(baseline));
      },
    );

    test(
      'all six profiles compose with kei-car override (smoke + invariants)',
      () {
        final reg = VehicleThresholdOverrides.withKeiCarDefault();
        for (final p in DriverProfile.values) {
          final base = NavigationSafetyConfig.forProfile(p);
          final withKeiCar = NavigationSafetyConfig.forProfileWithContext(
            p,
            context: const DrivingContext(vehicleClassToken: 'kei-car'),
            vehicleOverrides: reg,
          );
          expect(
            withKeiCar.warningVisibilityMeters,
            greaterThanOrEqualTo(base.warningVisibilityMeters),
            reason: 'profile $p: warning visibility relaxed',
          );
          expect(
            withKeiCar.warningTemperatureCelsius,
            greaterThanOrEqualTo(base.warningTemperatureCelsius),
            reason: 'profile $p: warning temperature relaxed',
          );
          expect(
            withKeiCar.safeScoreFloor,
            base.safeScoreFloor,
            reason: 'profile $p: safeScoreFloor modified',
          );
        }
      },
    );
  });
}
