# navigation_safety — Safety-Class Boundary Record

**Package**: `navigation_safety`
**Version**: 0.9.0 (DEPLOY)
**Boundary record version**: 1.1 (0.9.0 addendum: GlanceBudgetTracker + AlertExplainerExpandableSheet)
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-06
**Related**: `navigation_safety_core` SAFETY_BOUNDARY.md (re-exported core boundary applies through transitive dependency)

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. `NavigationBloc` is a session-state machine emitting `NavigationState` value-objects consumed by the integrator's HMI. The bloc neither actuates the vehicle nor closes a control loop.
**No L2+ claim.** Any handover-class or supervision-class deployment requires the integrator to add their own driver-attention monitoring, take-over-request signalling, and minimum-risk-manoeuvre fallback per L2+ standards.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are session-state transitions plus advisory alert vocabulary surfaced through the integrator's HMI. No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary. The 0.8.0 throttle integration at `_onSafetyAlert` modulates display-density per profile; it does not gate severity-class.
**Integrator responsibility**: integrator performs the hazard analysis and decides the final ASIL classification for their integration.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither feature nor control; it delivers session-state and alert events the integrator HMI renders. SOTIF triage is performed by the integrator at their HMI scope.
**Severity-not-profile invariant** (load-bearing, inherited verbatim from `navigation_safety_core` SAFETY_BOUNDARY.md §6): alert visibility, severity ordering, and plane-allocation priority MUST be **severity-driven, never profile-driven**. The 0.8.0 throttle integration preserves this invariant by construction: the throttle modulates density per profile, never gates severity-class; critical alerts always fire regardless of in-window count.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at package boundary.** The bloc consumes typed `NavigationEvent` value-objects and emits typed `NavigationState` value-objects. No external data ingress at this layer; no network surface; no over-the-air update surface.
**Integrator responsibility**: integrator who wires external sources (sensor / cloud / fleet) into `SafetyAlertReceived` events is the consumer-side WP.29 touchpoint owner.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.** Japanese-domestic certification is integrator-class concern. Per the inherited `navigation_safety_core` boundary record §5: *"Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface."*

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete locus** (0.8.0 integration):
- `lib/src/bloc/navigation_bloc.dart` `_onSafetyAlert` — the per-profile `AlertDensityThrottle` is consulted BEFORE the state emit; when the throttle returns false (cap exceeded, non-critical), the bloc returns without emitting state; when the severity is `AlertSeverity.critical`, the throttle's documented critical-bypass invariant returns true regardless of in-window count, so the state always emits for critical alerts. Severity drives whether-to-fire; profile drives only the per-class density cap.
- `lib/src/bloc/navigation_bloc.dart` `_canUpdateSeverity` (unchanged from prior versions) — preserves severity-monotone updates: a lower-severity alert never replaces a higher-severity active alert.

**Operational consequence**: the 0.8.0 wiring is a density modulator on the display path, not a severity gate. Per-profile differentiation enters via `AlertDensityThrottle` (alerts/min cap with critical-bypass invariant) and `AlertExplainer` (verbosity, locale), never via the severity-class path.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design** per D-VGC188-1.
**Concrete reasoning**: `NavigationBloc` emits state transitions consumed by the integrator HMI. The bloc holds no actuator authority; the driver hears / sees the alert and decides response. The 0.8.0 explainer integration replaces the free-form `message` string with the per-(condition, profile) action string when both are supplied — the action vocabulary remains advisory-mood (per `AlertExplainer` source: *"Action verbs are advisory ('reduce' / 'avoid' / 'maintain'), never imperative-on-control"*), and speed numbers remain published reference points, not system-enforced limits.

## 8 — Integrator-side driver-facing loom (D-VGC189-1; new in 0.8.0)

**Operational discipline**: *the throttle protects the driver from advisory-tier desensitization; the critical-bypass invariant preserves credibility.*

**What HER experiences when this package fires (0.8.0)**:
- HER receives an alert that *arrives in time* — when an alert is permitted by the per-profile throttle and reaches the HMI (the threshold layer in `navigation_safety_core` decides whether the underlying condition crosses the per-profile fire-threshold; the integration here gates density at the rendering boundary).
- HER receives an alert that *makes sense* — when a road-surface condition + profile pair is supplied, the bloc resolves the per-(condition, profile) action via `AlertExplainer.forConditionAndProfile`, replacing free-form text with action-coupled text in the driver's register.
- HER receives an alert that *is calm enough to ignore safely* — the per-profile alerts/min cap drops advisory-tier alerts that would crowd attention beyond HER driver-class threshold; critical alerts always preserved.
- HER agency preserved: the bloc emits state for the HMI to render. The bloc does not actuate the vehicle.

**Self-observation surface**: when a `LoomFitTelemetry` instance is supplied to the bloc, the integration emits one telemetry record per `shouldFire` decision (`fired` / `droppedByThrottle` / `criticalBypass` / `coldStart`) so the consuming-app analytics layer can ask *did the loom fit each driver-class?* and tune per-profile caps when calibration data warrants. The package does not classify "fit" vs "misfit" itself. Detection lives in the consuming app's analytics layer; the integrator owns the privacy-class boundary.

**Audible-to-edge-developer**: integrator reading `NavigationBloc` constructor today sees three optional parameters (`profile`, `throttle`, `telemetry`) — each defaults to null preserving pre-0.8.0 back-compat. The 0.8.0 wiring is opt-in at the integrator's choice; an integrator that supplies no profile sees no behavioural change from 0.7.0.

