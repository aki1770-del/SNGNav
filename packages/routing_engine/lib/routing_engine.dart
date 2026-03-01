/// Engine-agnostic routing interface with OSRM and Valhalla implementations.
///
/// Provides an abstract [RoutingEngine] interface that decouples routing
/// consumers from specific engine implementations. Includes two concrete
/// engines:
/// - [OsrmRoutingEngine]: Sub-frame latency, optimised for real-time rerouting
/// - [ValhallaRoutingEngine]: Multi-modal routing, isochrones, Japanese support
///
/// ```dart
/// import 'package:routing_engine/routing_engine.dart';
///
/// final engine = OsrmRoutingEngine(
///   baseUrl: 'https://router.project-osrm.org',
/// );
///
/// final route = await engine.calculateRoute(RouteRequest(
///   origin: LatLng(35.17, 136.88),
///   destination: LatLng(34.97, 137.17),
/// ));
///
/// print('${route.totalDistanceKm} km, ${route.maneuvers.length} steps');
/// ```
library;

export 'src/exceptions.dart';
export 'src/osrm_routing_engine.dart';
export 'src/route_result.dart';
export 'src/routing_engine.dart';
export 'src/valhalla_routing_engine.dart';
