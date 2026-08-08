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
/// | Condition | Factor |
/// |-----------|:------:|
/// | dry       | 1.0    |
/// | wet       | 0.7    |
/// | snowy     | 0.4    |
/// | icy       | 0.1    |
/// | unknown   | 0.8    |
///
/// When no recent reports exist the adapter returns 0.8 — the neutral
/// baseline. Absence of data is not evidence of danger.
///
/// If the weighted average cannot be computed — because some
/// [FleetReport.confidence] in the recent set is NaN or infinite — the
/// adapter returns that non-finite value **unchanged**. It is deliberately
/// not clamped into `[0.0, 1.0]`: `num.clamp` maps NaN and `+Infinity` to the
/// upper bound, so clamping would report maximum safety for evidence that
/// could not be read at all. See [confidence].
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

  /// Neutral baseline returned when no recent fleet data is available.
  static const double _neutralBaseline = 0.8;

  @override
  double get confidence {
    final recent = _reports.where((r) => r.isRecent(maxAge: maxAge)).toList();
    if (recent.isEmpty) return _neutralBaseline;

    var total = 0.0;
    var totalWeight = 0.0;

    for (final r in recent) {
      final factor = _conditionFactor(r.condition);
      total += factor * r.confidence;
      totalWeight += r.confidence;
    }

    if (totalWeight == 0.0) return _neutralBaseline;

    final average = total / totalWeight;

    // Do NOT sanitise a non-finite average into a finite one.
    //
    // `num.clamp` maps NaN and +Infinity to the UPPER bound. Measured on the
    // Dart VM: `double.nan.clamp(0.0, 1.0)` is `1.0`, and that result's
    // `.isFinite` is `true`. Clamping here would therefore turn "this could
    // not be computed" into `1.0` — which [FleetConfidenceProvider] defines as
    // "fleet reports consistently safe conditions" — and would do it before
    // any consumer could tell the two apart.
    //
    // It would also disarm a guard downstream. `navigation_safety_core`'s
    // conservative-on-uncertain invariant (GAP-1, `safety_score.dart`) maps a
    // non-finite score to 0 so that it ALERTS. That guard can only fire on a
    // value that is still non-finite when it reaches it.
    //
    // A non-finite return asserts nothing in either direction: every
    // comparison against NaN is false, so a consumer that does not handle it
    // makes no claim. Only a consumer that has opted into
    // conservative-on-uncertain turns it into an alert. That decision belongs
    // to the consumer, not to this adapter.
    if (!average.isFinite) return average;

    return average.clamp(0.0, 1.0);
  }

  static double _conditionFactor(RoadCondition condition) =>
      switch (condition) {
        RoadCondition.dry => 1.0,
        RoadCondition.wet => 0.7,
        RoadCondition.snowy => 0.4,
        RoadCondition.icy => 0.1,
        RoadCondition.unknown => _neutralBaseline,
      };
}
