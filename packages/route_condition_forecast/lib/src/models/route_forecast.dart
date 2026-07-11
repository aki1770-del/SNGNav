import 'package:driving_weather/driving_weather.dart';
import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';
import 'segment_condition_forecast.dart';

/// Complete condition forecast for all segments along a route.
///
/// Produced by [RouteConditionForecaster.forecast].
/// Use [hazard] for a go/no-go check — it is TRI-STATE, and
/// [SafetyVerdict.unknown] must not be read as "clear" — [firstHazardSegment]
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

  /// Is this route hazardous? **Tri-state — see [SafetyVerdict].**
  ///
  /// Up to 0.1.5 this was `bool get hasAnyHazard`, and a route every one of
  /// whose segments carried unmeasured weather answered **`false`** — i.e. it
  /// declared itself CLEAR. That answer then flowed into `adaptive_reroute`,
  /// which reported "Route is clear" with `confidence: 1.0`. A route nobody had
  /// looked at was presented to the driver as verified safe.
  ///
  /// The resolution order is the contract's asymmetry:
  /// * ANY hazardous segment ⇒ [SafetyVerdict.hazardous] (positive evidence
  ///   fires even if the rest of the route is unknown);
  /// * else ANY unknown segment ⇒ [SafetyVerdict.unknown] (a route is only as
  ///   assessed as its least-assessed segment — one unmeasured stretch is
  ///   enough to make "the route is clear" a claim we cannot support);
  /// * else [SafetyVerdict.notHazardous].
  ///
  /// An EMPTY forecast is [SafetyVerdict.unknown], not clear. Forecasting
  /// nothing is not the same as forecasting good news.
  SafetyVerdict get hazard {
    if (segments.isEmpty) return SafetyVerdict.unknown;
    if (segments.any((s) => s.hazard == SafetyVerdict.hazardous)) {
      return SafetyVerdict.hazardous;
    }
    if (!coversWholeRoute) return SafetyVerdict.unknown;
    if (segments.any((s) => s.hazard == SafetyVerdict.unknown)) {
      return SafetyVerdict.unknown;
    }
    return SafetyVerdict.notHazardous;
  }

  /// True if any segment has a fleet hazard zone.
  bool get hasFleetHazard => segments.any((s) => s.hasFleetHazard);

  /// The weather-only verdict for the route (ignoring fleet data). Tri-state.
  ///
  /// Carries the SAME coverage guard as [hazard]: a forecast that did not cover
  /// the whole route cannot support a `notHazardous` answer, whatever the
  /// segments it did cover happened to say. Without the guard, an integrator
  /// reading `weatherHazard` got `notHazardous` for the very route on which
  /// `hazard` — on the same object, one line up — correctly said `unknown`.
  SafetyVerdict get weatherHazard {
    if (segments.isEmpty) return SafetyVerdict.unknown;
    if (segments.any((s) => s.weatherHazard == SafetyVerdict.hazardous)) {
      return SafetyVerdict.hazardous;
    }
    if (!coversWholeRoute) return SafetyVerdict.unknown;
    if (segments.any((s) => s.weatherHazard == SafetyVerdict.unknown)) {
      return SafetyVerdict.unknown;
    }
    return SafetyVerdict.notHazardous;
  }

  /// The first hazardous segment in travel order, or `null` if none is
  /// KNOWN-hazardous.
  ///
  /// `null` here does NOT mean the route is clear — it means no segment carried
  /// positive evidence of a hazard. Check [hazard] and [firstUnassessedSegment]
  /// before telling a driver anything reassuring.
  SegmentConditionForecast? get firstHazardSegment => segments
      .where((s) => s.hazard == SafetyVerdict.hazardous)
      .firstOrNull;

  /// ETA in seconds to the first known-hazardous segment, or `null` if none.
  double? get firstHazardEtaSeconds => firstHazardSegment?.etaSeconds;

  /// The first segment whose conditions could not be assessed, or `null`.
  SegmentConditionForecast? get firstUnassessedSegment =>
      segments.where((s) => s.isUnassessed).firstOrNull;

  /// Count of known-hazardous segments.
  int get hazardSegmentCount =>
      segments.where((s) => s.hazard == SafetyVerdict.hazardous).length;

  /// Count of segments whose conditions could not be assessed.
  int get unassessedSegmentCount =>
      segments.where((s) => s.isUnassessed).length;

  /// Maneuvers on [route] that carried no position and so could not be
  /// forecast at all (see `RouteSegmenter.byManeuver`).
  ///
  /// These are not merely unknown — they are stretches this forecast never
  /// looked at. A short forecast reads exactly like a clear one unless it says
  /// so; this is how it says so.
  int get unlocatableManeuverCount =>
      route.maneuvers.where((m) => m.position == null).length;

  /// True when every maneuver on the route could be located and therefore
  /// forecast. When false, this forecast does not cover the whole route.
  bool get coversWholeRoute => unlocatableManeuverCount == 0;

  /// Minimum confidence across all segments, or `null` when there are no
  /// segments.
  ///
  /// Up to 0.1.5 this returned **1.0** for an empty forecast: total certainty,
  /// derived from nothing. That is the same defect class as a fabricated
  /// temperature — an unearned confident number. A forecast with no segments has
  /// no confidence, so it now says `null`.
  double? get minimumConfidence {
    if (segments.isEmpty) return null;
    return segments.map((s) => s.confidence).reduce((a, b) => a < b ? a : b);
  }

  /// Total route distance in km.
  double get totalDistanceKm => route.totalDistanceKm;

  @override
  List<Object?> get props => [route, segments, generatedAt];

  @override
  String toString() =>
      'RouteForecast(${route.totalDistanceKm.toStringAsFixed(1)}km, '
      '${segments.length} segments, hazard=${hazard.name})';
}
