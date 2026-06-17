/// NavigationSafetyConfig unit tests.
library;

import 'package:test/test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

void main() {
  group('NavigationSafetyConfig', () {
    test('defaults match planning thresholds', () {
      final config = NavigationSafetyConfig();

      expect(config.safeScoreFloor, 0.80);
      expect(config.infoScoreFloor, 0.50);
      expect(config.warningScoreFloor, 0.30);
      expect(config.infoTemperatureCelsius, 3);
      expect(config.warningTemperatureCelsius, 0);
      expect(config.criticalTemperatureCelsius, -5);
      expect(config.infoVisibilityMeters, 1000);
      expect(config.warningVisibilityMeters, 200);
      expect(config.criticalVisibilityMeters, 50);
    });

    test('supports custom thresholds', () {
      final config = NavigationSafetyConfig(
        safeScoreFloor: 0.9,
        infoScoreFloor: 0.6,
        warningScoreFloor: 0.4,
        infoTemperatureCelsius: 2,
        warningTemperatureCelsius: -1,
        criticalTemperatureCelsius: -7,
        infoVisibilityMeters: 900,
        warningVisibilityMeters: 150,
        criticalVisibilityMeters: 30,
      );

      expect(config.safeScoreFloor, 0.9);
      expect(config.infoScoreFloor, 0.6);
      expect(config.warningScoreFloor, 0.4);
      expect(config.infoTemperatureCelsius, 2);
      expect(config.warningTemperatureCelsius, -1);
      expect(config.criticalTemperatureCelsius, -7);
      expect(config.infoVisibilityMeters, 900);
      expect(config.warningVisibilityMeters, 150);
      expect(config.criticalVisibilityMeters, 30);
    });

    test('throws RangeError when safe floor exceeds one', () {
      expect(
        () => NavigationSafetyConfig(safeScoreFloor: 1.1),
        throwsA(isA<RangeError>()),
      );
    });

    test('throws when safeScoreFloor is negative', () {
      expect(
        () => NavigationSafetyConfig(safeScoreFloor: -0.1),
        throwsRangeError,
      );
    });

    test('throws ArgumentError when info floor is below warning floor', () {
      expect(
        () =>
            NavigationSafetyConfig(infoScoreFloor: 0.2, warningScoreFloor: 0.3),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when safe floor is below info floor', () {
      expect(
        () => NavigationSafetyConfig(safeScoreFloor: 0.4, infoScoreFloor: 0.5),
        throwsA(isA<ArgumentError>()),
      );
    });

    // GAP-2 (sibling to SafetyScore GAP-1): a non-finite score floor is
    // NaN-permissive against the `< 0 || > 1` range checks and would pass
    // construction silently, then poison `toAlertSeverity` (overall < NaN
    // is always false → no alert even at overall == 0). Construction must
    // reject it loudly.
    test('throws ArgumentError when warningScoreFloor is NaN', () {
      expect(
        () => NavigationSafetyConfig(warningScoreFloor: double.nan),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when safeScoreFloor is infinite', () {
      expect(
        () => NavigationSafetyConfig(safeScoreFloor: double.infinity),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('throws ArgumentError when infoScoreFloor is negative infinity', () {
      expect(
        () => NavigationSafetyConfig(infoScoreFloor: double.negativeInfinity),
        throwsA(isA<ArgumentError>()),
      );
    });

    test(
      'the NaN-floor no-alert path is unreachable: construction rejects the '
      'NaN floor, so a worst-case score still ALERTS critical',
      () {
        // Defensive end-to-end: prove the conservative-alert guarantee
        // cannot be silently defeated via a non-finite floor.
        expect(
          () => NavigationSafetyConfig(warningScoreFloor: double.nan),
          throwsA(isA<ArgumentError>()),
        );
        final config = NavigationSafetyConfig();
        final worstCase = SafetyScore(
          overall: 0,
          gripScore: 0,
          visibilityScore: 0,
          fleetConfidenceScore: 0,
        );
        expect(worstCase.toAlertSeverity(config), AlertSeverity.critical);
      },
    );

    test('equality holds for identical configs', () {
      final a = NavigationSafetyConfig();
      final b = NavigationSafetyConfig();
      expect(a, equals(b));
    });

    test('inequality holds when a field differs', () {
      final a = NavigationSafetyConfig();
      final b = NavigationSafetyConfig(safeScoreFloor: 0.9);
      expect(a, isNot(equals(b)));
    });
  });
}
