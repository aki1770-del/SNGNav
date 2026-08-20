# Changelog

## 0.6.0

### Safety defect in 0.5.4 and earlier — please read

This package **re-exports** `RoadSurfaceState`, `HysteresisFilter` and
`DrivingConditionAssessment` from `snow_rendering`. It therefore carried
`snow_rendering`'s fabrication defect verbatim to its own consumers:

**up to 0.5.4, a road with no weather data classified as `RoadSurfaceState.dry`,
with `gripFactor: 1.0` and the advisory "Conditions normal".** Absence of data
became maximum grip and a green light. See `snow_rendering` 0.3.0 and
`driving_weather` 0.5.0 for the full account.

pub.dev versions are immutable. This note is the recall.

### Second safety defect in 0.5.4 and earlier — fleet SILENCE raised the score

`FleetHazardConfidenceAdapter.confidence` returned **`0.8`** — called a "neutral
baseline" — in three different absence cases:

```dart
// fleet_hazard_confidence_adapter.dart, 0.5.4
static const double _neutralBaseline = 0.8;
if (recent.isEmpty) return _neutralBaseline;      // no recent report at all
if (totalWeight == 0.0) return _neutralBaseline;  // no usable report
RoadCondition.unknown => _neutralBaseline,        // a driver reporting "I don't know"
```

`0.8` is **not neutral**. On the same scale `dry` scores 1.0 and `snowy` 0.4 — so
0.8 is an OPTIMISTIC report from a fleet that reported nothing. And it was not a
display value: it was folded into the overall safety score with weight 0.2

```dart
final overall = gripScore * 0.4 + visibilityScore * 0.4 + fleetConfidenceScore * 0.2;
```

**so silence from the fleet RAISED the computed safety score.** A driver on an
icy road with no fleet data got a *higher* score than the measured terms
justified. The boundary record even certified the default as "honest (0.8
explicit baseline; not hidden)" — the number was explicit; what it MEANT was not.

**0.6.0**: `FleetConfidenceProvider.confidence` is `double?` (`null` = no fleet
data). An explicitly-`unknown` road report carries **no weight** rather than a
grip-like 0.8. And the overall score RE-NORMALISES its weights over the terms
that were actually measured, so an absent term is not folded in at any value —
fleet silence now neither raises nor lowers the score.

`ConstantFleetConfidenceProvider(0.8)` survives as what it always honestly was: a
caller ASSERTING a scenario (a test, a simulator) — the exact counterpart of
`WeatherCondition.simulatedClear()`. To say "no fleet data", use
`ConstantFleetConfidenceProvider.unavailable()`.

### Breaking

- Requires `snow_rendering: ^0.3.0` and `driving_weather: ^0.5.0`.
  The re-exported types changed, so **this package's own public API changed**:
  - `RoadSurfaceState.fromCondition()` now returns `RoadSurfaceState?`
    (`null` = cannot classify; it is never `dry`).
  - `DrivingConditionAssessment.surfaceState` is `RoadSurfaceState?`,
    `gripFactor` is `double?`, `visibility` is `VisibilityDegradation?`,
    `precipitation` is `PrecipitationConfig?`.
  - `RecommendedResponse` gains `conditionsUnknown`, breaking exhaustive
    switches.
  - `DrivingConditionAssessment.recommendedResponse` no longer defaults to
    `proceed`.

  Note that the old `driving_weather: ^0.4.0` constraint could not simply be
  left alone: `snow_rendering` 0.3.0 requires `driving_weather` `^0.5.0`, and
  for a `0.x` package `^0.4.0` does not admit `0.5.0`. Left unbumped, this
  package would have made resolution **impossible** for everyone downstream.

- **`SafetyScoreSimulator.simulate()` still takes a non-nullable
  `double gripFactor` and a non-nullable `RoadSurfaceState surface`** — so an
  unknown road can no longer be scored at all, and the compiler will stop you at
  the call site. This is deliberate. A Monte Carlo safety score computed on a
  fabricated grip of 1.0 is worse than no score: it is a confident number about
  a road nobody looked at. Guard, and tell the driver the road is unassessed:

  ```dart
  final surface = assessment.surfaceState;
  final grip = assessment.gripFactor;
  if (surface == null || grip == null) {
    // Do NOT write `?? RoadSurfaceState.dry` or `?? 1.0` — that is the defect.
    show(assessment.advisoryMessage); // "Conditions unavailable — ..."
    return;
  }
  final result = const SafetyScoreSimulator()
      .simulate(speed: 50, gripFactor: grip, surface: surface, /* ... */);
  ```

### Breaking: the simulation score is now `SimulatedSafetyScore`

`SimulationResult.score` and `SafetyScoreSimulator.runOnce` return
**`SimulatedSafetyScore`** (this package) instead of `SafetyScore`
(`navigation_safety_core`).

Why: `SafetyScore.fleetConfidenceScore` is a non-nullable `double`, so it
**cannot say "no fleet reported anything"** — which is exactly how the `0.8`
fabrication got in. `SimulatedSafetyScore.fleetConfidenceScore` is `double?`, and
its `overall` is re-normalised over the measured terms. `toAlertSeverity(config)`
is unchanged and applies the same thresholds to `overall`. `hasFleetData` tells
you which case you are in.

`navigation_safety_core` is **not** bumped: nothing outside this package
constructs or reads that type, and forcing a core release would strand
`nav2_safety_layer`, whose constraint was only just widened. The honest fix is
contained here, where the defect is.

