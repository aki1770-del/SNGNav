/// Abstract routing engine — decouples RoutingBloc from OSRM/Valhalla.
///
/// The edge developer swaps engines by providing a different
/// RoutingEngine implementation. The BLoC doesn't change.
///
/// Engine selection strategy:
///   Real-time reroute?     → OSRM (sub-frame latency)
///   Costing = auto?        → OSRM (primary)
///   Costing = multi-modal? → Valhalla (exclusive)
///   Isochrone?             → Valhalla (exclusive)
///   OSRM unavailable?     → Valhalla (fallback)
///   Default                → OSRM
library;

import '../models/route_result.dart';

abstract class RoutingEngine {
  /// Calculate a route for the given request.
  Future<RouteResult> calculateRoute(RouteRequest request);

  /// Check if this engine is ready to serve requests.
  Future<bool> isAvailable();

  /// Engine identity and capabilities.
  EngineInfo get info;

  /// Release resources.
  Future<void> dispose();
}
