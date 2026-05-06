# Changelog

## 0.5.0

- Add `PerformanceBudget` — stateful frame-timing budget tracker for
  tile-render advisory cognitive-load management. Integrator-supplied
  `FrameTimingProvider` interface; per-frame budget checked against
  `PerformanceBudgetConfig`; broadcast `budgetEvents` stream emits
  `BudgetWarning` (75% sustained) / `BudgetExhausted` (100% sustained
  over `sustainedFrames` consecutive frames). Mirrors the
  `GlanceBudgetTracker` pattern from `navigation_safety` 0.9.0
  (caution-add-only / severity-not-profile / driver-always-drives
  invariants enforced via debug-mode runtime asserts).
- Add `PerformanceBudgetConfig.forProfile(DriverProfile)` factory — per-
  cohort lenient-direction defaults (16ms baseline / 18ms
  `noviceUrban` / 22ms `ageingRural` + `foreignTouristSnowZone` for
  visual-cognitive-margin). Per-cohort budgets are
  **UNVERIFIED-magnitude design-default-hypothesis** pending field-
  measurement validation; conservative-only (every cohort `>=` 16ms
  baseline). Per-population calibration deferred.
- Add `BudgetResetReason` enum — render-cycle / long-pause / explicit.
- Add `navigation_safety_core: ^0.10.0` dependency for `DriverProfile`
  consumption. Add `equatable: ^2.0.7` (used by sealed event classes).
- Add `SAFETY_BOUNDARY.md` (driving-automation-regime declaration;
  PerformanceBudget invariants; ASIL-QM advisory; severity-not-profile
  + driver-always-drives preserved).
- Add `KNOWN_LIMITATIONS.md` (per-cohort budget UNVERIFIED-magnitude
  flags + integrator-side FrameTimingProvider supply-chain caveats).
- Public API additions are non-breaking; existing
  `OfflineTileManager` / providers / resolvers contracts unchanged.

## 0.4.0

- Migrate to `mbtiles ^0.5.0` and `sqlite3 ^3.2.0` (native assets).
- Remove EOL `sqflite` dependency.
- Remove unused `flutter_map_mbtiles` phantom dependency.
- Internal API update: `MbTiles(path:)`, `MbTiles.create(path:)`, `close()` replacing `dispose()`.
- Public API unchanged: `OfflineTileManager(mbtilesPath:)` contract preserved.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

