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
- **`DetourPlanner`** — generates waypoints that bypass identified
  hazard zones; respects detour-distance limits and routing-engine
  constraints.
- **`RerouteDecision`** — typed result with `shouldReroute`, human-readable
  `reason`, and `detourWaypoints` ready to hand back to a routing engine.
- **`AdaptiveRerouteConfig`** — knobs for hazard thresholds, max detour
  distance, and minimum-progress-before-reroute logic (avoids rerouting
  thrashing when the driver has just started).

## Install

```yaml
dependencies:
  adaptive_reroute: ^0.1.0
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
