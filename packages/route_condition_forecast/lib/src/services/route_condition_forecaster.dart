import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:routing_engine/routing_engine.dart';
import '../models/route_forecast.dart';
import '../models/route_segment.dart';
import '../models/segment_condition_forecast.dart';
import '../providers/forecast_provider.dart';
import 'route_segmenter.dart';

/// Projects weather and fleet hazard conditions onto the segments of a route.
///
/// For each segment, [forecast] computes:
/// - the ETA (seconds from departure, given constant [speedKmh])
/// - a weather forecast for the segment's midpoint at that ETA
/// - which [HazardZone]s geometrically overlap the segment
/// - a confidence score that degrades with forecast horizon
///
/// Usage:
/// ```dart
/// final forecaster = RouteConditionForecaster(
///   forecastProvider: CurrentConditionsForecastProvider(currentWeather),
///   hazardZones: aggregatedZones,
///   speedKmh: 60.0,
/// );
/// final forecast = await forecaster.forecast(routeResult);
/// if (forecast.hasAnyHazard) { ... }
/// ```
class RouteConditionForecaster {
  const RouteConditionForecaster({
    required ForecastProvider forecastProvider,
    this.hazardZones = const [],
    this.speedKmh = 60.0,
    this.segmentationStrategy = SegmentationStrategy.byManeuver,
    this.distanceSegmentKm = 5.0,
  }) : _forecastProvider = forecastProvider;

  final ForecastProvider _forecastProvider;

  /// Fleet hazard zones to test against each segment's geometry.
  final List<HazardZone> hazardZones;

  /// Assumed vehicle speed for ETA computation (km/h). Default 60.
  final double speedKmh;

  final SegmentationStrategy segmentationStrategy;

  /// Maximum segment length when using [SegmentationStrategy.byDistance].
  final double distanceSegmentKm;

  /// Produces a [RouteForecast] for [route].
  ///
  /// Segments are evaluated in travel order. Each segment's ETA is the
  /// cumulative travel time from departure at [speedKmh].
  Future<RouteForecast> forecast(RouteResult route) async {
    final segments = _segment(route);

    if (segments.isEmpty) {
      return RouteForecast(
        route: route,
        segments: const [],
        generatedAt: DateTime.now().toUtc(),
      );
    }

    double elapsedSeconds = 0.0;
    final forecasted = <SegmentConditionForecast>[];

    for (final segment in segments) {
      final etaSeconds = elapsedSeconds;

      final condition = await _forecastProvider.forecastAt(
        segment.midpoint,
        etaSeconds: etaSeconds,
      );

      final intersecting = _intersectingZones(segment);

      forecasted.add(SegmentConditionForecast(
        segment: segment,
        condition: condition,
        hazardZones: intersecting,
        etaSeconds: etaSeconds,
        confidence: _confidence(etaSeconds),
      ));

      // Advance elapsed time by this segment's travel time.
      final travelTime = speedKmh > 0
          ? (segment.distanceKm / speedKmh) * 3600.0
          : 0.0;
      elapsedSeconds += travelTime;
    }

    return RouteForecast(
      route: route,
      segments: forecasted,
      generatedAt: DateTime.now().toUtc(),
    );
  }

  List<RouteSegment> _segment(RouteResult route) {
    return switch (segmentationStrategy) {
      SegmentationStrategy.byManeuver => RouteSegmenter.byManeuver(route),
      SegmentationStrategy.byDistance =>
        RouteSegmenter.byDistance(route, maxKm: distanceSegmentKm),
    };
  }

  List<HazardZone> _intersectingZones(RouteSegment segment) {
    if (hazardZones.isEmpty) return const [];
    return hazardZones
        .where((zone) => _segmentIntersectsZone(segment, zone))
        .toList();
  }

  bool _segmentIntersectsZone(RouteSegment segment, HazardZone zone) {
    final dist = const Distance();
    return dist.distance(segment.start, zone.center) <= zone.radiusMeters ||
        dist.distance(segment.midpoint, zone.center) <= zone.radiusMeters ||
        dist.distance(segment.end, zone.center) <= zone.radiusMeters;
  }

  /// Confidence degrades linearly with forecast horizon.
  /// 1.0 at t=0h; 0.5 at t=8h; floor of 0.1.
  static double _confidence(double etaSeconds) {
    const halfLife = 8 * 3600.0; // 8 hours
    return math.max(0.1, 1.0 - (etaSeconds / halfLife) * 0.5);
  }
}

enum SegmentationStrategy { byManeuver, byDistance }
