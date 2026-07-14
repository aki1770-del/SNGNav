# route_condition_forecast

[![pub package](https://img.shields.io/pub/v/route_condition_forecast.svg)](https://pub.dev/packages/route_condition_forecast)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Per-segment weather and hazard forecasting along a planned route.**

You have a route. The driver will reach segment N at time T. What weather
and hazards will be there when she arrives — not now, not at the start,
but at her actual time-of-arrival per segment?

`route_condition_forecast` projects current
[`driving_weather`](https://pub.dev/packages/driving_weather) conditions
and [`fleet_hazard`](https://pub.dev/packages/fleet_hazard) zones onto
route segments using time-of-arrival weighting. The result is a
`RouteForecast` answering "what will conditions be when she gets there?"
segment by segment.

Pure Dart. No Flutter.

> **0.2.0 fixes a safety defect present through 0.1.5.** A route whose segments
> carried unmeasured weather answered `hasAnyHazard == false` — i.e. it declared
> itself CLEAR — and that answer flowed into `adaptive_reroute`, which reported
> "Route is clear" with `confidence: 1.0`. Verdicts are now tri-state and the
> bool accessor is gone; `if (forecast.hasAnyHazard)` will not compile. Read the
> [CHANGELOG](CHANGELOG.md) before upgrading — the compile error is the fix.

## What it gives you

- **`RouteSegmenter`** — splits a route into time-aware segments.
- **`RouteConditionForecaster`** — projects forecast conditions onto
  segments with ETA weighting; flags hazard intersections.
- **`RouteForecast`** — typed result with per-segment condition snapshots,
  hazard intersections, and a **tri-state** `SafetyVerdict get hazard`
  (`hazardous` / `notHazardous` / **`unknown`**), plus
  `firstHazardEtaSeconds`, `firstUnassessedSegment`, `coversWholeRoute`.
- **`ForecastProvider`** — pluggable; ships with
  `CurrentConditionsForecastProvider` (uses current weather as best estimate)
  for cases where no time-series forecast source is available.

## Install

```yaml
dependencies:
  route_condition_forecast: ^0.2.0
```

## Use

```dart
// oracle:placeholders currentWeather, myHazardZones, routeResult
import 'package:route_condition_forecast/route_condition_forecast.dart';

final forecaster = RouteConditionForecaster(
  forecastProvider: CurrentConditionsForecastProvider(currentWeather),
  hazardZones: myHazardZones,
);

final forecast = await forecaster.forecast(routeResult);

// TRI-STATE. `unknown` is not "clear": it means the route could not be
// assessed (an unmeasured segment, or a maneuver that carried no position and
// so was never forecast at all).
//
// Do NOT write `forecast.hazard == SafetyVerdict.hazardous ? warn() : allClear()`
// — that puts `unknown` back in the all-clear branch, which IS the defect.
switch (forecast.hazard) {
  case SafetyVerdict.hazardous:
    print('Hazard at ${forecast.firstHazardEtaSeconds} seconds in.');
  case SafetyVerdict.unknown:
    print('Route conditions unknown — the route could not be assessed.');
  case SafetyVerdict.notHazardous:
    print('Route assessed, no hazard found.');
}

for (final segment in forecast.segments) {
  print('Seg ${segment.index}: ${segment.condition.summary} '
        '(arrival in ${segment.etaSeconds}s)');
}
```

## When to use this

When you have a planned route and need to know what conditions the driver
will encounter as she progresses through it — not just current conditions
at the starting point. Useful for:

- "Snow is coming in 30 minutes; will I be in the worst of it on the
  highway segment or the city segment?"
- "Hazard reported 5 km ahead; will I reach it before or after the road
  warms above freezing?"
- "Pre-trip risk summary: how many segments of the planned route have
  active hazard zones?"

If you only need *current* conditions at a single point, depend on
[`driving_weather`](https://pub.dev/packages/driving_weather) directly.

## License

BSD-3-Clause. See [LICENSE](LICENSE).
