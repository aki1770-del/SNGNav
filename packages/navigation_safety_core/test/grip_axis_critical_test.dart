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

    test('grip just below the glare-ice floor is critical under clear air', () {
      final config = NavigationSafetyConfig();
      // 1.5 / 5.5 m/s^2 — the package's own glare-ice-over-dry braking ratio.
      // The comparison is STRICT, so the value tested is just below the
      // floor, not at it. The name said "at" while the body tested below;
      // a test whose name and body disagree is a test nobody can read.
      final score = SafetyScore(
        overall: 0.5 * _glareIceFloor + 0.5,
        gripScore: _glareIceFloor - 0.001,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), AlertSeverity.critical);
    });

    test('grip exactly AT the floor is not critical on grip alone', () {
      // The other side of the strict comparison, asserted so the boundary
      // is pinned by a test rather than by a comment.
      final config = NavigationSafetyConfig();
      final score = SafetyScore(
        overall: 0.5 * _glareIceFloor + 0.5,
        gripScore: _glareIceFloor,
        visibilityScore: 1.0,
        fleetConfidenceScore: 1.0,
      );
      expect(score.toAlertSeverity(config), isNot(AlertSeverity.critical));
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
      'the per-axis rule NEVER lowers severity, over the derived-mean slice',
      () {
        // READ THE BOUND IN THE NAME. This sweep RECOMPUTES `overall` from
        // the two axes. `overall` is not derived by this package — the
        // README calls it "an `overall` score the caller supplies" — so it
        // is a THIRD independent input, and this loop walks a 2-D slice of
        // a 3-D domain. The group below sweeps the surface the constructor
        // actually accepts.
        final config = NavigationSafetyConfig();
        var promoted = 0;
        var allClearDisturbed = 0;
        const n = 101;
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final grip = i / (n - 1);
            final visibility = j / (n - 1);
            final overall = 0.5 * grip + 0.5 * visibility;
            final before = _compositeOnly(config, overall);
            final after = SafetyScore(
              overall: overall,
              gripScore: grip,
              visibilityScore: visibility,
              fleetConfidenceScore: 1.0,
            ).toAlertSeverity(config);

            expect(
              _rank[after]! >= _rank[before]!,
              isTrue,
              reason:
                  'grip=$grip visibility=$visibility: severity FELL from '
                  '$before to $after — the axis rule must be monotone',
            );
            if (_rank[after]! > _rank[before]!) promoted++;
            if (before == null && after != null) allClearDisturbed++;
          }
        }
        // It does change something — a rule that promotes nothing is ornament.
        expect(promoted, greaterThan(0));
        // Zero here is ARITHMETIC, NOT EVIDENCE. On this slice, grip below
        // `criticalGripScoreFloor` (0.2727…) caps the 50/50 mean at
        // 0.5 * 0.2727… + 0.5 = 0.635, while the LOWEST `safeScoreFloor`
        // this package ships is 0.80. "silent before AND alerting after" is
        // unsatisfiable here, so this counter cannot be anything but 0
        // whatever the rule does. It is pinned to say so, not to reassure.
        expect(allClearDisturbed, 0);
      },
    );
  });

  group('the free `overall` surface the constructor accepts', () {
    // `SafetyScore` clamps each field to [0,1] and does NOTHING else: it
    // never recomputes `overall` from the axes and never checks the two
    // against each other. Any integrator whose `overall` is not our 50/50
    // mean — a different weighting, more axes, a model of their own, or the
    // FFI `overallMean` that `driving_conditions`' native engine passes
    // straight through — lives OFF the slice above.
    late int freeCells, freePromoted, freeOutOfNone, freeLowered;
    late int slicedCells, slicedPromoted, slicedOutOfNone, slicedLowered;
    late int slicedWarningToCritical, slicedInfoToCritical;

    setUpAll(() {
      const n = 101;
      final configs = <NavigationSafetyConfig>[
        NavigationSafetyConfig(),
        ...DriverProfile.values.map(NavigationSafetyConfig.forProfile),
      ];

      slicedCells = slicedPromoted = slicedOutOfNone = slicedLowered = 0;
      slicedWarningToCritical = slicedInfoToCritical = 0;
      for (final c in configs) {
        for (var i = 0; i < n; i++) {
          for (var j = 0; j < n; j++) {
            final grip = i / (n - 1), vis = j / (n - 1);
            final overall = 0.5 * grip + 0.5 * vis;
            slicedCells++;
            final b = _compositeOnly(c, overall);
            final a = SafetyScore(
              overall: overall,
              gripScore: grip,
              visibilityScore: vis,
              fleetConfidenceScore: 1.0,
            ).toAlertSeverity(c);
            if (_rank[a]! > _rank[b]!) slicedPromoted++;
            if (_rank[a]! < _rank[b]!) slicedLowered++;
            if (b == null && a != null) slicedOutOfNone++;
            if (b == AlertSeverity.warning && a == AlertSeverity.critical) {
              slicedWarningToCritical++;
            }
            if (b == AlertSeverity.info && a == AlertSeverity.critical) {
              slicedInfoToCritical++;
            }
          }
        }
      }

      freeCells = freePromoted = freeOutOfNone = freeLowered = 0;
      for (final c in configs) {
        for (var k = 0; k < n; k++) {
          final overall = k / (n - 1);
          for (var i = 0; i < n; i++) {
            for (var j = 0; j < n; j++) {
              final grip = i / (n - 1), vis = j / (n - 1);
              freeCells++;
              final b = _compositeOnly(c, overall);
              final a = SafetyScore(
                overall: overall,
                gripScore: grip,
                visibilityScore: vis,
                fleetConfidenceScore: 1.0,
              ).toAlertSeverity(c);
              if (_rank[a]! > _rank[b]!) freePromoted++;
              if (_rank[a]! < _rank[b]!) freeLowered++;
              if (b == null && a != null) freeOutOfNone++;
            }
          }
        }
      }
    });

    test('the numbers the CHANGELOG cites are the numbers measured', () {
      // 0.11.10 printed these four counts and said they were "Asserted in
      // test/grip_axis_critical_test.dart". They were asserted nowhere.
      // They are asserted here, so the citation is true.
      expect(slicedCells, 71407);
      expect(slicedPromoted, 9721);
      expect(slicedWarningToCritical, 7723);
      expect(slicedInfoToCritical, 1998);
      expect(slicedLowered, 0);
      expect(slicedOutOfNone, 0);
    });

    test('no alert 0.11.9 delivers is silenced, on the WHOLE surface', () {
      // The safety property, and the one that must never break. It holds
      // off the slice as well as on it: 7,212,107 cells, none lowered.
      expect(freeCells, 7212107);
      expect(freeLowered, 0);
      expect(freePromoted, 1357440);
    });

    test('the release DOES speak where 0.11.9 was silent', () {
      // 0.11.10's CHANGELOG said it "cannot make the package speak where
      // 0.11.9 was silent". Off the derived slice it can, and this is the
      // count. A test that could not have produced this number is a test
      // that proved nothing.
      expect(
        freeOutOfNone,
        359156,
        reason:
            'cells that are silent on 0.11.9 and alerting on 0.11.10, over '
            'the free (overall, grip, visibility) surface on all seven '
            'configs — new alert volume an integrator must expect',
      );
    });

    test('the probe that the derived slice could not reach', () {
      // Measured against the PUBLISHED 0.11.9 archive: `null`.
      // A legal construction: every field is in [0,1].
      final score = SafetyScore(
        overall: 0.8, // NOT 0.5 * 0.0 + 0.5 * 1.0 — the caller's own number
        gripScore: 0.0, // the road brakes like glare ice
        visibilityScore: 1.0, // under a clear sky
        fleetConfidenceScore: 1.0,
      );
      expect(
        score.toAlertSeverity(NavigationSafetyConfig()),
        AlertSeverity.critical,
      );
      // And it is unreachable on the derived slice: with grip 0.0 the
      // 50/50 mean is at most 0.5, never 0.8.
      expect(0.5 * 0.0 + 0.5 * 1.0, lessThan(0.8));
    });
  });
}

const _rank = <AlertSeverity?, int>{
  null: 0,
  AlertSeverity.info: 1,
  AlertSeverity.warning: 2,
  AlertSeverity.critical: 3,
};

/// The 0.11.9 rule, recomputed so the comparison is against behaviour and
/// not a remembered table. Verified against the published 0.11.9 archive:
/// composite-only, against these same three floors.
AlertSeverity? _compositeOnly(NavigationSafetyConfig c, double overall) {
  if (overall < c.warningScoreFloor) return AlertSeverity.critical;
  if (overall < c.infoScoreFloor) return AlertSeverity.warning;
  if (overall < c.safeScoreFloor) return AlertSeverity.info;
  return null;
}
