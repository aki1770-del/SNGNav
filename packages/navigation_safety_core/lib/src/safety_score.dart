/// Composite safety score model for navigation risk communication.
library;

import 'package:equatable/equatable.dart';

import 'alert_severity.dart';
import 'navigation_safety_config.dart';

double _clamp01(double value) {
  // Conservative-on-uncertain invariant: a
  // non-finite value (NaN / +Infinity / -Infinity) is an invalid or
  // uncertain score. Map it to 0 — the worst-case value — so it ALERTS
  // conservatively (overall < warningScoreFloor → critical) instead of
  // silently passing. Without this guard NaN compares false to both
  // bounds below and slips through unclamped; in `toAlertSeverity` every
  // `<` against NaN is then false, yielding null (no alert), and
  // +Infinity would clamp to 1 (no alert). Both invert the "if
  // uncertain, alert conservatively" intent. (The conservative-alert
  // guarantee assumes warningScoreFloor > 0 — true for all shipped configs.)
  if (!value.isFinite) return 0;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

class SafetyScore extends Equatable {
  final double overall;
  final double gripScore;
  final double visibilityScore;
  final double fleetConfidenceScore;

  SafetyScore({
    required double overall,
    required double gripScore,
    required double visibilityScore,
    required double fleetConfidenceScore,
  }) : overall = _clamp01(overall),
       gripScore = _clamp01(gripScore),
       visibilityScore = _clamp01(visibilityScore),
       fleetConfidenceScore = _clamp01(fleetConfidenceScore);

  /// Severity for this score under [config] — the WORSE of the composite
  /// verdict and the per-axis verdict.
  ///
  /// ## Why two verdicts and not one
  ///
  /// **CORRECTED IN 0.11.11.** Through 0.11.10 this paragraph opened
  /// "[overall] is a MEAN of the axes" and concluded that
  /// [AlertSeverity.critical] "was UNREACHABLE at any grip whatsoever".
  /// **Both were false.** [overall] is a THIRD caller-supplied input — the
  /// constructor clamps it and nothing in this package ever recomputes it
  /// from the axes — and on 0.11.9 `SafetyScore(overall: 0.2,
  /// gripScore: 1.0, visibilityScore: 1.0, fleetConfidenceScore: 1.0)`
  /// already returned [AlertSeverity.critical] at PERFECT grip, because the
  /// composite returns `critical` whenever [overall] is below
  /// [NavigationSafetyConfig.warningScoreFloor] (default 0.30). Both
  /// statements hold only on the 50/50 slice. What follows is the true
  /// statement.
  ///
  /// A mean answers "how good are conditions on aggregate"; severity asks
  /// "how bad is the worst thing here". The two come apart precisely when
  /// one axis is catastrophic and the other is fine — **black ice under a
  /// clear sky**. WHEN [overall] IS the 50/50 mean of the axes — which is
  /// what `driving_conditions` supplies, from both its engines — then with
  /// [visibilityScore] at 1.0 the mean is >= 0.5, while every shipped
  /// [NavigationSafetyConfig.warningScoreFloor] is 0.30-0.40, so
  /// [AlertSeverity.critical] was unreachable at any grip value ON THAT
  /// SLICE.
  /// Measured on 0.11.9 at [gripScore] `0.0` with [visibilityScore] `1.0`:
  /// [AlertSeverity.info] on three of the six [DriverProfile] baselines
  /// (`snowZoneExperienced`, `professional`, `agriculturalForestry`) and on
  /// the default config, and [AlertSeverity.warning] on the other three
  /// (`ageingRural`, `noviceUrban`, `foreignTouristSnowZone`). An advisory
  /// grade either way, on a road she cannot stop on. This type carried the
  /// per-axis numbers all along and the decision discarded them.
  ///
  /// The correction is not a lower floor. Lowering a threshold so one
  /// number crosses it drags every other road across with it, and a model
  /// that shouts at everything is the cry-wolf failure. Instead [overall]
  /// keeps its stated meaning and fixed weights, the axes are read
  /// separately, and the worse verdict wins.
  ///
  /// ## The property that makes this safe to add
  ///
  /// Taking the WORSE verdict is monotone: it can only raise severity,
  /// never lower it, so no alert that fires today can be silenced by it.
  /// Measured over the whole `(grip, visibility)` plane at default floors,
  /// every promotion is out of a band that was ALREADY alerting and ZERO
  /// cells are promoted out of `none` — it sharpens alerts, it does not
  /// add them. Both properties are asserted in
  /// `test/grip_axis_critical_test.dart`.
  ///
  /// ## What is NOT covered yet
  ///
  /// Only grip has a per-axis floor here. [NavigationSafetyConfig] also
  /// declares `criticalVisibilityMeters` — profile-tuned and
  /// literature-cited — and **nothing in this package reads it**; the
  /// visibility axis therefore still reaches the decision only through the
  /// mean. Wiring it is a separate, deliberate change, because it moves
  /// behaviour for consumers on a second axis.
  AlertSeverity? toAlertSeverity(NavigationSafetyConfig config) {
    final composite = _compositeSeverity(config);
    // A grip score BELOW the floor means the road brakes no better than
    // glare ice. That is independently lethal — it does not become
    // survivable because she can see it coming.
    //
    // The comparison is strict, matching `_compositeSeverity` below and the
    // score floors it uses: a score exactly EQUAL to the floor is not
    // critical on grip alone.
    //
    // `gripScore` of 0 is never an encoding of "no grip sensor": an
    // unreadable reading is rejected upstream in `driving_conditions`
    // (`requireMeasured`), and `_clamp01` above maps a non-finite value to 0
    // *deliberately*, so that uncertainty alerts conservatively. Both
    // readings of 0 want this alert.
    if (gripScore < config.criticalGripScoreFloor) {
      return AlertSeverity.critical;
    }
    return composite;
  }

  AlertSeverity? _compositeSeverity(NavigationSafetyConfig config) {
    if (overall < config.warningScoreFloor) {
      return AlertSeverity.critical;
    }
    if (overall < config.infoScoreFloor) {
      return AlertSeverity.warning;
    }
    if (overall < config.safeScoreFloor) {
      return AlertSeverity.info;
    }
    return null;
  }

  @override
  List<Object?> get props => [
    overall,
    gripScore,
    visibilityScore,
    fleetConfidenceScore,
  ];
}
