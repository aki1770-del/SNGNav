import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('VehicleThresholdOverrides — registry construction + lookup', () {
    test('default constructor stores the supplied map', () {
      final reg = VehicleThresholdOverrides({
        'foo': (b) => b,
      });
      expect(reg.overrides.keys, contains('foo'));
    });

    test('null token returns the baseline unchanged', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken(null, baseline);
      expect(result, equals(baseline));
    });

    test('unregistered token returns the baseline unchanged', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken(
        'commercial-light',
        baseline,
      );
      expect(result, equals(baseline));
    });
  });

  group('VehicleThresholdOverrides.withKeiCarDefault — kei-car cohort', () {
    test('kei-car token raises warningVisibilityMeters by +50m', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(
        result.warningVisibilityMeters,
        baseline.warningVisibilityMeters + 50,
      );
    });

    test('kei-car token raises warningTemperatureCelsius by +1°C', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(
        result.warningTemperatureCelsius,
        baseline.warningTemperatureCelsius + 1,
      );
    });

    test('kei-car override preserves score-floor tiers (severity-not-profile)',
        () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.ageingRural,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(result.safeScoreFloor, baseline.safeScoreFloor);
      expect(result.infoScoreFloor, baseline.infoScoreFloor);
      expect(result.warningScoreFloor, baseline.warningScoreFloor);
    });

    test('kei-car override preserves critical thresholds + cap-override', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.foreignTouristSnowZone,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(result.criticalVisibilityMeters, baseline.criticalVisibilityMeters);
      expect(result.criticalTemperatureCelsius, baseline.criticalTemperatureCelsius);
      expect(result.alertsPerMinuteCapOverride,
          baseline.alertsPerMinuteCapOverride);
    });

    test('kei-car override preserves info thresholds (warning-tier only)', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides.withKeiCarDefault();
      final result = reg.applyOverrideForToken('kei-car', baseline);
      expect(result.infoVisibilityMeters, baseline.infoVisibilityMeters);
      expect(result.infoTemperatureCelsius, baseline.infoTemperatureCelsius);
    });
  });

  group('VehicleThresholdOverrides — caution-add-only invariant (negative)', () {
    test('relaxing warningVisibilityMeters trips the debug assertion', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides({
        'relaxing-vis': (b) => NavigationSafetyConfig(
              safeScoreFloor: b.safeScoreFloor,
              infoScoreFloor: b.infoScoreFloor,
              warningScoreFloor: b.warningScoreFloor,
              infoTemperatureCelsius: b.infoTemperatureCelsius,
              warningTemperatureCelsius: b.warningTemperatureCelsius,
              criticalTemperatureCelsius: b.criticalTemperatureCelsius,
              infoVisibilityMeters: b.infoVisibilityMeters,
              warningVisibilityMeters: b.warningVisibilityMeters - 50,
              criticalVisibilityMeters: b.criticalVisibilityMeters,
              alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride,
            ),
      });
      expect(
        () => reg.applyOverrideForToken('relaxing-vis', baseline),
        throwsA(isA<AssertionError>()),
      );
    });

    test('relaxing warningTemperatureCelsius trips the debug assertion', () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides({
        'relaxing-temp': (b) => NavigationSafetyConfig(
              safeScoreFloor: b.safeScoreFloor,
              infoScoreFloor: b.infoScoreFloor,
              warningScoreFloor: b.warningScoreFloor,
              infoTemperatureCelsius: b.infoTemperatureCelsius,
              warningTemperatureCelsius: b.warningTemperatureCelsius - 1,
              criticalTemperatureCelsius: b.criticalTemperatureCelsius,
              infoVisibilityMeters: b.infoVisibilityMeters,
              warningVisibilityMeters: b.warningVisibilityMeters,
              criticalVisibilityMeters: b.criticalVisibilityMeters,
              alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride,
            ),
      });
      expect(
        () => reg.applyOverrideForToken('relaxing-temp', baseline),
        throwsA(isA<AssertionError>()),
      );
    });

    test('modifying safeScoreFloor trips the severity-not-profile assertion',
        () {
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides({
        'severity-modifying': (b) => NavigationSafetyConfig(
              safeScoreFloor: 0.95, // changed
              infoScoreFloor: b.infoScoreFloor,
              warningScoreFloor: b.warningScoreFloor,
              infoTemperatureCelsius: b.infoTemperatureCelsius,
              warningTemperatureCelsius: b.warningTemperatureCelsius,
              criticalTemperatureCelsius: b.criticalTemperatureCelsius,
              infoVisibilityMeters: b.infoVisibilityMeters,
              warningVisibilityMeters: b.warningVisibilityMeters,
              criticalVisibilityMeters: b.criticalVisibilityMeters,
              alertsPerMinuteCapOverride: b.alertsPerMinuteCapOverride,
            ),
      });
      expect(
        () => reg.applyOverrideForToken('severity-modifying', baseline),
        throwsA(isA<AssertionError>()),
      );
    });

    test('caution-equal (no change) override is permitted', () {
      // The invariant is caution-add-only, so equal values must pass
      // (override may legitimately be a no-op).
      final baseline = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final reg = VehicleThresholdOverrides({
        'identity': (b) => b,
      });
      final result = reg.applyOverrideForToken('identity', baseline);
      expect(result, equals(baseline));
    });
  });
}
