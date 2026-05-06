# Known limitations

This document lists known limitations of the current `snow_rendering`
package, with citations to public sources, so that consumers can
integrate with eyes open and contribute corrections from informed
positions.

The list is honest by intent — surfacing what we don't yet know rather
than letting silent gaps reach drivers.

---

## DataBudget per-cohort byte-budget defaults (added in 0.2.0) — UNVERIFIED magnitudes

The 0.2.0 release adds `DataBudget` + `DataBudgetConfig` +
`DataBudgetConfig.forProfile(DriverProfile)` factory + the
`relax(int, BudgetRelaxConfirmation)` cap-override-with-confirmation
pattern. The **API shape** is intentional and stable (mirrors the
`GlanceBudgetTracker` precedent from `navigation_safety` 0.9.0 + the
cap-override-with-confirmation precedent from `navigation_safety_core`
0.10.0 #30); the **magnitudes** in the per-cohort `forProfile` factory
are design-default hypotheses pending field-measurement validation.

### What is UNVERIFIED at 0.2.0

- **Per-cohort data-budget magnitudes** (`professional` /
  `snowZoneExperienced` / `agriculturalForestry` 4MB baseline /
  `noviceUrban` 3MB / `ageingRural` 2MB /
  `foreignTouristSnowZone` 2MB). The 4MB baseline is engineering-
  judgement consistent with mobile-bandwidth-respect range (typical
  2-8MB / minute supplemental overlay fetch); the per-cohort tighter-
  direction values are conservative-only (every cohort `<=` 4MB
  baseline) and ordered to match bandwidth-class assumptions
  (rural-bandwidth-margin for `ageingRural`; international-roaming-
  cost for `foreignTouristSnowZone`; urban-mobile-data-cost for
  `noviceUrban`). The specific magnitudes (3MB / 2MB / 2MB) are NOT
  yet anchored in a published study mapping driver-cohort to
  optimal-data-budget specifically. Per-population calibration is
  deferred pending fleet-class field measurement.

- **Bandwidth-class assumptions** — the per-cohort tighter-direction
  rationale assumes:
  - `ageingRural` → slower-rural-data; tighter budget reduces fetch
    wait. Assumption sensitive to actual rural data-coverage in the
    integrator's deployment region.
  - `foreignTouristSnowZone` → international-roaming-cost margin.
    Assumption sensitive to actual roaming-data-cost in the
    integrator's tourist-cohort population.
  - `noviceUrban` → urban-mobile-data-cost margin. Assumption
    sensitive to actual urban-data-cost in the integrator's
    deployment region.
  All three assumptions are integrator-tunable via the explicit
  `DataBudgetConfig` constructor; the `forProfile` factory is a
  default-only convenience.

- **`warningRatio` default of 0.75** — mirrors the `GlanceBudgetTracker`
  / `PerformanceBudget` precedents. The 75% threshold is published-
  anchor for typical budget-warning HMI patterns.

### What is verified at 0.2.0

- **API shape** — the `DataMeterProvider` interface is integrator-
  implemented and orthogonal to the existing `DrivingConditionAssessment`;
  every input is opt-in (defaults preserve 0.1.x behaviour exactly).
  Unit tests cover `record()` / `BudgetWarning` / `BudgetExhausted` /
  `RenderFidelityDrop` / `tighten()` / `relax()` / `reset()` /
  `dispose()` + per-cohort allocation.

- **Caution-add-only contract** — `DataBudgetConfig.forProfile`
  rejects per-cohort budget above the 4MB baseline at runtime via
  debug-mode assertion. `tighten(int)` rejects newBudgetBytes larger
  than active budget. Auto-relax forbidden; only `relax(int,
  BudgetRelaxConfirmation)` with affirmative confirmation may loosen
  the budget. Verified by negative-assertion tests.

- **Driver-always-drives contract** — `relax` rejects
  `confirmation.isConfirmed == false` and empty `confirmation.reason`
  at runtime via debug-mode assertion. Verified by the relax-flow
  test in `test/data_budget_test.dart`.

- **Severity-not-profile contract** — the tracker is bandwidth-class
  only; it does not modify alert severity tiers. Verified at
  `SAFETY_BOUNDARY.md` §6 + library-level docstring.

- **Back-compat** — pre-existing `RoadSurfaceState`,
  `PrecipitationConfig`, `VisibilityDegradation`, and
  `DrivingConditionAssessment` contracts unchanged from 0.1.x. Pure
  Dart property preserved (the 0.2.0 additions add only `equatable`
  and `navigation_safety_core` dependencies; both pure Dart).

### Out of scope at 0.2.0

- Live-detection of network-class (WiFi vs mobile-data vs roaming)
  is out of scope. The package consumes only the integrator-supplied
  byte-count; integrators that wish to gate behaviour on
  network-class should signal via `BudgetResetReason.networkClassChange`
  and re-configure the tracker.

- Per-cohort-validated magnitude tables (the 0.2.0 magnitudes are
  placeholders pending the integrator's own fleet-class telemetry).

- Per-fetch-class sub-budgets (overlay vs route vs surface-state
  fetch) are reserved for v2 differentiation when field evidence
  motivates them.

### Integrator-side caveats

- **`DataMeterProvider` supply-chain caveat**: the integrator is
  responsible for the adapter from their network sub-system to the
  package's `DataMeterProvider` interface. The package consumes only
  typed `DataFetchEvent` byte-count values; supply-chain provenance
  is the integrator's concern.

- **`BudgetRelaxConfirmation` discipline**: the cap-override-with-
  confirmation pattern requires the integrator to BUILD a
  confirmation surface (e.g. user-tap dialog). The package does not
  invent the surface. The discipline is: relax(...)
  must NEVER be called from a code path that does not pass through
  affirmative driver-confirmed input. The `assert` is a backstop, not
  a substitute for the discipline.

---

## Pre-existing limitations (0.1.x)

See `CHANGELOG.md` 0.1.0 entry for the founding extraction note.
No new disclosures at 0.2.0 affect the existing
`DrivingConditionAssessment` surface.
