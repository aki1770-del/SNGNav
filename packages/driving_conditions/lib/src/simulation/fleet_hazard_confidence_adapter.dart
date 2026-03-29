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
    final recent =
        _reports.where((r) => r.isRecent(maxAge: maxAge)).toList();
    if (recent.isEmpty) return _neutralBaseline;

    var total = 0.0;
    var totalWeight = 0.0;

    for (final r in recent) {
      final factor = _conditionFactor(r.condition);
      total += factor * r.confidence;
      totalWeight += r.confidence;
    }

    if (totalWeight == 0.0) return _neutralBaseline;
    return (total / totalWeight).clamp(0.0, 1.0);
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
