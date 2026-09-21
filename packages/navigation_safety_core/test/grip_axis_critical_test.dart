/// Black ice under a clear sky: one axis is catastrophic, the other is fine.
///
/// The composite `overall` is a MEAN (`0.5 * grip + 0.5 * visibility` in
/// `driving_conditions`). A mean cannot express "one axis alone is lethal":
/// with visibility at 1.0, `overall >= 0.5`, while every shipped
/// `warningScoreFloor` is 0.30-0.40. So a grip score of ZERO under clear air
/// scored `info` on the default config and could NOT reach `critical` at any
/// grip value. Google Maps working, GPS working, sky clear, road lethal — the
/// exact condition this product exists for, and the severity model had no
/// shape in which to say it.
///
/// These tests fail on the composite-only rule and pass on the per-axis rule.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// 1.5 / 5.5 m/s^2 — glare-ice braking deceleration over dry-pavement, both
/// values published in `navigation_safety_calibration`'s
/// `speed_dependent_visibility.dart`. Written as a literal here so this test
/// compiles against the PRE-fix API and fails on BEHAVIOUR, not on a missing
/// symbol.
const double _glareIceFloor = 1.5 / 5.5;

void main() {
  group('a single catastrophic axis reaches critical', () {
    test('zero grip + perfect visibility is critical, not info', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.5, // 0.5 * 0.0 + 0.5 * 1.0 — the mean says "half good"
        gripScore: 0.0, // she has no grip at all
        visibilityScore: 1.0, // and she can see every metre of it
        fleetConfidenceScore: 1.0,
      );

      // Pre-fix: overall 0.5 is not < 0.50 and not < 0.30, but is < 0.80,
      // so this returned AlertSeverity.info.
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('critical is reachable at perfect visibility on every profile', () {
      for (final profile in DriverProfile.values) {
        final config = NavigationSafetyConfig.forProfile(profile);
        final score = SafetyScore(
          overall: 0.5,
          gripScore: 0.0,
          visibilityScore: 1.0,
          fleetConfidenceScore: 1.0,
        );
        expect(
          score.toAlertSeverity(config),
          AlertSeverity.critical,
          reason:
              'profile $profile: with visibility 1.0 the mean can never fall '
              'below warningScoreFloor ${config.warningScoreFloor}, so critical '
              'was unreachable however bad the grip was',
        );
      }
    });

    test('grip at the glare-ice floor is critical under clear air', () {
      final config = NavigationSafetyConfig();
      // 1.5 / 5.5 m/s^2 — the package's own glare-ice-over-dry braking ratio.
      final score = SafetyScore(
        overall: 0.5 * _glareIceFloor + 0.5,
        gripScore: _glareIceFloor - 0.001,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });
  });

  group('the floor is pinned to its published derivation', () {
    test('the shipped floor is the glare-ice braking ratio', () {
      // A silent retune of this number is a change to when she is told the
      // road is lethal. It must be a decision, not a drift.
      expect(NavigationSafetyConfig().criticalGripScoreFloor, _glareIceFloor);
      expect(_glareIceFloor, closeTo(0.2727, 0.0001));
    });

    test('compacted snow sits well clear of the floor', () {
      // 3.0 / 5.5 — a winter road is not glare ice, and must not be told it is.
      expect(3.0 / 5.5, greaterThan(_glareIceFloor));
      expect(
        SafetyScore(
          overall: 0.5 * (3.0 / 5.5) + 0.5,
          gripScore: 3.0 / 5.5,
          visibilityScore: 1.0,
          fleetConfidenceScore: 1.0,
        ).toAlertSeverity(NavigationSafetyConfig()),
        AlertSeverity.info,
      );
    });

    test('a vehicle override cannot weaken the floor', () {
      // Severity-class, exactly like the score floors: a per-vehicle
      // transform that lowered it would re-open this gap one car at a time.
      final base = NavigationSafetyConfig();
      expect(
        () => NavigationSafetyConfig(criticalGripScoreFloor: double.nan),
        throwsArgumentError,
      );
      expect(
        () => NavigationSafetyConfig(criticalGripScoreFloor: 1.5),
        throwsRangeError,
      );
      expect(base.criticalGripScoreFloor, _glareIceFloor);
    });
  });

  group('the reverse control: ordinary conditions are not promoted', () {
    test('a good road stays silent', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.90,
        gripScore: 0.90,
        visibilityScore: 0.90,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), isNull);
    });

    test('a wet autumn road is not shouted at', () {
      final config = NavigationSafetyConfig();
      // Grip well above the glare-ice floor; visibility mediocre.
      final score = SafetyScore(
        overall: 0.5 * 0.60 + 0.5 * 0.60,
        gripScore: 0.60,
        visibilityScore: 0.60,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.info);
    });

    test('grip just above the floor does not fire critical on its own', () {
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.5 * (_glareIceFloor + 0.01) + 0.5,
        gripScore: _glareIceFloor + 0.01,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.info);
    });

    test(
      'the per-axis rule NEVER lowers severity, over the whole score plane',
      () {
        // The safety property: adding the axis rule can only raise severity.
        // No alert that fires today can be silenced by this change.
        const rank = {
          null: 0,
          AlertSeverity.info: 1,
          AlertSeverity.warning: 2,
          AlertSeverity.critical: 3,
        };
        final config = NavigationSafetyConfig();
        var promoted = 0;
        var allClearDisturbed = 0;
        const n = 101;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final grip = i / (n - 1);
            final visibility = j / (n - 1);
            final overall = 0.5 * grip + 0.5 * visibility;

            // Composite-only band — the pre-fix rule, recomputed here so the
            // comparison is against behaviour, not against a remembered table.
            final AlertSeverity? before;
            if (overall < config.warningScoreFloor) {
              before = AlertSeverity.critical;
            } else if (overall < config.infoScoreFloor) {
              before = AlertSeverity.warning;
            } else if (overall < config.safeScoreFloor) {
              before = AlertSeverity.info;
            } else {
              before = null;
            }

            final after = SafetyScore(
              overall: overall,
              gripScore: grip,
              visibilityScore: visibility,
              fleetConfidenceScore: 1.0,
            ).toAlertSeverity(config);

            expect(
              rank[after]! >= rank[before]!,
              isTrue,
              reason:
                  'grip=$grip visibility=$visibility: severity FELL from '
                  '$before to $after — the axis rule must be monotone',
            );
            if (rank[after]! > rank[before]!) promoted++;
            if (before == null && after != null) allClearDisturbed++;
          }
        }
        // It does change something — a rule that promotes nothing is ornament.
        expect(promoted, greaterThan(0));
        // And it never turns an all-clear into an alert: every promotion is
        // from a band that was ALREADY alerting.
        expect(
          allClearDisturbed,
          0,
          reason:
              'the axis rule must not create an alert where there is '
              'silence today — it sharpens alerts, it does not add them',
        );
      },
    );
  });
}
