/// Adapter that derives fleet confidence from FleetReport observations.
library;

import 'package:fleet_hazard/fleet_hazard.dart';

import 'fleet_confidence_provider.dart';

/// Derives a [FleetConfidenceProvider] score from a list of [FleetReport]s.
///
/// Filters to recent reports, maps each [RoadCondition] to a safety factor,
/// and returns a weighted average by per-report observation confidence.
///
/// Safety factor mapping:
/// | Condition | Factor       |
/// |-----------|:------------:|
/// | dry       | 1.0          |
/// | wet       | 0.7          |
/// | snowy     | 0.4          |
/// | icy       | 0.1          |
/// | unknown   | *no weight*  |
///
/// [confidence] is `null` — NOT a number — on every absence path: no recent
/// reports, every recent report `unknown`, every report carrying a non-usable
/// self-confidence, or zero total weight. Absence of data is not evidence of
/// danger, and it is not evidence of safety either.
///
/// ## What this adapter is FOR, as of 0.7.0
///
/// **It no longer feeds the safety score.** `SimulatedSafetyScore` has no fleet
/// term — the term never carried a real reading, and the four attempts to make
/// its absence honest are catalogued in that type's own documentation.
///
/// This class is kept, exported and supported anyway, and that is a deliberate
/// choice rather than an oversight. It is honest, useful, standalone code: it
/// turns a list of real observations into one number and says `null` when there
/// were none. A consumer who actually has fleet telemetry has every right to
/// read it, render it, and act on it. What changed is that this package no
/// longer folds it into a number it presents as *the* safety score. Deleting a
/// working public symbol to make a point would have broken consumers for no
/// safety gain.
///
/// ```dart
/// final fleet = FleetHazardConfidenceAdapter(reports).confidence;
/// if (fleet == null) {
///   // The fleet said nothing. Not "probably fine".
/// } else {
///   // A real reading from real vehicles. Yours to use.
/// }
///
/// // The safety score is computed independently, from grip and visibility:
/// final result = const SafetyScoreSimulator().simulate(/* ... */);
/// ```
class FleetHazardConfidenceAdapter implements FleetConfidenceProvider {
  /// Creates an adapter over [reports].
  ///
  /// [maxAge] controls the recency window (default 15 minutes).
  const FleetHazardConfidenceAdapter(
    this._reports, {
    this.maxAge = const Duration(minutes: 15),
  });

  final List<FleetReport> _reports;

  /// Maximum age of reports to include.
  final Duration maxAge;

  /// Fleet-derived confidence, or **`null` when the fleet said nothing**.
  ///
  /// Up to 0.5.4 all absence paths returned `0.8`, called a "neutral baseline".
  /// It was never neutral: `dry` scores 1.0 and `snowy` 0.4, so 0.8 is an
  /// OPTIMISTIC report. 0.6.0 made them `null`.
  ///
  /// ⚑ **0.7.0 closes the path 0.6.0 missed.** The final `.clamp(0.0, 1.0)`
  /// turned a non-finite weighted mean into exactly `1.0` — the top of the
  /// scale, *"the fleet reports consistently safe conditions"* — manufactured
  /// out of unreadable data. `double.nan.clamp(0.0, 1.0)` returns `1.0`, and
  /// `double.nan == 0.0` is `false`, so the zero-weight guard below never
  /// fired. Measured against published 0.6.0: four `icy` reports carrying a
  /// `nan` self-confidence returned `confidence == 1.0`. **The ice was erased
  /// and replaced with the best reading the scale can express.**
  ///
  /// A report whose own confidence is not a usable number now carries no
  /// weight, exactly as `RoadCondition.unknown` does — a vehicle that cannot
  /// say how sure it is has not told us anything about the road. If that leaves
  /// nothing to average, the answer is `null`.
  @override
  double? get confidence {
    final recent = _reports.where((r) => r.isRecent(maxAge: maxAge)).toList();
    // No recent report at all. Not "the road is probably fine".
    if (recent.isEmpty) return null;

    var total = 0.0;
    var totalWeight = 0.0;

    for (final r in recent) {
      // A report whose road condition is EXPLICITLY unknown tells us nothing
      // about the road. It carried 0.8 — a grip-like factor — which meant a
      // driver reporting "I don't know" nudged the score upward. It now carries
      // no weight at all.
      final factor = _conditionFactor(r.condition);
      if (factor == null) continue;
      // Same treatment for a self-confidence that is not a usable weight.
      // `nan`/`inf` poison the running sums, and a negative weight would let
      // one report subtract another's hazard back out.
      if (!r.confidence.isFinite || r.confidence < 0) continue;
      total += factor * r.confidence;
      totalWeight += r.confidence;
    }

    // Every recent report was unknown-condition, unusable-confidence, or
    // zero self-confidence. Either way nothing was actually reported about
    // the road.
    if (totalWeight <= 0.0) return null;

    final mean = total / totalWeight;
    // Both operands are finite and totalWeight > 0, so `mean` is finite; the
    // guard stands anyway because the alternative failure mode is silent and
    // reads as an all-clear.
    if (!mean.isFinite) return null;
    if (mean < 0.0) return 0.0;
    if (mean > 1.0) return 1.0;
    return mean;
  }

  /// Grip-like factor for a reported road condition, or `null` when the report
  /// carries no information about the road.
  static double? _conditionFactor(RoadCondition condition) =>
      switch (condition) {
        RoadCondition.dry => 1.0,
        RoadCondition.wet => 0.7,
        RoadCondition.snowy => 0.4,
        RoadCondition.icy => 0.1,
        // NOT a number. "Unknown" is not a mildly-good road.
        RoadCondition.unknown => null,
      };
}
