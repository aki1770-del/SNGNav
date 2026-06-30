# Changelog

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

