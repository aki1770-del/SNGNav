# Known limitations

This document lists known limitations of the current `map_viewport_bloc`
package, with citations to public sources, so that consumers can
integrate with eyes open and contribute corrections from informed
positions.

The list is honest by intent — surfacing what we don't yet know rather
than letting silent gaps reach drivers.

---

## ViewportRenderBudgetBloc viewport-class composition (added in 0.4.0) — UNVERIFIED magnitudes

The 0.4.0 release adds `ViewportRenderBudgetBloc` +
`ViewportRenderConfig` + `ViewportRenderConfig.forProfile(DriverProfile)`
factory + per-cohort `RenderFidelityFloor`. The **API shape** is
intentional and stable (the bloc composes upstream `PerformanceBudget`
and `DataBudget` streams into a single `RenderFidelity` recommendation
with the caution-add-direction-wins composition rule); the
**magnitudes** in the per-cohort `RenderFidelityFloor` factory are
design-default hypotheses pending field-measurement validation.

### What is UNVERIFIED at 0.4.0

- **Per-cohort `RenderFidelityFloor` choices** (`professional` /
  `snowZoneExperienced` / `agriculturalForestry` → LOW floor;
  `noviceUrban` / `ageingRural` / `foreignTouristSnowZone` → MEDIUM
  floor). The choice that visual-cognitive-margin cohorts get a
  higher floor (= bloc never drops to LOW) is qualitatively-anchored
  in the same age-group reaction-time / cognitive-load literature
  that motivates the `PerformanceBudget` per-cohort lenient-direction
  defaults; the specific binary floor choice (LOW vs MEDIUM) is a
  v1 design-default-hypothesis. A more granular per-cohort floor (or
  a per-cohort + per-context floor) may graduate in v2 if integrator
  field-evidence motivates it.

- **Caution-add-direction-wins composition strategy** — the v1
  composition rule is straightforward (any Exhausted → LOW; any
  Warning → MEDIUM; else HIGH). A more sophisticated threshold-class
  composition (PerformanceBudget Warning + DataBudget OK = HIGH still
  vs MEDIUM; PerformanceBudget Warning + DataBudget Warning = LOW)
  may graduate in v2 if integrator field-evidence shows the v1 rule
  is too conservative or too lenient. The v1 rule is conservative-
  only and consistent with the caution-add-only invariant family
  ("when in doubt, add caution").

- **Reset semantics** — the bloc requires explicit `ViewportBudgetReset`
  to return to HIGH. There is intentionally NO automatic recovery
  (e.g. "if no Exhausted in N seconds, return to HIGH"). The choice
  matches the auto-relax-forbidden discipline of upstream
  `DataBudget.relax`. Field-evidence may motivate a confirmation-
  gated auto-recovery pattern in v2.

### What is verified at 0.4.0

- **API shape** — the bloc subscribes to upstream streams via
  `attachPerformanceBudgetStream` / `attachDataBudgetStream`; the
  runtime-typed listener (inspecting
  `event.runtimeType.toString()`) keeps the bloc compatible with
  both `offline_tiles` and `snow_rendering` event classes without
  re-importing either package's sealed types. Unit tests cover
  state transitions / caution-add-direction-wins / per-cohort
  floor enforcement / reset.

- **Caution-add-direction-wins contract** — verified by
  test/viewport_render_budget_bloc_test.dart positive + negative
  assertions: any Exhausted on either stream → LOW (after floor);
  any Warning → MEDIUM; both nominal → HIGH; conflict resolves
  toward caution-add direction.

- **Per-cohort floor contract** — verified by floor-enforcement
  tests: `ageingRural` cohort never drops to LOW even when both
  budgets are exhausted (resolves to MEDIUM via floor).

- **Severity-not-profile contract** — the bloc emits
  `RenderFidelity` recommendations only; it does not modify alert
  severity tiers. Verified at `SAFETY_BOUNDARY.md` §6 + library-
  level docstring.

- **Driver-always-drives contract** — the bloc never RAISES fidelity
  in response to a stream event; only integrator-driven
  `ViewportBudgetReset` returns to HIGH.

- **Back-compat** — pre-existing `MapBloc`, `MapState`, `MapEvent`,
  and viewport model contracts unchanged from 0.3.x.

### Out of scope at 0.4.0

- Live-detection of integrator-render-strategy is out of scope. The
  bloc consumes the upstream stream events only; the integrator
  decides what to do with the `RenderFidelity` recommendation.

- Per-cohort-validated `RenderFidelityFloor` tables (the 0.4.0
  values are placeholders pending the integrator's own fleet-class
  telemetry).

- Three-way (or more) budget composition (e.g. adding a memory-
  pressure budget alongside frame + data) is reserved for v2 when
  the third-axis evidence materializes; the bloc's
  `attach*Stream` pattern is forward-compatible with extension.

### Integrator-side caveats

- **Stream supply-chain caveat**: the integrator is responsible for
  constructing the upstream `PerformanceBudget` and `DataBudget`
  instances and connecting their `budgetEvents` streams to the bloc
  via `attachPerformanceBudgetStream` / `attachDataBudgetStream`.
  The bloc holds StreamSubscription handles and cancels them in
  `close()`.

- **Runtime-typed listener caveat**: the bloc identifies upstream
  events by `runtimeType.toString()` matching `'BudgetWarning'` /
  `'BudgetExhausted'`. This is a deliberate choice to keep the bloc
  compatible with both upstream packages without depending on either
  sealed-class hierarchy. Integrators who construct custom budget
  events with collision-class names should namespace appropriately
  or adapt the events before forwarding.

- **Test discipline**: tests in
  `test/viewport_render_budget_bloc_test.dart` exercise the bloc
  with fabricated events (using `attachPerformanceBudgetStream` with
  test-class streams). Integrators should add integration tests
  against their actual upstream `PerformanceBudget` / `DataBudget`
  instances.

---

## Pre-existing limitations (0.3.x and earlier)

See `CHANGELOG.md` 0.3.0 entry for the version-harmonization note.
No new disclosures at 0.4.0 affect the existing `MapBloc` /
`MapState` surfaces.
