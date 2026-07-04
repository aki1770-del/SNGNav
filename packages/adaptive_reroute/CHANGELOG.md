# Changelog

## 0.1.5

- Widen the `routing_engine` constraint to `>=0.4.0 <0.6.0` so consumers can
  take `routing_engine` 0.5.0 (language-honoring turn-by-turn narration)
  alongside `adaptive_reroute`. No library code change (lib/ is byte-identical
  to 0.1.4).


## 0.1.4

- deps: require `fleet_hazard: ^0.5.0` (the anonymized aggregate — `HazardZone`
  no longer retains a re-identifiable per-vehicle trail). No API change here;
  this package reads only zone center/severity/vehicleCount/confidence, all
  preserved. Tests updated to the `ZoneObservation` element type.

## 0.1.3

Safety-documentation honesty fix. The docs now describe only what ships;
no source/behavior change.

- **Struck a fabricated SOTIF safety claim.** README and `SAFETY_BOUNDARY.md`
  (§3) described a "minimum-progress-before-reroute / anti-thrashing logic"
  presented as an explicit SOTIF-class mitigation against alarm-fatigue. No
  such field or logic exists in code; `RerouteEvaluator` evaluates each
  forecast independently with no debounce. Removed the claim and recorded
  alarm-fatigue mitigation as a documented carry-forward gap (integrator
  responsibility until implemented).
- **Corrected the "respects detour-distance limits" claim.** README said
  `DetourPlanner` respects detour-distance limits; `AdaptiveRerouteConfig`
  exposed `maxDetourFraction`, documented as the threshold above which a
  candidate route "is rejected." No code path consumes `maxDetourFraction` —
  nothing is rejected. The field is now documented as **declared but not yet
  enforced** (carry-forward gap; enforce in your own routing engine).
- Fixed a stale dartdoc reference to the non-existent `AdaptiveRerouteService`
  (actual class: `RerouteEvaluator`).

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