### Fixed: `RecommendedResponse` was never re-exported

Up to 0.5.4 this package re-exported `DrivingConditionAssessment` but **not the
type of its `recommendedResponse` field**. A consumer importing only
`package:driving_conditions` could hold the value but could not name the type,
and so could not `switch` on it.

That was a latent facade gap; 0.6.0 makes it load-bearing, because
`RecommendedResponse.conditionsUnknown` is precisely the tier a consumer must
handle in order not to treat an unassessed road as a clear one. A contract the
consumer cannot name is a contract that does not reach them. Now exported.

### Also

- **`navigation_safety_core` is `>=0.10.0 <0.12.0`, not `^0.10.0`.** The
  published 0.5.5 (2026-07-12) already widened this to admit the 0.11.x line;
  that widening lived only in the published artifact and never came back to this
  repository, so the tree still carried the pre-0.5.5 `^0.10.0`. Shipped as-is,
  0.6.0 would have been the only package in this catalog to *exclude*
  `navigation_safety_core` 0.11.0–0.11.4 — narrower than the 0.5.7 it replaces,
  and narrower than the six siblings (`snow_rendering`, `offline_tiles`,
  `map_viewport_bloc`, `voice_guidance`, `navigation_safety`,
  `nav2_safety_layer`) that all declare `>=0.10.0 <0.12.0`. An upgrade that
  *removes* resolvable versions is a downgrade for the integrator holding both.
  Nothing in 0.11.x required the narrowing: 0.11.0 and 0.11.1 record themselves
  as additive (0.11.0 *adds* re-exports; no existing symbol changed or was
  removed) and 0.11.2, 0.11.3 and 0.11.4 each record "no API changes". Read as
  a claim that needed checking rather than a promise: this package's suite is
  green on both ends of the range — 0.10.5 and 0.11.4 — from a hosted,
  override-free resolution carrying no path dependency.

- Behaviour on **fully measured** data is unchanged — all pre-existing tests
  still pass. The break reaches only the code paths where data was absent, which
  is exactly where the old behaviour was wrong.

## 0.5.4

- deps: allow `fleet_hazard: ^0.4.0` → `^0.5.0` (the anonymized-`HazardZone`
  dignity fix). `driving_conditions` consumes only the `FleetReport` input atom
  and the `RoadCondition` enum via `FleetHazardConfidenceAdapter` — neither
  changed in fleet_hazard 0.5.0 (only the *retained* `HazardZone.reports` type
  was anonymized from `List<FleetReport>` to `List<ZoneObservation>`, which this
  package never reads). Source-compatible; no `lib/` code change. Unblocks
  integrators that pull both packages from pub.dev.

## 0.5.3

- Docs: de-promote the optional native (C FFI) `NativeSafetyScoreSimulationEngine`. The README now states the pure-Dart `CpuSafetyScoreSimulationEngine` is the default, and that the native path requires compiling the C library (`native/build/lib...`) first — it throws (`DynamicLibrary.open` / `UnsupportedError`) otherwise, with no silent fallback. Updated the README install snippet pin to `^0.5.3`. No code change.

## 0.5.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.5.1 — 2026-05-10 — Refresh cascade-stale dependency constraints

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- `fleet_hazard: ^0.3.0` → `^0.4.0`.
- No source changes; pubspec dep-constraint refresh only.

## 0.5.0

- **Dep modernization** (republish cascade): bump `navigation_safety_core: ^0.1.0 → ^0.10.0` (closes 9-version stale dep) + `snow_rendering: ^0.1.0 → ^0.2.0` (closes 1-version stale dep). NSC dep update consumes additive surface only (no breaking changes per NSC CHANGELOG 0.2.0–0.10.0). Closes 2-month publish-debt (pub.dev last at 0.3.0 from 2026-03-15).
- **New**: `FleetConfidenceProvider` abstract interface — pluggable fleet confidence for safety simulation.
- **New**: `ConstantFleetConfidenceProvider` — explicit named replacement for the `0.8` literal.
- **New**: `FleetHazardConfidenceAdapter` — derives confidence from `List<FleetReport>` using road condition safety factors (dry 1.0, wet 0.7, snowy 0.4, icy 0.1).
- `CpuSafetyScoreSimulationEngine`, `NativeSafetyScoreSimulationEngine`, and `SafetyScoreSimulator` now accept an optional `FleetConfidenceProvider`. Default behaviour is unchanged (0.8 constant).
- Native `simulation_run_batch` C function now accepts `fleet_confidence` as a parameter. Shared library rebuilt.
- Adds `fleet_hazard: ^0.3.0` as a dependency.

## 0.4.0

- **Refactor**: drop direct `navigation_safety` package dependency; consume `navigation_safety_core` (pure-Dart core) only. Tracks the NSC pure-Dart core extraction (commit `86632c4`); driving_conditions only uses the core safety vocabulary types and never required the Flutter+BLoC surface.
- **Breaking**: `SafetyScoreSimulator.simulate()` and `SafetyScoreSimulationEngine.simulate()` now return `SimulationResult` instead of `SafetyScore`.
- **New type**: `SimulationResult` — wraps the mean `SafetyScore` with statistical measures: `variance`, `incidentCount`, and (native engine only) `executionMs`.
- **Promoted**: `NativeSafetyScoreSimulationEngine` is now part of the public API. Edge developers can instantiate it directly to access native-engine execution timing.
- `CpuSafetyScoreSimulationEngine.simulate()` now computes and exposes `variance` and `incidentCount` from the Monte Carlo runs.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

