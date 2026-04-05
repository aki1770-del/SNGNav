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
        maneuvers: maneuvers
            .map((m) => NavigationManeuver(
                  index: m.index,
                  instruction: m.instruction,
                  type: m.type,
                  lengthKm: m.lengthKm,
                  timeSeconds: m.timeSeconds,
                  position: m.position,
                ))
            .toList(),
        totalDistanceKm: totalDistanceKm,
        totalTimeSeconds: totalTimeSeconds,
        summary: summary,
      );
}
