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
/// [confidence] is `null` — NOT a number — on all three absence paths: no
/// recent reports, every recent report `unknown`, or zero total weight.
/// Absence of data is not evidence of danger, and it is not evidence of
/// safety either; it is left out of the score rather than scored.
///
/// ```dart
/// final adapter = FleetHazardConfidenceAdapter(reports);
/// final engine = CpuSafetyScoreSimulationEngine(provider: adapter);
/// final result = engine.simulate(...);
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
  /// Up to 0.5.4 all three absence paths below returned `0.8`, called a
  /// "neutral baseline". It was never neutral: `dry` scores 1.0 and `snowy`
  /// 0.4, so 0.8 is an OPTIMISTIC report — and it was folded into the overall
  /// safety score with weight 0.2. Silence from the fleet therefore RAISED the
  /// score. An absent report is now absent.
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
      total += factor * r.confidence;
      totalWeight += r.confidence;
    }

    // Every recent report was unknown-condition, or every report carried zero
    // self-confidence. Either way nothing was actually reported about the road.
    if (totalWeight == 0.0) return null;
    return (total / totalWeight).clamp(0.0, 1.0);
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
