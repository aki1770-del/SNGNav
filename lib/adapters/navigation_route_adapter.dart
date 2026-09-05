/// Routing → Navigation boundary adapter.
///
/// This is the **only** place in the codebase where `RouteResult` is converted
/// to `NavigationRoute`. All call sites that dispatch `NavigationStarted` or
/// `RerouteCompleted` must go through this extension rather than passing
/// `RouteResult` directly into navigation events.
///
/// Internal use only — do not export from any package public barrel.
library;

import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';

extension RouteResultNavigationAdapter on RouteResult {
  NavigationRoute toNavigationRoute() => NavigationRoute(
        shape: shape,
        // routing_engine 0.6.0: `RouteManeuver.position` is nullable. A maneuver
        // whose location could not be parsed is NOT at `LatLng(0, 0)` — Null
        // Island, in the Gulf of Guinea, which is where the old sentinel would
        // have narrated and centred her map. `NavigationManeuver.position` is
        // non-nullable, so a positionless maneuver cannot enter this type at
        // all: it is omitted rather than given a fabricated coordinate.
        maneuvers: maneuvers
            .where((m) => m.position != null)
            .map((m) => NavigationManeuver(
                  index: m.index,
                  instruction: m.instruction,
                  type: m.type,
                  lengthKm: m.lengthKm,
                  timeSeconds: m.timeSeconds,
                  position: m.position!,
                ))
            .toList(),
        totalDistanceKm: totalDistanceKm,
        totalTimeSeconds: totalTimeSeconds,
        summary: summary,
      );
}