## 8.1 — GlanceBudgetTracker integrator-side advisory loom (new in 0.9.0)

**Anchor**: NHTSA Phase 2 Driver Distraction Guidelines (NHTSA-2010-0053; widely cited 12-second total off-road glance budget per task; published-anchor).

**Operational discipline**: *the tracker reports cumulative off-road glance consumption against the published budget so an integrator HMI can lighten attention demand before the budget is exhausted; the package supplies the substrate, the integrator owns the surface.*

**Concrete locus**: `lib/src/glance_budget_tracker.dart` `GlanceBudgetTracker.record(GlanceEvent)` consumes integrator-supplied glance events; emits `BudgetWarning` (default 75% consumed) and `BudgetExhausted` (100% consumed) records on a broadcast `budgetEvents` stream. Reset via `reset(BudgetResetReason)` is integrator-explicit only.

**Caution-add-only invariant** (load-bearing): consumed-budget never decreases between `record()` calls within a trip. `record()` only DECREASES (or holds) `remainingBudget`; never INCREASES it. A debug-mode runtime assert verifies the non-decrease invariant; the assert is elided in release builds per Dart `assert` semantics, but a regressing change would fail loudly in tests. Reset is the only operation that resets `remainingBudget`, and it does so by integrator-explicit request — preserving the within-trip caution-add-only invariant while permitting fresh-trip cycles. Auto-relax-on-cooldown is intentionally absent at v1.

**Severity-not-profile invariant preserved**: the tracker is timing-class only. It supplies a substrate the integrator may use to modulate display-density / voice-pace; it does not adjust score floors or severity tiers. Critical alerts in `NavigationBloc` retain their critical-bypass invariant regardless of glance-budget state.

**Driver-always-drives invariant preserved**: the tracker is reporting-only. It mounts no actuator, suppresses no input, locks no driver out. The driver always drives; the tracker only reports.

**What the driver experiences when this package fires (0.9.0)**: when the integrator has wired a `GlanceBudgetTracker`, the integrator's HMI can simplify display / soften voice / extend dwell-times as the budget approaches exhaustion — closing the cognitive-load gap between *alert arrives in time* and *alert arrives at a moment the driver has attention to receive it*.

## 8.2 — AlertExplainerExpandableSheet driver-facing loom (new in 0.9.0)

**Operational discipline**: *the explainer sheet ships a per-cohort default expansion policy at the package boundary so the integrator-developer is not required to invent one. Each driver-class receives the explainer at the verbosity their cohort default expects.*

**Concrete locus**: `lib/src/widgets/alert_explainer_expandable_sheet.dart` `AlertExplainerExpandableSheet` consumes `AlertExplainer.forConditionAndProfile` from `navigation_safety_core` 0.10.0 substrate. Two states: collapsed (source-line provenance + expand affordance) / expanded (action text VERBATIM + verbosity name + locale tag + provenance full-form).

**Per-cohort default expansion** (UNVERIFIED-magnitude design-default-hypothesis):
- `ageingRural`, `foreignTouristSnowZone`, `noviceUrban` -> default-EXPANDED (cognitive-load support; trust-attribution support; low-experience cognitive support).
- `agriculturalForestry`, `snowZoneExperienced`, `professional` -> default-COLLAPSED (experienced / terse-expectation cohorts).

Per-instance override via `defaultExpanded` field. Optional `onExpansionChanged` callback for integrator analytics.

**Article 17 (β) verbatim-relay invariant** (load-bearing): the `action` text from `AlertExplainer.forConditionAndProfile` is preserved VERBATIM in BOTH states. The collapsed state HIDES the expanded section but does not paraphrase or truncate the action text. Expanded state renders the action text exactly as the explainer returned it.

**Driver-always-drives invariant preserved**: the widget is presentation-class only. It renders information; it does not actuate the vehicle or modify any driver-control surface. Action verbs in the rendered text remain advisory-mood per `AlertExplainer` source discipline.

**Severity-not-profile invariant preserved**: the widget renders at the same severity-class regardless of expansion state. Severity gating happens upstream in `NavigationBloc`; this widget does not modify severity.

## 9 — Cross-references

- `lib/src/bloc/navigation_bloc.dart` — `_onSafetyAlert` 0.8.0 throttle + explainer + telemetry integration
- `lib/src/bloc/navigation_event.dart` — `SafetyAlertReceived` 0.8.0 fields: `condition`, `ambientThreshold`
- `lib/src/bloc/navigation_state.dart` — `NavigationState.alertCondition` 0.8.0 field
- `lib/src/glance_budget_tracker.dart` — 0.9.0 `GlanceBudgetTracker` substrate (NHTSA Phase 2 12-second total off-road glance budget; caution-add-only)
- `lib/src/widgets/alert_explainer_expandable_sheet.dart` — 0.9.0 `AlertExplainerExpandableSheet` widget (per-cohort default expansion; Article 17 (β) verbatim-relay both states)
- `navigation_safety_core` SAFETY_BOUNDARY.md (re-exported core boundary applies; severity-not-profile invariant inherited verbatim)
- LICENSE: BSD-3-Clause

---

**Boundary record authored** by AAA (automotive-adas-analyst) under VAA-as-SEO operational pen authorization. Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
