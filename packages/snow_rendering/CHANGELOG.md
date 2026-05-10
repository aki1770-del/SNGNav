## 0.2.1 — 2026-05-10 — Refresh cascade-stale dependency constraint

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- No source changes; pubspec dep-constraint refresh only.

## 0.2.0

- Add `DataBudget` — stateful data-fetch budget tracker for snow-
  overlay render bandwidth management. Integrator-supplied
  `DataMeterProvider` interface; per-cycle bytes budget checked against
  `DataBudgetConfig`; broadcast `budgetEvents` stream emits
  `BudgetWarning` (75%) / `BudgetExhausted` (100%) /
  `RenderFidelityDrop` (in lock-step with Exhausted). Mirrors the
  `GlanceBudgetTracker` pattern from `navigation_safety` 0.9.0
  (caution-add-only / severity-not-profile / driver-always-drives
  invariants enforced via debug-mode runtime asserts).
- Add `DataBudgetConfig.forProfile(DriverProfile)` factory — per-
  cohort tighter-direction defaults (4MB baseline / 3MB `noviceUrban`
  / 2MB `ageingRural` + `foreignTouristSnowZone` for bandwidth-margin).
  Per-cohort budgets are **UNVERIFIED-magnitude design-default-
  hypothesis** pending field-measurement validation; conservative-only
  (every cohort `<=` 4MB baseline). Per-population calibration
  deferred.
- Add `tighten(int)` — auto-tightening allowed at runtime; new budget
  must be `<=` active budget per caution-add-only invariant.
- Add `relax(int, BudgetRelaxConfirmation)` — auto-relax FORBIDDEN;
  loosening requires integrator-supplied affirmative confirmation
  token. Mirrors the cap-override-with-confirmation pattern from
  `navigation_safety_core` 0.10.0 #30 (driver-always-drives).
- Add `BudgetResetReason` enum + `DataFetchEvent` value object +
  sealed `DataBudgetEvent` hierarchy.
- Add `navigation_safety_core: ^0.10.0` dependency for `DriverProfile`
  consumption.
- Add `SAFETY_BOUNDARY.md` (DataBudget invariants; cohort-tighter
  direction caveat; auto-relax-with-confirmation pattern; ASIL-QM
  advisory; severity-not-profile + driver-always-drives preserved).
- Add `KNOWN_LIMITATIONS.md` (per-cohort data-budget UNVERIFIED-
  magnitude flags + bandwidth-class assumptions).
- Public API additions are non-breaking; existing
  `DrivingConditionAssessment` / `RoadSurfaceState` /
  `PrecipitationConfig` / `VisibilityDegradation` contracts unchanged.

## 0.1.0

- Initial extraction from `driving_conditions` (SNGNav P1, D-SC22-2).
- `RoadSurfaceState` — six-state road surface classification with grip factors.
- `PrecipitationConfig` — particle configuration derived from weather conditions.
- `VisibilityDegradation` — opacity and blur parameters from visibility distance.
- `DrivingConditionAssessment` — combined assessment with advisory message.
- `HysteresisFilter<T>` — debounce filter for state oscillation at boundary conditions.
