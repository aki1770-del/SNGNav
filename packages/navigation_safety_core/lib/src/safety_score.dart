/// Composite safety score model for navigation risk communication.
library;

import 'package:equatable/equatable.dart';

import 'alert_severity.dart';
import 'navigation_safety_config.dart';

double _clamp01(double value) {
  // Conservative-on-uncertain invariant (GAP-1): a
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

  AlertSeverity? toAlertSeverity(NavigationSafetyConfig config) {
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
