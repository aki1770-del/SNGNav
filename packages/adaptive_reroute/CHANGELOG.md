# Changelog

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
