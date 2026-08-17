import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import '../models/adaptive_reroute_config.dart';
import '../models/reroute_decision.dart';
import 'detour_planner.dart';

/// Evaluates a [RouteForecast] and decides whether to reroute.
///
/// Evaluation rules (applied in order):
/// 0. If any segment endpoint — or the current position — is (0, 0) or
///    non-finite, the geometry is a placeholder or corrupt and the forecast
///    over it cannot be trusted → [RerouteDecision.cannotAssess]. No detour
///    bearing is computed from such a position, and the route is never
///    reported clear over it.
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
    // Rule 0: refuse to assess placeholder or corrupt geometry. A segment
    // endpoint at (0, 0) or a non-finite coordinate is not a place on the
    // route; bearing math toward it aims detours at (0, 0), and a "clear"
    // verdict over it reports absence of data as certainty of safety.
    final poisoned = forecast.segments
        .where((s) => _isUnusablePoint(s.segment.start) ||
            _isUnusablePoint(s.segment.end))
        .toList();
    if (poisoned.isNotEmpty) {
      final first = poisoned.first;
      final others = poisoned.length - 1;
      return RerouteDecision.cannotAssess(
        reason: 'Segment ${first.segment.index} has an unusable position '
            '((0, 0) placeholder or non-finite coordinate'
            '${others > 0 ? '; $others more segment${others > 1 ? 's' : ''} affected' : ''}) '
            '— the route could not be assessed',
        triggerSegment: first,
      );
    }

    if (_isUnusablePoint(currentPosition)) {
      return const RerouteDecision.cannotAssess(
        reason: 'Current position is unusable ((0, 0) placeholder or '
            'non-finite coordinate) — the approach bearing cannot be '
            'computed and the route could not be assessed',
      );
    }

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

  /// True when [p] cannot be trusted as a real position: exact (0, 0)
  /// (the null-position placeholder) or any non-finite coordinate.
  static bool _isUnusablePoint(LatLng p) =>
      !p.latitude.isFinite ||
      !p.longitude.isFinite ||
      (p.latitude == 0.0 && p.longitude == 0.0);

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
