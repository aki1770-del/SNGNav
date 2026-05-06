# map_viewport_bloc — Safety-Class Boundary Record

**Package**: `map_viewport_bloc`
**Version**: 0.4.0 (DEPLOY)
**Boundary record version**: 1.0 (founding; introduced with `ViewportRenderBudgetBloc` substrate)
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-06
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
**Related**: `navigation_safety_core` SAFETY_BOUNDARY.md (severity-not-profile + driver-always-drives invariants inherited verbatim through transitive `navigation_safety_core: ^0.10.0` dependency); `offline_tiles` SAFETY_BOUNDARY.md (PerformanceBudget producer); `snow_rendering` SAFETY_BOUNDARY.md (DataBudget producer).

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces — `MapBloc` (camera state machine) + (new in 0.4.0) `ViewportRenderBudgetBloc` (render-fidelity composer) — emit value-objects consumed by the integrator HMI. The package neither actuates the vehicle nor closes a control loop.
**No L2+ claim.** Any handover-class or supervision-class deployment requires the integrator to add their own driver-attention monitoring, take-over-request signalling, and minimum-risk-manoeuvre fallback per L2+ standards.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are state-machine value-objects (`MapState`, `ViewportRenderState`) consumed by the integrator HMI. No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary. The 0.4.0 `ViewportRenderBudgetBloc` integration emits a `RenderFidelity` recommendation the integrator HMI may consume to lighten render-load; it does not actuate any vehicle surface.
**Integrator responsibility**: the integrator performs the hazard analysis and decides the final ASIL classification for their integration.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package does not deliver an automated driving feature; it delivers viewport state-machine substrate plus advisory render-fidelity composition. SOTIF triage is performed by the integrator at their HMI scope.
**Severity-not-profile invariant** (load-bearing, inherited verbatim from `navigation_safety_core` SAFETY_BOUNDARY.md §6): the bloc modulates RENDER FIDELITY per profile (visual-cognitive-margin direction); it does NOT modify alert severity, score floors, or critical thresholds. Critical alerts in `navigation_safety` retain their critical-bypass invariant regardless of viewport-render state.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at package boundary.** The bloc consumes typed events (sealed `MapEvent` hierarchy + sealed `ViewportRenderBudgetEvent` hierarchy) and emits typed states. No external network surface; no over-the-air update surface; no key-management surface.
**Integrator responsibility**: any integrator who wires external sources (sensor / cloud / fleet) into events or supplies the upstream `PerformanceBudget` / `DataBudget` streams is the consumer-side WP.29 touchpoint owner.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.** Japanese-domestic certification is integrator-class concern. Per the inherited `navigation_safety_core` boundary record §5: *"Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface."*

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete locus**:
- `lib/src/viewport_render_budget_bloc.dart` library-level docstring — explicit declaration that the bloc modulates render fidelity only and does not modify severity tiers.
- `ViewportRenderBudgetBloc` reducers — emit `RenderFidelity` recommendations only; never severity-mutating values; never modify alert score floors.

**Operational consequence**: per-profile differentiation lives in `ViewportRenderConfig.forProfile`'s `RenderFidelityFloor` only — never in alert severity.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design** per D-VGC188-1.
**Concrete locus**:
- `lib/src/viewport_render_budget_bloc.dart` library-level docstring — *"the bloc emits state for the integrator HMI to render. It mounts no actuator; the driver always drives."*
- All bloc reducers emit `ViewportRenderState` value-objects only; no actuator surface; no vehicle-state mutation.
- The bloc never RAISES fidelity in response to a stream event (auto-relax-forbidden); only `ViewportBudgetReset` (integrator-driven) returns to HIGH. Auto-loosen is FORBIDDEN; this is the bloc-level mirror of the cap-override-with-confirmation pattern in `snow_rendering` 0.2.0 `DataBudget.relax`.

## 8 — ViewportRenderBudgetBloc driver-facing-loom (new in 0.4.0)

**Operational discipline**: *the bloc composes per-frame and per-cycle budget streams into a single render-fidelity recommendation so the integrator HMI receives one coherent caution-add-direction-wins signal instead of two independent budget streams the integrator must invent composition rules for.*

**Concrete locus**: `lib/src/viewport_render_budget_bloc.dart` `ViewportRenderBudgetBloc.attachPerformanceBudgetStream(Stream<Object>)` + `attachDataBudgetStream(Stream<Object>)` subscribe to upstream `PerformanceBudget.budgetEvents` (from `offline_tiles` 0.5.0) and `DataBudget.budgetEvents` (from `snow_rendering` 0.2.0); the bloc dispatches the appropriate internal event for each emitted `BudgetWarning` / `BudgetExhausted`. The reducer emits `ViewportRenderState` with a `RenderFidelity` recommendation (high / medium / low). Reset via `ViewportBudgetReset` event is integrator-explicit only.

**Caution-add-direction-wins invariant** (load-bearing): when PerformanceBudget and DataBudget disagree on direction, the caution-add direction wins. Concretely: any `BudgetExhausted` on either stream → fidelity LOW; otherwise any `BudgetWarning` → fidelity MEDIUM; else HIGH. The bloc never RAISES fidelity in response to a stream event.

**Per-cohort `RenderFidelityFloor` invariant**: cohorts whose visual-cognitive-margin demands a richer rendering (`ageingRural`, `foreignTouristSnowZone`, `noviceUrban`) have a HIGHER floor (MEDIUM; bloc never drops to LOW for these cohorts). Cohorts who can tolerate the lowest fidelity (`professional`, `snowZoneExperienced`, `agriculturalForestry`) have the LOW floor. The floor never RAISES fidelity; it only prevents the bloc from going BELOW the floor.

**Severity-not-profile invariant preserved** (load-bearing per §6 above): the bloc modulates RENDER FIDELITY only. It does NOT adjust score floors or severity tiers. Critical alerts retain their critical-bypass invariant.

**Driver-always-drives invariant preserved** (load-bearing per §7 above): the bloc is reporting-only. It mounts no actuator, suppresses no input, locks no driver out. The driver always drives.

**UNVERIFIED-magnitude flags** (per `KNOWN_LIMITATIONS.md`): per-cohort `RenderFidelityFloor` choices are **design-default hypotheses** pending field-measurement validation. Per-population calibration deferred pending fleet-class field measurement.

**ASIL-QM advisory** per §2 (no functional-safety claim asserted at the package boundary). **WP.29 touchpoint** at integrator's upstream stream sources, not at this package (per §4).

## 9 — Cross-references

- `lib/src/viewport_render_budget_bloc.dart` — 0.4.0 `ViewportRenderBudgetBloc` substrate
- `lib/map_viewport_bloc.dart` — re-exports `viewport_render_budget_bloc.dart`
- `KNOWN_LIMITATIONS.md` — per-cohort floor UNVERIFIED-magnitude flag; viewport-class composition strategy caveat
- `CHANGELOG.md` 0.4.0 entry — verbatim caution-add-direction-wins declaration + UNVERIFIED-magnitude flag
- `navigation_safety_core` SAFETY_BOUNDARY.md (re-exported core boundary applies; severity-not-profile invariant inherited verbatim)
- `offline_tiles` SAFETY_BOUNDARY.md §8 — PerformanceBudget producer
- `snow_rendering` SAFETY_BOUNDARY.md §8 — DataBudget producer
- LICENSE: BSD-3-Clause

---

**Boundary record authored** by AAA (automotive-adas-analyst) under VAA-as-SEO operational pen authorization (spawn -86). Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
