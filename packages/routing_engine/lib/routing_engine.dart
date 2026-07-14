/// Engine-agnostic routing interface with OSRM and Valhalla implementations.
///
/// Provides an abstract [RoutingEngine] interface that decouples routing
/// consumers from specific engine implementations. Includes two concrete
/// engines:
/// - [OsrmRoutingEngine]: Sub-frame latency, optimised for real-time rerouting;
///   localizes instructions client-side per `RouteRequest.language` (Japanese —
///   the default — natively; unknown locales degrade to the engine's English)
/// - [ValhallaRoutingEngine]: Multi-modal routing, isochrones; localizes
///   server-side by forwarding `RouteRequest.language`
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

// Our public API (RouteRequest, RouteResult, RouteManeuver) takes and returns
// latlong2's LatLng. A package whose API requires a type MUST export that type:
// without this, the very first block of our own README —
//   import 'package:routing_engine/routing_engine.dart';
//   ... origin: LatLng(35.1709, 136.9066)
// — does not compile, and every stranger's first contact with us is an
// `undefined_function`. (Found 2026-07-14 by the L35 snippet oracle.)
export 'package:latlong2/latlong.dart' show LatLng;

export 'src/exceptions.dart';
// NOTE: src/maneuver_localizer.dart is deliberately NOT exported — it is an
// internal product piece (§9: no pub.dev-facing API without edge-developer
// demand evidence; measured 2026-07-04: none). The engine uses it internally.
export 'src/osrm_routing_engine.dart';
export 'src/route_result.dart';
export 'src/routing_engine.dart';
export 'src/valhalla_routing_engine.dart';
