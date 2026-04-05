import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';
import 'segment_condition_forecast.dart';

/// Complete condition forecast for all segments along a route.
///
/// Produced by [RouteConditionForecaster.forecast].
/// Use [hasAnyHazard] for a quick go/no-go check, [firstHazardSegment]
/// for the earliest actionable warning, and [segments] for the full picture.
class RouteForecast extends Equatable {
  final RouteResult route;
  final List<SegmentConditionForecast> segments;
  final DateTime generatedAt;

  const RouteForecast({
    required this.route,
    required this.segments,
    required this.generatedAt,
  });

  /// True if any segment along the route is hazardous.
  bool get hasAnyHazard => segments.any((s) => s.isHazardous);

  /// True if any segment has a fleet hazard zone.
  bool get hasFleetHazard => segments.any((s) => s.hasFleetHazard);

  /// True if any segment has hazardous weather (ignoring fleet data).
  bool get hasWeatherHazard => segments.any((s) => s.hasWeatherHazard);

  /// The first hazardous segment in travel order, or null if route is clear.
  SegmentConditionForecast? get firstHazardSegment =>
      segments.where((s) => s.isHazardous).firstOrNull;

  /// ETA in seconds to the first hazardous segment, or null if route is clear.
  double? get firstHazardEtaSeconds => firstHazardSegment?.etaSeconds;

  /// Count of hazardous segments.
  int get hazardSegmentCount => segments.where((s) => s.isHazardous).length;

  /// Minimum confidence across all segments.
  double get minimumConfidence {
    if (segments.isEmpty) return 1.0;
    return segments.map((s) => s.confidence).reduce(
          (a, b) => a < b ? a : b,
        );
  }

  /// Total route distance in km.
  double get totalDistanceKm => route.totalDistanceKm;

  @override
  List<Object?> get props => [route, segments, generatedAt];

  @override
  String toString() =>
      'RouteForecast(${route.totalDistanceKm.toStringAsFixed(1)}km, '
      '${segments.length} segments, hazard=$hasAnyHazard)';
}
