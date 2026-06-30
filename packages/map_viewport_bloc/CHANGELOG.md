# Changelog

## 0.4.3
- docs: correct stale README install pin to current version (no API change).

## 0.4.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.1 — 2026-05-10 — Pana score recovery (Theme α P4)

- Trim pubspec `description` to within the pana 60–180 character target.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.4.0

- Add `ViewportRenderBudgetBloc` — composes `PerformanceBudget` (from
  `offline_tiles` 0.5.0) and `DataBudget` (from `snow_rendering`
  0.2.0) streams into a single `ViewportRenderState` with a
  `RenderFidelity` recommendation (`high` / `medium` / `low`).
- **Caution-add-direction-wins on conflict** (load-bearing): any
  `BudgetExhausted` on either stream → fidelity LOW; otherwise any
  `BudgetWarning` → fidelity MEDIUM; else HIGH. The bloc never RAISES
  fidelity in response to a stream event; reset returns to HIGH.
- Add `ViewportRenderConfig.forProfile(DriverProfile)` factory with
  per-cohort `RenderFidelityFloor` (UNVERIFIED-magnitude design-
  default-hypothesis). Cohorts `ageingRural` /
  `foreignTouristSnowZone` / `noviceUrban` get MEDIUM floor (bloc
  never drops to LOW; visual-cognitive-margin demands richer
  rendering). Cohorts `professional` / `snowZoneExperienced` /
  `agriculturalForestry` get LOW floor.
- Add `attachPerformanceBudgetStream` /
  `attachDataBudgetStream` — runtime-typed listener subscription.
- Add `ViewportBudgetReset` event — integrator-driven; returns
  fidelity to HIGH and clears observed-flags.
- Add `navigation_safety_core: ^0.10.0` dependency for `DriverProfile`
  consumption.
- Add `SAFETY_BOUNDARY.md` (viewport-class composition invariants;
  caution-add-direction-wins on conflict; ASIL-QM advisory;
  severity-not-profile + driver-always-drives preserved).
- Add `KNOWN_LIMITATIONS.md` (viewport-class composition strategy
  UNVERIFIED-magnitude; per-cohort `RenderFidelityFloor` design-
  default-hypothesis).
- Public API additions are non-breaking; existing `MapBloc` /
  `MapState` / `MapEvent` / model contracts unchanged.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

