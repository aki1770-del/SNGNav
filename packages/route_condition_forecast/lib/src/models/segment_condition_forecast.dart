import 'package:equatable/equatable.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'route_segment.dart';

/// Forecasted driving conditions for a single route segment.
///
/// Produced by [RouteConditionForecaster] for each [RouteSegment].
/// Combines weather forecast data with fleet-reported hazard zones
/// that geometrically intersect the segment.
class SegmentConditionForecast extends Equatable {
  /// The route segment this forecast applies to.
  final RouteSegment segment;

  /// Forecasted weather at this segment's ETA.
  final WeatherCondition condition;

  /// Fleet hazard zones whose radius overlaps any point of this segment.
  final List<HazardZone> hazardZones;

  /// Estimated seconds from departure before reaching this segment.
  final double etaSeconds;

  /// Forecast confidence [0, 1]. Degrades with forecast horizon.
  /// 1.0 at departure; ~0.5 at 8 hours ahead.
  final double confidence;

  const SegmentConditionForecast({
    required this.segment,
    required this.condition,
    required this.hazardZones,
    required this.etaSeconds,
    required this.confidence,
  });

  /// Is this segment hazardous? **Tri-state — see [SafetyVerdict].**
  ///
  /// Up to 0.1.5 this was `bool get isHazardous => condition.isHazardous || ...`.
  /// A `bool` cannot say "I do not know", so a segment whose weather was never
  /// measured silently reported `false` — **not hazardous** — and a route made
  /// entirely of unmeasured segments reported itself CLEAR. That is the
  /// fabrication defect arriving one layer downstream of where it was fixed.
  ///
  /// The asymmetry (contract O2) holds here too:
  /// * a fleet hazard zone, or hazardous weather, is POSITIVE evidence and
  ///   fires even if everything else about the segment is unknown;
  /// * [SafetyVerdict.notHazardous] requires actually KNOWING the weather;
  /// * otherwise [SafetyVerdict.unknown] — which propagates upward and, in
  ///   `adaptive_reroute`, becomes "could not assess" rather than "route clear".
  SafetyVerdict get hazard {
    // A reported fleet hazard zone is a real observation. It fires regardless
    // of what the weather feed did or did not say.
    if (hazardZones.isNotEmpty) return SafetyVerdict.hazardous;
    return condition.hazard;
  }

  /// True if at least one fleet hazard zone overlaps this segment.
  ///
  /// This stays a `bool` honestly: we always know whether we hold zones. An
  /// empty list means no zone was REPORTED here, which is a fact about our
  /// fleet data, not a claim that the road is safe.
  bool get hasFleetHazard => hazardZones.isNotEmpty;

  /// The weather-only verdict for this segment (ignoring fleet data).
  ///
  /// [SafetyVerdict.unknown] when the forecast for this segment carried no
  /// measurements — never `false`/"clear".
  SafetyVerdict get weatherHazard => condition.hazard;

  /// True when this segment's conditions could not be assessed at all.
  bool get isUnassessed => hazard == SafetyVerdict.unknown;

  /// Highest fleet hazard severity present, or null if no fleet hazards.
  HazardSeverity? get worstFleetSeverity {
    if (hazardZones.isEmpty) return null;
    return hazardZones.any((z) => z.severity == HazardSeverity.icy)
        ? HazardSeverity.icy
        : HazardSeverity.snowy;
  }

  @override
  List<Object?> get props => [
    segment,
    condition,
    hazardZones,
    etaSeconds,
    confidence,
  ];

  @override
  String toString() =>
      'SegmentConditionForecast(seg=${segment.index}, '
      'hazard=${hazard.name}, eta=${etaSeconds.toStringAsFixed(0)}s, '
      'conf=${confidence.toStringAsFixed(2)})';
}
