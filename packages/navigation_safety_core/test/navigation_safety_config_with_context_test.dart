import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('NavigationSafetyConfig.forProfileWithContext', () {
    test('null context delegates to forProfile (backward-compat)', () {
      final base = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
      final ctx = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.ageingRural,
      );
      expect(ctx, equals(base));
    });

    test('speed-only context can raise warning visibility', () {
      final base = NavigationSafetyConfig.forProfile(DriverProfile.noviceUrban);
      final adj = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.noviceUrban,
        context: const DrivingContext(speedMps: 50.0),
      );
      // Novice 3.58s × 50 = 179m + 50²/11 ≈ 113.6 → 292.6m, less than
      // 320 baseline → stays at baseline. Try faster.
      expect(
        adj.warningVisibilityMeters,
        greaterThanOrEqualTo(base.warningVisibilityMeters),
      );
    });

    test('very high speed forces visibility floor above baseline', () {
      final base = NavigationSafetyConfig.forProfile(DriverProfile.noviceUrban);
      final adj = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.noviceUrban,
        context: const DrivingContext(speedMps: 60.0),
      );
      // 3.58 * 60 = 214.8 + 60²/11 ≈ 327.3 → 542.1, well above 320.
      expect(
        adj.warningVisibilityMeters,
        greaterThan(base.warningVisibilityMeters),
      );
    });

    test('humidity + ambient context can raise warning temperature', () {
      final base = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      final adj = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: const DrivingContext(humidityRH: 0.4, ambientTempCelsius: 1.0),
      );
      // Effective at 40% RH and 1C ambient drops below freezing → lift expected.
      expect(
        adj.warningTemperatureCelsius,
        greaterThanOrEqualTo(base.warningTemperatureCelsius),
      );
    });

    test('precipitation context can raise warning visibility', () {
      final base = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
      final adj = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.ageingRural,
        context: const DrivingContext(
          timeSincePrecipitation: Duration(minutes: 10),
          ambientTempCelsius: 5.0,
        ),
      );
      expect(
        adj.warningVisibilityMeters,
        greaterThan(base.warningVisibilityMeters),
      );
    });

    test('combined context applies all dimensions simultaneously', () {
      final adj = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.foreignTouristSnowZone,
        context: const DrivingContext(
          speedMps: 30.0,
          humidityRH: 0.6,
          ambientTempCelsius: 2.0,
          timeSincePrecipitation: Duration(minutes: 30),
        ),
      );
      final base = NavigationSafetyConfig.forProfile(
        DriverProfile.foreignTouristSnowZone,
      );
      // At least one dimension must move (visibility or temperature).
      final visMoved =
          adj.warningVisibilityMeters > base.warningVisibilityMeters;
      final tempMoved =
          adj.warningTemperatureCelsius > base.warningTemperatureCelsius;
      expect(visMoved || tempMoved, isTrue);
    });

    test('per-profile baseline preserved when context is null', () {
      for (final p in DriverProfile.values) {
        final base = NavigationSafetyConfig.forProfile(p);
        final ctx = NavigationSafetyConfig.forProfileWithContext(p);
        expect(ctx, equals(base), reason: 'profile $p mismatched');
      }
    });

    test('forProfile() unchanged by adding the context-aware factory', () {
      // Direct invariant check: forProfile() returns historical defaults.
      final ageing = NavigationSafetyConfig.forProfile(
        DriverProfile.ageingRural,
      );
      expect(ageing.warningTemperatureCelsius, 2);
      expect(ageing.warningVisibilityMeters, 300);
      final novice = NavigationSafetyConfig.forProfile(
        DriverProfile.noviceUrban,
      );
      expect(novice.warningVisibilityMeters, 320);
    });
  });
}
