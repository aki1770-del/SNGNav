# Changelog

## 0.1.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.2 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.1 — 2026-05-10 — Refresh cascade-stale dependency constraints

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- `fleet_hazard: ^0.3.0` → `^0.4.0`.
- `routing_engine: ^0.3.0` → `^0.4.0`.
- No source changes; pubspec dep-constraint refresh only.

## 0.1.0 — 2026-04-27

Initial release.

Per-segment weather and hazard forecasting along a planned route.
Projects current `driving_weather` conditions and `fleet_hazard` zones
onto route segments with time-of-arrival weighting.

Exports:

- `RouteForecast`, `RouteSegment`, `SegmentConditionForecast` models
- `ForecastProvider` interface + `CurrentConditionsForecastProvider`
  (uses current weather as best estimate when no time-series source
  is available)
- `RouteConditionForecaster` service
- `RouteSegmenter` service

Pure Dart. No Flutter dependency.
