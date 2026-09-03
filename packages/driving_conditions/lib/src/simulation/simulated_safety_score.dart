/// The safety score produced by a simulation run — over the terms that have a
/// source.
///
/// ## Why there is no fleet term here (0.7.0)
///
/// Up to 0.6.0 `overall` was `0.4*grip + 0.4*visibility + 0.2*fleet`. Four
/// separate defects were found and fixed in that fleet term, in this order:
///
/// 1. The engines' default provider was `ConstantFleetConfidenceProvider()`,
///    whose value defaulted to `0.8`. A consumer who wired **no fleet source at
///    all** got `hasFleetData == true` and an optimistic 0.8 folded in at weight
///    0.2. Silence RAISED the score.
/// 2. The adapter's `.clamp(0.0, 1.0)` turned a non-finite confidence into
///    exactly `1.0` — *"fleet reports consistently safe conditions"*,
///    manufactured from unreadable data (`double.nan.clamp(0, 1) == 1.0`, and
///    `double.nan == 0.0` is `false`, so the zero-weight guard never fired).
/// 3. Excluding an absent term and RE-NORMALISING the remaining weights is
///    arithmetically identical to imputing the absent term as the MEAN of the
///    measured ones (max deviation 1.11e-16 across 40,401 grid cells). Absence
///    did not read as "unknown" — it silently agreed with everything else, and
///    in good conditions it scored HIGHER than the 0.8 default that had just
///    been removed as optimistic.
/// 4. A rebuilt version replaced re-normalisation with a floor of 0.1. It
///    proved the absence invariant on 3,676,491 triples with 0 violations —
///    and made the all-clear unreachable: at shipped defaults the maximum
///    attainable `overall` was 0.780257, below every `DriverProfile`'s
///    `safeScoreFloor`. A permanent warning band is a light she stops seeing.
///
/// Each fix was real and each was insufficient, because all four were tuned as
/// though absence were an edge case. **It is the only case.** The fleet term has
/// never carried a real reading: the four `FleetProvider` implementations that
/// exist are three test doubles and one simulator of five fake vehicles on
/// Route 153 seeded `Random(42)`, whose own header says *"Production
/// replacement: real fleet telemetry API."* That replacement does not exist.
///
/// **A term with no source does not carry weight in a safety score.** The fleet
/// term is gone from this type. The reading API — `FleetConfidenceProvider`,
/// `ConstantFleetConfidenceProvider` and `FleetHazardConfidenceAdapter` — is
/// kept and still exported, because a consumer with a real fleet source has
/// every right to read it; it simply is not laundered into a number this
/// package presents as a safety score.
///
/// ## The two rules this type now holds
///
/// **1. The weights are stated, and are NEVER re-normalised.** [_gripWeight] and
/// [_visibilityWeight] are constants that sum to exactly 1.0 and do not vary
/// with what happened to be measured. There is no third term whose absence
/// could be imputed, and no arithmetic anywhere that divides by "the weights
/// that are present" — that division is defect 3 above, and it must not return
/// in any spelling.
///
/// **2. A number that is not a number is not a measurement.** Every input is
/// checked for finiteness and a non-finite one is REJECTED, not coerced. This
/// closes defect 2 in the terms that survived it: on 0.6.0, `gripFactor:
/// double.nan` produced `gripScore == 1.0` via the same `.clamp` semantics, and
/// a run with both grip and visibility unreadable scored `overall 0.9373`,
/// band `none` — an all-clear rated *higher than a genuinely perfect dry road
/// at zero speed* (0.9178). Unreadable sensors now throw [ArgumentError]
/// rather than reporting the best road she could possibly be on.
library;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Rejects a non-finite [value] and coerces a finite one into `[0, 1]`.
///
/// The coercion is deliberate and the rejection is deliberate, and they are
/// different acts. Clamping `1.2` to `1.0` narrows a real number to the range
/// this score is defined on. Clamping `double.nan` to `1.0` — which is what
/// `num.clamp` actually does — INVENTS a perfect reading out of a broken
/// sensor. The first is range coercion; the second is fabrication, and it is
/// the defect that shipped in 0.6.0's grip and visibility terms.
double _finite01(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      name,
      'must be finite — a non-finite value is an unreadable measurement, and '
      'this score will not stand in a number for one (num.clamp would silently '
      'turn it into 1.0, the best possible reading)',
    );
  }
  if (value < 0) return 0;
  if (value > 1) return 1;
  return value;
}

/// Weight of the grip term in [SimulatedSafetyScore.overall].
///
/// Stated explicitly. Never re-normalised — see the library doc, rule 1.
const double _gripWeight = 0.5;

/// Weight of the visibility term in [SimulatedSafetyScore.overall].
///
/// Stated explicitly. Never re-normalised — see the library doc, rule 1.
const double _visibilityWeight = 0.5;

class SimulatedSafetyScore extends Equatable {
  /// Grip term, `[0, 1]`. Weighted [_gripWeight] in [overall].
  final double gripScore;

  /// Visibility term, `[0, 1]`. Weighted [_visibilityWeight] in [overall].
  final double visibilityScore;

  /// Overall safety, `[0, 1]` — `0.5 * grip + 0.5 * visibility`.
  ///
  /// Both terms are always present and always carry the weight stated above.
  /// Nothing here is conditional on what was measured, so nothing here can
  /// change meaning between two runs of the same code.
  final double overall;

  SimulatedSafetyScore({
    required double gripScore,
    required double visibilityScore,
    double? overall,
  }) : gripScore = _finite01(gripScore, 'gripScore'),
       visibilityScore = _finite01(visibilityScore, 'visibilityScore'),
       overall = _finite01(
         overall ??
             _weightedMean(
               grip: _finite01(gripScore, 'gripScore'),
               visibility: _finite01(visibilityScore, 'visibilityScore'),
             ),
         'overall',
       );

  /// `0.5 * grip + 0.5 * visibility`, with both weights fixed.
  ///
  /// There is no branch in this function, and that is the point. The 0.6.0
  /// version had one — `if (fleet == null) ... / known` — and that branch was
  /// defect 3: it made the meaning of the returned number depend on which
  /// terms had arrived.
  static double _weightedMean({
    required double grip,
    required double visibility,
  }) => grip * _gripWeight + visibility * _visibilityWeight;

  /// Alert severity for this score under [config] — the same thresholds
  /// `navigation_safety_core`'s `SafetyScore` applies to `overall`.
  AlertSeverity? toAlertSeverity(NavigationSafetyConfig config) {
    if (overall < config.warningScoreFloor) return AlertSeverity.critical;
    if (overall < config.infoScoreFloor) return AlertSeverity.warning;
    if (overall < config.safeScoreFloor) return AlertSeverity.info;
    return null;
  }

  @override
  List<Object?> get props => [overall, gripScore, visibilityScore];

  @override
  String toString() =>
      'SimulatedSafetyScore(overall: ${overall.toStringAsFixed(2)}, '
      'grip: ${gripScore.toStringAsFixed(2)}, '
      'visibility: ${visibilityScore.toStringAsFixed(2)})';
}
