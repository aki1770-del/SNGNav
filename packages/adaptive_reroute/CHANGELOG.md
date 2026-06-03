# Changelog

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Refresh cascade-stale dependency constraints

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- `fleet_hazard: ^0.3.0` → `^0.4.0`.
- `routing_engine: ^0.3.0` → `^0.4.0`.
- No source changes; pubspec dep-constraint refresh only.

## 0.1.0 — 2026-04-27

Initial release.

Safety-driven route adaptation for winter driving. Consumes a
`RouteForecast` from `route_condition_forecast`; returns a
`RerouteDecision` (whether to reroute, why, detour waypoints).

Exports:

- `AdaptiveRerouteConfig` — thresholds and limits for reroute decisions
- `DetourWaypoint`, `RerouteDecision` models
- `RerouteEvaluator` service — decides when rerouting is justified
- `DetourPlanner` service — generates hazard-bypassing waypoints

Pure Dart. No Flutter dependency.

Dependencies: `equatable`, `latlong2`, `driving_weather` ^0.3.0,
`fleet_hazard` ^0.3.0, `routing_engine` ^0.3.0,
`route_condition_forecast` ^0.1.0.
