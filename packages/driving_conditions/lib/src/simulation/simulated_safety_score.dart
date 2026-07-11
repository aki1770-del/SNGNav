/// The safety score produced by a simulation run — with an HONEST fleet term.
///
/// ## Why this type exists (0.6.0)
///
/// Up to 0.5.4 the simulation lane produced a `SafetyScore` (from
/// `navigation_safety_core`) whose `fleetConfidenceScore` is a NON-NULLABLE
/// `double`. A `double` cannot say "no fleet reported anything", so the
/// adapter filled the gap with a literal:
///
/// ```dart
/// static const double _neutralBaseline = 0.8;   // fleet_hazard_confidence_adapter
/// if (recent.isEmpty) return _neutralBaseline;  // no reports at all
/// if (totalWeight == 0.0) return _neutralBaseline;
/// RoadCondition.unknown => _neutralBaseline,    // an EXPLICITLY unknown report
/// ```
///
/// `0.8` was called a "neutral baseline". It is not neutral — it is optimistic
/// (`dry` scores 1.0, `snowy` 0.4), and it was folded into `overall` with
/// weight 0.2. So **silence from the fleet RAISED the computed safety score**.
/// That is the same defect class as the fabricated `+5.0 °C`, in the term that
/// is supposed to represent what other drivers are actually reporting from the
/// road.
///
/// The fix has two halves, and both are here:
///
/// 1. [fleetConfidenceScore] is **nullable**. `null` means NO FLEET DATA — never
///    0.8, never 0.0 ("the fleet reports danger", which would be the same lie
///    pointed the other way and would cry wolf until she stopped believing it).
/// 2. [overall] is computed by RE-NORMALISING the weights over the terms that
///    were actually MEASURED. An unmeasured term is not folded in at any value,
///    so fleet silence neither raises nor lowers the score. It simply is not
///    part of it, and the object says so.
library;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

double _clamp01(double value) {
  if (!value.isFinite) return 0;
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

/// Relative weights of the three terms. When a term is absent, the remaining
/// weights are re-normalised over what is known.
const double _gripWeight = 0.4;
const double _visibilityWeight = 0.4;
const double _fleetWeight = 0.2;

class SimulatedSafetyScore extends Equatable {
  /// Grip term, `[0, 1]`.
  final double gripScore;

  /// Visibility term, `[0, 1]`.
  final double visibilityScore;

  /// Fleet-confidence term, `[0, 1]`, or **`null` when no fleet data was
  /// available**.
  ///
  /// `null` is NOT a low score and NOT a high one. It means the fleet said
  /// nothing — either no report arrived inside the recency window, or the only
  /// reports carried `RoadCondition.unknown`. Read it before you render it: a
  /// UI that prints a number here for an absent fleet is re-creating the
  /// defect this type was introduced to remove.
  final double? fleetConfidenceScore;

  /// Overall safety, `[0, 1]` — a weighted mean over the terms that were
  /// actually measured.
  ///
  /// When [fleetConfidenceScore] is `null`, grip and visibility are
  /// re-normalised to carry the whole weight. No value is substituted for the
  /// missing term.
  final double overall;

  SimulatedSafetyScore({
    required double gripScore,
    required double visibilityScore,
    required double? fleetConfidenceScore,
    double? overall,
  }) : gripScore = _clamp01(gripScore),
       visibilityScore = _clamp01(visibilityScore),
       fleetConfidenceScore = fleetConfidenceScore == null
           ? null
           : _clamp01(fleetConfidenceScore),
       overall = _clamp01(
         overall ??
             _weightedMean(
               grip: _clamp01(gripScore),
               visibility: _clamp01(visibilityScore),
               fleet: fleetConfidenceScore == null
                   ? null
                   : _clamp01(fleetConfidenceScore),
             ),
       );

  /// True when the fleet term was measured and is part of [overall].
  bool get hasFleetData => fleetConfidenceScore != null;

  static double _weightedMean({
    required double grip,
    required double visibility,
    required double? fleet,
  }) {
    if (fleet == null) {
      // Re-normalise over the KNOWN terms. The absent term contributes
      // nothing — not 0.8, not 0.0, not anything.
      const known = _gripWeight + _visibilityWeight;
      return (grip * _gripWeight + visibility * _visibilityWeight) / known;
    }
    return grip * _gripWeight +
        visibility * _visibilityWeight +
        fleet * _fleetWeight;
  }

  /// Alert severity for this score under [config] — the same thresholds
  /// `navigation_safety_core`'s `SafetyScore` applies to `overall`.
  AlertSeverity? toAlertSeverity(NavigationSafetyConfig config) {
    if (overall < config.warningScoreFloor) return AlertSeverity.critical;
    if (overall < config.infoScoreFloor) return AlertSeverity.warning;
    if (overall < config.safeScoreFloor) return AlertSeverity.info;
    return null;
  }

  @override
  List<Object?> get props => [
    overall,
    gripScore,
    visibilityScore,
    fleetConfidenceScore,
  ];

  @override
  String toString() =>
      'SimulatedSafetyScore(overall: ${overall.toStringAsFixed(2)}, '
      'grip: ${gripScore.toStringAsFixed(2)}, '
      'visibility: ${visibilityScore.toStringAsFixed(2)}, '
      'fleet: ${fleetConfidenceScore == null ? 'not measured' : fleetConfidenceScore!.toStringAsFixed(2)})';
}
