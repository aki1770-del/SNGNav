# adaptive_reroute

[![pub package](https://img.shields.io/pub/v/adaptive_reroute.svg)](https://pub.dev/packages/adaptive_reroute)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Safety-driven route adaptation for winter driving.**

The driver is on a planned route. Conditions ahead change — a hazard
appears, weather worsens, the road two segments forward becomes risky.
Should you reroute? When? Around what?

`adaptive_reroute` answers those questions. It consumes a
[`RouteForecast`](https://pub.dev/packages/route_condition_forecast) and
returns a `RerouteDecision` — whether to reroute, why, and (if yes)
the detour waypoints to feed back to your routing engine.

Pure Dart. No Flutter.

## What it gives you

- **`RerouteEvaluator`** — decides when rerouting is justified given
  forecast hazards, current position, and configured thresholds.
- **`DetourPlanner`** — generates left/right waypoint pairs that bypass
  identified hazard zones, each offset by the zone radius plus a configured
  lateral offset. It produces candidate waypoints only; honouring
  detour-distance limits and routing-engine constraints is the calling
  routing engine's responsibility.
- **`RerouteDecision`** — typed result with `shouldReroute`, human-readable
  `reason`, `detourWaypoints` ready to hand back to a routing engine, and
  `confidence` (`double?`). It reports **one of three** facts: *reroute*,
  *no hazard found on the assessed route*, or ***could not assess the route***
  (`isAssessed == false`, `confidence == null`).
  **`shouldReroute == false` does not mean the route is safe** — it is also what
  you get when the conditions were unknown. Read `isAssessed` first. (Before
  0.2.0 there were only two outcomes and an unknown route was reported as
  *"Route is clear"* at `confidence = 1.0`; see CHANGELOG.)
- **`AdaptiveRerouteConfig`** — knobs for the hazard look-ahead window
  (`hazardWindowSeconds`), the minimum forecast confidence to act
  (`minConfidenceToAct`), and the detour waypoint offset distance
  (`detourOffsetMeters`).

## Not yet implemented

Documented as carry-forward gaps so the public API is honest about what
currently ships:

- **`AdaptiveRerouteConfig.maxDetourFraction`** is declared but **not yet
  enforced** — no code path rejects a detour for exceeding it. Treat it as
  advisory and enforce detour-distance limits in your own routing engine
  until a future version wires it into evaluation.
- **Minimum-progress / anti-thrashing logic** (suppressing rapid
  re-reroute prompts so the driver is not alarmed repeatedly) is **not
  implemented**. `RerouteEvaluator` evaluates each forecast independently;
  debounce reroute prompts in your integration if you need this.

## Install

```yaml
dependencies:
  adaptive_reroute: ^0.2.0
```

You'll also need
[`route_condition_forecast`](https://pub.dev/packages/route_condition_forecast)
to produce the input forecasts.

## Use

```dart
import 'package:adaptive_reroute/adaptive_reroute.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';

final evaluator = RerouteEvaluator();
final planner = DetourPlanner();

// You produced this from RouteConditionForecaster:
final RouteForecast forecast = ...;

final decision = evaluator.evaluate(
  forecast,
  currentPosition: currentLatLng,
);

// FIRST: did we actually have conditions to judge? `shouldReroute == false`
// is ALSO what you get when the route could not be assessed at all — do not
// paint that as a clear road.
if (!decision.isAssessed) {
  print('Route conditions unknown: ${decision.reason}');
  // Tell the driver the road ahead could not be assessed. Not an all-clear.
  return;
}

if (decision.shouldReroute) {
  print('Rerouting: ${decision.reason}');
  // Hand decision.detourWaypoints to your RoutingEngine to compute
  // the new route around the hazard zone.
  final newRoute = await routingEngine.calculateRoute(
    RouteRequest(
      origin: currentLatLng,
      destination: originalDestination,
      waypoints: decision.detourWaypoints,
    ),
  );
} else {
  // Assessed, and nothing found. `confidence` is inherited from the forecast
  // (the weakest segment along the route) — never a manufactured 1.0.
  print('No hazard found (confidence ${decision.confidence!}).');
}
```

## When to use this

When you've already shipped a navigation flow that consumes a forecast
and you need a typed, tested decision layer for "do we reroute now,
and if so around what?" — instead of re-rolling the threshold + waypoint
logic per project.

If you don't yet have a forecast, depend on
[`route_condition_forecast`](https://pub.dev/packages/route_condition_forecast)
first; it produces the `RouteForecast` this package consumes.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
