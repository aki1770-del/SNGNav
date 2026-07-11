# Changelog

## 0.2.0

### Safety defect in 0.1.5 and earlier — please read

**Up to and including 0.1.5, a route whose weather was never measured reported
itself as CLEAR.**

`RouteForecast.hasAnyHazard` and `SegmentConditionForecast.isHazardous` were
`bool`. A `bool` cannot say "I do not know", so it resolved absence to `false` —
and for a hazard question, `false` is the "clear road" branch. Concretely:

- `driving_weather` up to 0.4.4 could hand us a `WeatherCondition` full of
  fabricated values (`+5.0 °C`, visibility `10000 m`, `iceRisk: false`) whenever
  a feed came back empty;
- every segment carrying it answered `isHazardous == false`;
- `hasAnyHazard` therefore answered `false` — **the route is clear**;
- and `adaptive_reroute` turned that into `RerouteDecision.clear()` with
  `confidence: 1.0`.

A route nobody had looked at was presented to the driver as verified safe, with
total certainty. An **empty** forecast (zero segments) also answered
`hasAnyHazard == false`, and `minimumConfidence` returned **1.0** — perfect
confidence, derived from nothing.

pub.dev versions are immutable. This note is the recall.

### Breaking: hazard verdicts are tri-state

- `SegmentConditionForecast.isHazardous` (`bool`) → **`hazard`
  (`SafetyVerdict`)**.
- `SegmentConditionForecast.hasWeatherHazard` (`bool`) → **`weatherHazard`
  (`SafetyVerdict`)**.
- `RouteForecast.hasAnyHazard` (`bool`) → **`hazard` (`SafetyVerdict`)**.
- `RouteForecast.hasWeatherHazard` (`bool`) → **`weatherHazard`
  (`SafetyVerdict`)**.
- `RouteForecast.minimumConfidence` (`double`) → **`double?`** (`null` for an
  empty forecast; it used to return a fabricated `1.0`).

`if (forecast.hasAnyHazard)` no longer compiles. You must now handle
`SafetyVerdict.unknown` explicitly, and Dart's exhaustive `switch` will refuse
code that does not. **Do not write `== SafetyVerdict.hazardous ? warn() :
allClear()`** — that puts `unknown` back in the all-clear branch, which is the
defect.

Resolution order (the contract's asymmetry):

- ANY hazardous segment ⇒ `hazardous` — positive evidence fires even when the
  rest of the route is unknown;
- else incomplete coverage or ANY unknown segment ⇒ `unknown` — a route is only
  as assessed as its least-assessed segment;
- else `notHazardous`.

An **empty** forecast is `unknown`, not clear. Forecasting nothing is not the
same as forecasting good news.

### New: the forecast admits where it could not look

- `SegmentConditionForecast.isUnassessed`
- `RouteForecast.firstUnassessedSegment`, `unassessedSegmentCount`
- `RouteForecast.unlocatableManeuverCount`, `coversWholeRoute`

`routing_engine` 0.6.0 makes `RouteManeuver.position` nullable (`null` = the
engine returned no usable coordinate; up to 0.5.0 it silently substituted
`const LatLng(0, 0)` — Null Island, a real place in the Gulf of Guinea).
`RouteSegmenter.byManeuver` now **skips** a maneuver with no position rather
than anchoring a segment to a fabricated coordinate — which would have queried
the weather in the Atlantic and attributed the answer to a road in Akita.

Skipping is itself an absence, so it is reported, not hidden: a route with any
unlocatable maneuver has `coversWholeRoute == false` and its `hazard` is
`unknown` even if every segment we *could* forecast came back benign. A silently
short forecast reads exactly like a clear one.

### Migration

| 0.1.5 | 0.2.0 | On `unknown` |
| --- | --- | --- |
| `forecast.hasAnyHazard` (`bool`) | `forecast.hazard` (`SafetyVerdict`) | Tell the driver the route could not be assessed. Do not proceed as if clear. |
| `segment.isHazardous` (`bool`) | `segment.hazard` (`SafetyVerdict`) | — |
| `segment.hasWeatherHazard` | `segment.weatherHazard` | — |
| `forecast.minimumConfidence` (`double`) | `double?` | `null` = no segments; there is no confidence to report. |

`firstHazardSegment == null` does **not** mean the route is clear — it means no
segment carried positive evidence of a hazard. Check `hazard` and
`firstUnassessedSegment` before saying anything reassuring.

### Also

- Requires `driving_weather: ^0.5.0` and `routing_engine: >=0.6.0 <0.7.0`.
- One pre-existing test **certified the defect** and has been inverted: it
  asserted that an empty forecast reports `hasAnyHazard == false`. It now asserts
  `hazard == SafetyVerdict.unknown`.
- Behaviour on fully measured, fully located routes is unchanged.

## 0.1.5

- Widen the `routing_engine` constraint to `>=0.4.0 <0.6.0` so consumers can
  take `routing_engine` 0.5.0 (language-honoring turn-by-turn narration)
  alongside `route_condition_forecast` — this pin was the last CATALOG link
  blocking the Android reach vehicle (`sngnav-app`) from resolving the
  Japanese narration. Reach itself is still OPEN at this publish: the app
  must additionally widen its own `routing_engine` pin and take
  `voice_guidance` ^0.7.x, and the narration must be verified ON DEVICE
  before any reach claim (publish ≠ reach). No library code change (lib/
  is byte-identical to 0.1.4). Consumers who prefer English instructions
  with default requests can pin `routing_engine: ^0.4.0` or pass
  `language: 'en'` (see routing_engine 0.5.0's changelog).


## 0.1.4

- deps: require `fleet_hazard: ^0.5.0` (the anonymized aggregate — `HazardZone`
  no longer retains a re-identifiable per-vehicle trail). No API change here;
  this package reads only zone center/severity/vehicleCount/confidence, all
  preserved. Tests updated to the `ZoneObservation` element type.

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
