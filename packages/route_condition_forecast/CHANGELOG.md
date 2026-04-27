# Changelog

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
