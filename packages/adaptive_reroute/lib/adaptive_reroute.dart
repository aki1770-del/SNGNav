/// Safety-driven route adaptation for winter driving.
///
/// Evaluates [RouteForecast] data from `route_condition_forecast`,
/// decides when rerouting is justified, and generates detour waypoints
/// to bypass hazard zones. Pure Dart, no Flutter dependency.
///
/// Quick start:
/// ```dart
/// final evaluator = RerouteEvaluator();
/// final decision = evaluator.evaluate(
///   routeForecast,
///   currentPosition: currentLatLng,
/// );
/// if (decision.shouldReroute) {
///   // Pass decision.detourWaypoints to your RoutingEngine
///   print(decision.reason);
/// }
/// ```
library;

export 'src/models/adaptive_reroute_config.dart';
export 'src/models/detour_waypoint.dart';
export 'src/models/reroute_decision.dart';
export 'src/services/detour_planner.dart';
export 'src/services/reroute_evaluator.dart';
