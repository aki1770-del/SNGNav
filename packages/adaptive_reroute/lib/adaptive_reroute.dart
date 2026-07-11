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
///
/// if (!decision.isAssessed) {
///   // The conditions along the route were NOT known. This is not an
///   // all-clear — tell the driver the route could not be assessed.
///   showUnknown(decision.reason);
/// } else if (decision.shouldReroute) {
///   // Pass decision.detourWaypoints to your RoutingEngine
///   showReroute(decision.reason);
/// } else {
///   // Assessed, and nothing found. decision.confidence tells you how strong
///   // that claim is — it is inherited from the forecast, never a flat 1.0.
///   showClear(decision.confidence!);
/// }
/// ```
///
/// **Read [RerouteDecision.isAssessed] first.** `shouldReroute == false` on its
/// own does not mean the route is safe — it is also what this package returns
/// when it could not assess the route at all. See [RerouteDecision].
library;

export 'src/models/adaptive_reroute_config.dart';
export 'src/models/detour_waypoint.dart';
export 'src/models/reroute_decision.dart';
export 'src/services/detour_planner.dart';
export 'src/services/reroute_evaluator.dart';

/// Re-exported from `driving_weather`: [RerouteEvaluator.verdictFor] returns a
/// [SafetyVerdict], so it belongs to this package's public API surface.
export 'package:driving_weather/driving_weather.dart' show SafetyVerdict;
