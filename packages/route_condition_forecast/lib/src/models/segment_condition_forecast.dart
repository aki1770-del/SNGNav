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

  /// True if weather is hazardous OR a fleet hazard zone intersects this segment.
  bool get isHazardous => condition.isHazardous || hazardZones.isNotEmpty;

  /// True if at least one fleet hazard zone overlaps this segment.
  bool get hasFleetHazard => hazardZones.isNotEmpty;

  /// True if weather alone (ignoring fleet data) classifies this segment as risky.
  bool get hasWeatherHazard => condition.isHazardous;

  /// Highest fleet hazard severity present, or null if no fleet hazards.
  HazardSeverity? get worstFleetSeverity {
    if (hazardZones.isEmpty) return null;
    return hazardZones.any((z) => z.severity == HazardSeverity.icy)
        ? HazardSeverity.icy
        : HazardSeverity.snowy;
  }

  @override
  List<Object?> get props =>
      [segment, condition, hazardZones, etaSeconds, confidence];

  @override
  String toString() =>
      'SegmentConditionForecast(seg=${segment.index}, '
      'hazardous=$isHazardous, eta=${etaSeconds.toStringAsFixed(0)}s, '
      'conf=${confidence.toStringAsFixed(2)})';
}
