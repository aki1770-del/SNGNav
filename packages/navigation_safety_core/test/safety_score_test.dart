/// SafetyScore unit tests.
library;

import 'package:test/test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

void main() {
  group('SafetyScore', () {
    test('preserves in-range values', () {
      final score = SafetyScore(
        overall: 0.7,
        gripScore: 0.6,
        visibilityScore: 0.8,
        fleetConfidenceScore: 0.9,
      );

      expect(score.overall, 0.7);
      expect(score.gripScore, 0.6);
      expect(score.visibilityScore, 0.8);
      expect(score.fleetConfidenceScore, 0.9);
    });

    test('clamps negative values to zero', () {
      final score = SafetyScore(
        overall: -1,
        gripScore: -0.2,
        visibilityScore: -4,
        fleetConfidenceScore: -0.01,
      );

      expect(score.overall, 0);
      expect(score.gripScore, 0);
      expect(score.visibilityScore, 0);
      expect(score.fleetConfidenceScore, 0);
    });

    test('clamps values above one to one', () {
      final score = SafetyScore(
        overall: 5,
        gripScore: 1.2,
        visibilityScore: 2,
        fleetConfidenceScore: 10,
      );

      expect(score.overall, 1);
      expect(score.gripScore, 1);
      expect(score.visibilityScore, 1);
      expect(score.fleetConfidenceScore, 1);
    });

    test('equatable compares all fields', () {
      final a = SafetyScore(
        overall: 0.4,
        gripScore: 0.5,
        visibilityScore: 0.3,
        fleetConfidenceScore: 0.7,
      );
      final b = SafetyScore(
        overall: 0.4,
        gripScore: 0.5,
        visibilityScore: 0.3,
        fleetConfidenceScore: 0.7,
      );

      expect(a, equals(b));
    });

    test('returns null severity for safe score', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.95,
        gripScore: 0.95,
        visibilityScore: 0.95,
        fleetConfidenceScore: 0.95,
      );

      expect(score.toAlertSeverity(config), isNull);
    });

    test('returns info severity for caution score', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.6,
        gripScore: 0.6,
        visibilityScore: 0.6,
        fleetConfidenceScore: 0.6,
      );

      expect(score.toAlertSeverity(config), AlertSeverity.info);
    });

    test('returns warning severity for hazardous score', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.4,
        gripScore: 0.4,
        visibilityScore: 0.4,
        fleetConfidenceScore: 0.4,
      );

      expect(score.toAlertSeverity(config), AlertSeverity.warning);
    });

    test('returns critical severity below warning floor', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.2,
        gripScore: 0.2,
        visibilityScore: 0.2,
        fleetConfidenceScore: 0.2,
      );

      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('returns null severity at safe threshold boundary', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: config.safeScoreFloor,
        gripScore: 0.7,
        visibilityScore: 0.8,
        fleetConfidenceScore: 0.9,
      );

      expect(score.toAlertSeverity(config), isNull);
    });

    test('returns info severity at info threshold boundary', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: config.infoScoreFloor,
        gripScore: 0.6,
        visibilityScore: 0.6,
        fleetConfidenceScore: 0.6,
      );

      expect(score.toAlertSeverity(config), AlertSeverity.info);
    });

    test('returns warning severity at warning threshold boundary', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: config.warningScoreFloor,
        gripScore: 0.3,
        visibilityScore: 0.3,
        fleetConfidenceScore: 0.3,
      );

      expect(score.toAlertSeverity(config), AlertSeverity.warning);
    });

    test('overall = 0.0 → critical', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.0,
        gripScore: 0.0,
        visibilityScore: 0.0,
        fleetConfidenceScore: 0.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('overall = 1.0 → no alert', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 1.0,
        gripScore: 1.0,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), isNull);
    });
  });

  // GAP-1 (conservative-on-uncertain invariant): a non-finite (NaN / Infinity) score must be
  // treated as the worst-case/uncertain value and ALERT conservatively,
  // never silently pass. NaN compares false to both clamp bounds (so it
  // would slip through unclamped), and in toAlertSeverity every `<`
  // against NaN is false → null (no alert). +Infinity clamps to 1 → no
  // alert. Both invert the "if uncertain, alert conservatively" intent
  // The invariant the guard enforces: non-finite → 0 → critical.
  group('non-finite inputs alert conservatively (GAP-1)', () {
    test('NaN components clamp to 0 (worst-case), never remain NaN', () {
      final score = SafetyScore(
        overall: double.nan,
        gripScore: double.nan,
        visibilityScore: double.nan,
        fleetConfidenceScore: double.nan,
      );

      expect(score.overall, 0);
      expect(score.gripScore, 0);
      expect(score.visibilityScore, 0);
      expect(score.fleetConfidenceScore, 0);
      expect(score.overall.isNaN, isFalse);
    });

    test('NaN overall → critical (alerts, never silently passes)', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: double.nan,
        gripScore: 0.5,
        visibilityScore: 0.5,
        fleetConfidenceScore: 0.5,
      );

      // Pre-fix: NaN slips through clamp and toAlertSeverity returns null
      // (no alert). Post-fix: NaN → 0 → critical.
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('+Infinity overall → critical (not clamped to 1 / no-alert)', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: double.infinity,
        gripScore: 0.5,
        visibilityScore: 0.5,
        fleetConfidenceScore: 0.5,
      );

      // Pre-fix: +Infinity clamps to 1 → null (no alert).
      // Post-fix: +Infinity → 0 → critical.
      expect(score.overall, 0);
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('-Infinity overall → critical (worst-case)', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: double.negativeInfinity,
        gripScore: 0.5,
        visibilityScore: 0.5,
        fleetConfidenceScore: 0.5,
      );

      expect(score.overall, 0);
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });
  });
}
