# offline_tiles — Safety-Class Boundary Record

**Package**: `offline_tiles`
**Version**: 0.5.0 (DEPLOY)
**Boundary record version**: 1.0 (founding; introduced with `PerformanceBudget` substrate)
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-06
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
**Related**: `navigation_safety_core` SAFETY_BOUNDARY.md (severity-not-profile + driver-always-drives invariants inherited verbatim through transitive `navigation_safety_core: ^0.10.0` dependency); `navigation_safety` SAFETY_BOUNDARY.md §8.1 (GlanceBudgetTracker structural precedent).

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces — `OfflineTileManager` + `OfflineTileProvider` + `RuntimeTileResolver` + (new in 0.5.0) `PerformanceBudget` — supply tile rendering and per-frame budget telemetry consumed by the integrator HMI. The package neither actuates the vehicle nor closes a control loop.
**No L2+ claim.** Any handover-class or supervision-class deployment requires the integrator to add their own driver-attention monitoring, take-over-request signalling, and minimum-risk-manoeuvre fallback per L2+ standards.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are tile bytes (offline-cached MBTiles content, integrator-supplied) plus advisory-class frame-budget telemetry. No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary. The 0.5.0 `PerformanceBudget` integration emits broadcast events the integrator HMI may consume to lighten render-load; it does not actuate any vehicle surface.
**Integrator responsibility**: the integrator performs the hazard analysis and decides the final ASIL classification for their integration.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package does not deliver an automated driving feature; it delivers tile-rendering substrate plus advisory frame-budget telemetry consumed by integrator HMI surfaces. SOTIF triage is performed by the integrator at their HMI scope.
**Severity-not-profile invariant** (load-bearing, inherited verbatim from `navigation_safety_core` SAFETY_BOUNDARY.md §6): the per-frame `PerformanceBudget` modulates RENDER-LOAD per profile (visual-cognitive-margin direction); it does NOT modify alert severity, score floors, or critical thresholds. Critical alerts in `navigation_safety` retain their critical-bypass invariant regardless of frame-budget state.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at package boundary.** The package consumes typed value-objects (`DriverProfile` from `navigation_safety_core`, `FrameTiming` from `dart:ui`) and integrator-owned MBTiles file paths. No external network surface at this layer; no over-the-air update surface; no key-management surface. Tile bytes are fetched from integrator-provided local MBTiles archives.
**Integrator responsibility**: any integrator who feeds external sources (sensor / cloud / fleet) into the resolver chain or supplies the `FrameTimingProvider` adapter is the consumer-side WP.29 touchpoint owner.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.** Japanese-domestic certification is integrator-class concern. Per the inherited `navigation_safety_core` boundary record §5: *"Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface."*

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete locus**:
- `lib/src/performance_budget.dart` library-level docstring — explicit declaration that the tracker is timing-class only and does not modify severity tiers.
- `lib/src/performance_budget.dart` `PerformanceBudgetConfig.forProfile` — per-cohort `frameBudget` adjusts TIMING (warn-earlier on render-load) only; the factory does not return severity-mutating values; the runtime debug assertion verifies `frameBudget >= baselineFrameBudget`.

**Operational consequence**: per-profile differentiation lives in `PerformanceBudgetConfig.forProfile`'s frame-budget allowance only — never in alert severity, never in the score-floor tiers. The bloc consumer (`map_viewport_bloc` 0.4.0 `ViewportRenderBudgetBloc`) modulates RENDER FIDELITY only.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design** per D-VGC188-1.
**Concrete locus**:
- `lib/src/performance_budget.dart` library-level docstring — *"the tracker is presentation-class only. The integrator may dim a non-essential layer when `BudgetWarning` fires, but the package itself does not modify any driver-facing surface or vehicle state."*
- `PerformanceBudget.record(FrameTiming)` — observation-only; no actuator surface; no vehicle-state mutation.
- `PerformanceBudget.reset(BudgetResetReason)` — integrator-explicit only; the tracker does NOT auto-reset on cooldown.

## 8 — PerformanceBudget driver-facing-loom (new in 0.5.0)

**Operational discipline**: *the budget reports cumulative per-frame render time against a per-cohort allowance so an integrator HMI can lighten attention demand before the budget is exhausted; the package supplies the substrate, the integrator owns the surface.*

**Concrete locus**: `lib/src/performance_budget.dart` `PerformanceBudget.record(FrameTiming)` consumes integrator-supplied `FrameTiming` events (typically adapted from Flutter `SchedulerBinding.instance.addTimingsCallback`); emits `BudgetWarning` (default 75% consumed) and `BudgetExhausted` (after `sustainedFrames` consecutive over-budget frames; default 5) records on a broadcast `budgetEvents` stream. Reset via `reset(BudgetResetReason)` is integrator-explicit only.

**Caution-add-only invariant** (load-bearing): the per-cohort frame budget produced by `PerformanceBudgetConfig.forProfile` is `>=` the 16ms baseline. Lower-than-baseline values would relax the visual-cognitive-margin direction and are rejected at runtime via debug-mode assertion in `forProfile`; in release builds the assertion is elided per Dart `assert` semantics, but a relaxing factory return remains a programmer error and is detectable via `test/performance_budget_test.dart`. Auto-relax-on-cooldown is intentionally absent at v1; integrator's `reset()` call is the only path that resets the warning/exhausted fired-once flags.

**Severity-not-profile invariant preserved** (load-bearing per §6 above): the tracker is timing-class only. It supplies a substrate the integrator may use to modulate display-density / drop layer fidelity; it does not adjust score floors or severity tiers. Critical alerts retain their critical-bypass invariant.

**Driver-always-drives invariant preserved** (load-bearing per §7 above): the tracker is reporting-only. It mounts no actuator, suppresses no input, locks no driver out. The driver always drives; the tracker only reports.

**UNVERIFIED-magnitude flags** (per `KNOWN_LIMITATIONS.md`): per-cohort frame-budget magnitudes are **design-default hypotheses** pending field-measurement validation. Per-population calibration deferred pending fleet-class field measurement.

**ASIL-QM advisory** per §2 (no functional-safety claim asserted at the package boundary). **WP.29 touchpoint** at integrator's `FrameTimingProvider` implementation, not at this package (per §4; the interface is consumer-implemented; the package consumes only typed `FrameTiming` values at this layer).

## 9 — Cross-references

- `lib/src/performance_budget.dart` — 0.5.0 `PerformanceBudget` substrate
- `lib/offline_tiles.dart` — re-exports `performance_budget.dart`
- `KNOWN_LIMITATIONS.md` — per-cohort budget UNVERIFIED-magnitude flag; FrameTimingProvider supply-chain caveat
- `CHANGELOG.md` 0.5.0 entry — verbatim caution-add-only declaration + UNVERIFIED-magnitude flag
- `navigation_safety_core` SAFETY_BOUNDARY.md (re-exported core boundary applies; severity-not-profile invariant inherited verbatim)
- `navigation_safety` SAFETY_BOUNDARY.md §8.1 — `GlanceBudgetTracker` structural precedent
- LICENSE: BSD-3-Clause

---

**Boundary record authored** by AAA (automotive-adas-analyst) under VAA-as-SEO operational pen authorization (spawn -86). Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
