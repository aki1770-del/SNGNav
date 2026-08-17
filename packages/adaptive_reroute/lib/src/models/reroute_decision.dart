import 'package:equatable/equatable.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'detour_waypoint.dart';

/// The result of evaluating whether to reroute based on a [RouteForecast].
///
/// Produced by [RerouteEvaluator]. The calling code acts on [shouldReroute]
/// and, if true, uses [detourWaypoints] to build an alternative route with
/// the routing engine of choice.
///
/// This package decides; it never routes. The caller routes.
class RerouteDecision extends Equatable {
  /// Whether the evaluator recommends rerouting.
  final bool shouldReroute;

  /// Human-readable explanation for logging or driver UI.
  final String reason;

  /// The hazardous segment that triggered the recommendation, if any.
  final SegmentConditionForecast? triggerSegment;

  /// Detour waypoints to feed to a routing engine if [shouldReroute] is true.
  /// Empty when [shouldReroute] is false.
  final List<DetourWaypoint> detourWaypoints;

  /// Confidence of this decision [0, 1].
  /// Inherits from the forecast confidence of [triggerSegment].
  final double confidence;

  const RerouteDecision({
    required this.shouldReroute,
    required this.reason,
    required this.confidence,
    this.triggerSegment,
    this.detourWaypoints = const [],
  });

  /// Convenience factory: no reroute needed.
  const RerouteDecision.clear()
      : shouldReroute = false,
        reason = 'Route is clear',
        triggerSegment = null,
        detourWaypoints = const [],
        confidence = 1.0;

  @override
  List<Object?> get props =>
      [shouldReroute, reason, triggerSegment, detourWaypoints, confidence];

  @override
  String toString() =>
      'RerouteDecision(reroute=$shouldReroute, '
      'conf=${confidence.toStringAsFixed(2)}, reason="$reason")';
}
