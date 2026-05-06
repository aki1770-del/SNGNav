# Known limitations

This document lists known limitations of the current `offline_tiles`
package, with citations to public sources, so that consumers can
integrate with eyes open and contribute corrections from informed
positions.

The list is honest by intent — surfacing what we don't yet know rather
than letting silent gaps reach drivers.

---

## PerformanceBudget per-cohort frame-budget defaults (added in 0.5.0) — UNVERIFIED magnitudes

The 0.5.0 release adds `PerformanceBudget` + `PerformanceBudgetConfig`
+ `PerformanceBudgetConfig.forProfile(DriverProfile)` factory. The
**API shape** is intentional and stable (mirrors the
`GlanceBudgetTracker` precedent from `navigation_safety` 0.9.0); the
**magnitudes** in the per-cohort `forProfile` factory are
design-default hypotheses pending field-measurement validation.

### What is UNVERIFIED at 0.5.0

- **Per-cohort frame-budget magnitudes** (`professional` /
  `snowZoneExperienced` / `agriculturalForestry` 16ms baseline /
  `noviceUrban` 18ms / `ageingRural` 22ms /
  `foreignTouristSnowZone` 22ms). The 16ms baseline is published-
  anchor (Flutter / Skia 60fps target = 16.67ms / frame). The
  per-cohort lenient-direction values are conservative-only (every
  multiplier `>=` 16ms baseline) and ordered to match age-group
  reaction-time literature qualitatively (older drivers tolerate /
  benefit from longer frame allowance for visual-cognitive-margin),
  but the specific magnitudes (18ms / 22ms / 22ms) are NOT yet
  anchored in a published population study mapping driver-cohort to
  optimal-frame-rate-tolerance specifically. Per-population
  calibration is deferred pending fleet-class field measurement.

- **`sustainedFrames` default of 5** — the choice that
  `BudgetExhausted` requires 5 consecutive over-budget frames before
  firing is engineering-judgement on what distinguishes single-frame
  jank (normal Skia behaviour) from sustained over-budget consumption
  (jank-class regression worth surfacing). The choice is sensitive to
  the integrator's frame-pacing strategy; integrators reporting
  field-evidence may motivate tuning.

- **`warningRatio` default of 0.75** — mirrors the `GlanceBudgetTracker`
  precedent. The 75% threshold is published-anchor for typical budget-
  warning HMI patterns; the choice may not be optimal for per-frame
  budgets specifically.

### What is verified at 0.5.0

- **API shape** — the `FrameTimingProvider` interface is integrator-
  implemented and orthogonal to the existing `OfflineTileManager`;
  every input is opt-in (defaults preserve 0.4.x behaviour exactly).
  Unit tests cover `record()` / `BudgetWarning` / `BudgetExhausted` /
  `reset()` / `dispose()` + per-cohort allocation.

- **Caution-add-only contract** — `PerformanceBudgetConfig.forProfile`
  rejects per-cohort budget below the 16ms baseline at runtime via
  debug-mode assertion. Verified by negative-assertion test.

- **Severity-not-profile contract** — the tracker is timing-class
  only; it does not modify alert severity tiers. Verified at
  `SAFETY_BOUNDARY.md` §6 + library-level docstring.

- **Driver-always-drives contract** — the tracker is presentation-
  class only. The reset path is integrator-explicit.

- **Back-compat** — pre-existing `OfflineTileManager`,
  `OfflineTileProvider`, `RuntimeTileResolver`, and `TileCacheConfig`
  contracts unchanged from 0.4.x.

### Out of scope at 0.5.0

- Live-detection of frame-pacing strategy (whether the integrator
  is using `RasterCache` / `Picture` recording / off-thread image
  decode etc.) is out of scope. The package consumes the integrator-
  supplied `FrameTiming` only.

- Per-cohort-validated magnitude tables (the 0.5.0 magnitudes are
  placeholders pending the integrator's own fleet-class telemetry).

- Per-modal-class sub-budgets (raster-time vs UI-thread vs platform-
  thread) are reserved for v2 differentiation when field evidence
  motivates them.

### Integrator-side caveats

- **`FrameTimingProvider` supply-chain caveat**: the integrator is
  responsible for the adapter from Flutter `SchedulerBinding` (or
  whichever rendering surface the integrator owns) to the package's
  `FrameTimingProvider` interface. The package consumes only typed
  `FrameTiming` values; supply-chain provenance of those values is
  the integrator's concern.

- **Test discipline**: tests in `test/performance_budget_test.dart`
  exercise the budget logic with fabricated `FrameTiming` values. The
  test does not mount a real Flutter rendering engine; integrators
  should add integration tests against their own rendering pipeline.

---

## Pre-existing limitations (0.4.x and earlier)

See `CHANGELOG.md` 0.3.0 / 0.4.0 entries for migration notes
(MBTiles native assets, `flutter_map` ^8.x compatibility, sqflite
removal). No new disclosures at 0.5.0 affect these earlier surfaces.
