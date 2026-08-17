import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import '../models/adaptive_reroute_config.dart';
import '../models/reroute_decision.dart';
import 'detour_planner.dart';

/// Evaluates a [RouteForecast] and decides whether to reroute.
///
/// Evaluation rules (applied in order):
/// 1. If the forecast has no hazards → [RerouteDecision.clear].
/// 2. If the first hazard ETA exceeds [AdaptiveRerouteConfig.hazardWindowSeconds]
///    → hazard is beyond the look-ahead window; flag but do not reroute yet.
/// 3. If the trigger segment's confidence is below
///    [AdaptiveRerouteConfig.minConfidenceToAct] → signal is uncertain; wait.
/// 4. Otherwise → reroute recommended with detour waypoints.
///
/// The caller acts on [RerouteDecision.shouldReroute] and routes via its
/// chosen [RoutingEngine] using [RerouteDecision.detourWaypoints].
class RerouteEvaluator {
  const RerouteEvaluator({
    this.config = const AdaptiveRerouteConfig(),
    DetourPlanner? detourPlanner,
  }) : _detourPlanner = detourPlanner ?? const DetourPlanner();

  final AdaptiveRerouteConfig config;
  final DetourPlanner _detourPlanner;

  /// Evaluates [forecast] and returns a [RerouteDecision].
  ///
  /// [currentPosition] is used to compute the approach bearing toward hazards
  /// for detour waypoint generation.
  RerouteDecision evaluate(
    RouteForecast forecast, {
    required LatLng currentPosition,
  }) {
    if (!forecast.hasAnyHazard) {
      return const RerouteDecision.clear();
    }

    final trigger = forecast.firstHazardSegment!;

    if (trigger.etaSeconds > config.hazardWindowSeconds) {
      return RerouteDecision(
        shouldReroute: false,
        reason: 'Hazard at ${(trigger.etaSeconds / 60).toStringAsFixed(0)} min '
            '— outside ${(config.hazardWindowSeconds / 60).toStringAsFixed(0)} min window',
        triggerSegment: trigger,
        confidence: trigger.confidence,
      );
    }

    if (trigger.confidence < config.minConfidenceToAct) {
      return RerouteDecision(
        shouldReroute: false,
        reason: 'Hazard detected but forecast confidence '
            '${trigger.confidence.toStringAsFixed(2)} < '
            'threshold ${config.minConfidenceToAct}',
        triggerSegment: trigger,
        confidence: trigger.confidence,
      );
    }

    final approachBearing = _bearing(currentPosition, trigger.segment.start);
    final waypoints = _detourPlanner.plan(
      trigger.hazardZones,
      approachBearing: approachBearing,
    );

    return RerouteDecision(
      shouldReroute: true,
      reason: _reason(trigger),
      triggerSegment: trigger,
      detourWaypoints: waypoints,
      confidence: trigger.confidence,
    );
  }

  String _reason(SegmentConditionForecast trigger) {
    final etaMin = (trigger.etaSeconds / 60).toStringAsFixed(0);
    if (trigger.hasFleetHazard) {
      final sev = trigger.worstFleetSeverity!.name;
      return 'Fleet hazard ($sev) at segment ${trigger.segment.index} in $etaMin min';
    }
    if (trigger.condition.iceRisk) {
      return 'Ice risk at segment ${trigger.segment.index} in $etaMin min';
    }
    return 'Hazardous weather at segment ${trigger.segment.index} in $etaMin min';
  }

  /// Bearing from [from] to [to] in degrees (0–360, clockwise from north).
  static double _bearing(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final x = math.sin(dLng) * math.cos(lat2);
    final y = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(x, y) * 180 / math.pi + 360) % 360;
  }
}
