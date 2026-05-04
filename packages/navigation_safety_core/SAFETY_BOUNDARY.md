# navigation_safety_core — Safety-Class Boundary Record

**Package**: `navigation_safety_core`
**Version**: 0.8.0 (DEPLOY)
**Boundary record version**: 1.1 (0.8.0 addendum: `LoomFitTelemetry` driver-facing-loom field)
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-04
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
**Related**: README.md §Standards mapping (L153-168) + KNOWN_LIMITATIONS.md §Standards-mapping-current-advisory-framing + LICENSE BSD-3-Clause

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces inform the driver but **never actuate the vehicle and never close a control loop**.
**No L2+ claim.** Any handover-class or supervision-class deployment requires the integrator to add their own driver-attention monitoring, take-over-request signalling, and minimum-risk-manoeuvre fallback per L2+ standards. See README.md §What this is NOT (L170-188).

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are advisory-class threshold configuration + alert vocabulary + density-throttle policy. No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary.
**Integrator responsibility**: the integrator performs the hazard analysis and decides the final ASIL classification for their integration. The package's wording discipline is consistent with QM at the application layer.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package does not deliver an automated driving feature; it delivers advisory threshold + vocabulary substrate consumed by integrator HMI surfaces. SOTIF triage is performed by the integrator at their HMI scope where the alert is rendered.
**Equal-dignity invariant** (load-bearing): per README.md §Equal-dignity invariant (L189-197) — alert visibility, severity ordering, and plane-allocation priority MUST be **severity-driven, never profile-driven**. Per-profile differentiation belongs in verbosity, locale, and density-cap; it MUST NOT enter the visibility or preemption path. This invariant is the package's SOTIF-class operational discipline.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at package boundary.** The package consumes only typed value-objects (`DriverProfile`, `DriverState`, `DriverContext`, `DrivingContext`); no external data ingress at this layer. No network surface; no over-the-air update surface; no key-management surface.
**Integrator responsibility**: any integrator who feeds external data (sensor / cloud / fleet) into the package's `DrivingContext` is the consumer-side WP.29 touchpoint owner. Integrator declares cybersecurity scope at their layer; the package does not pre-empt that declaration.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.**
**Reasoning**: Japanese-domestic certification is integrator-class concern. Per README.md L164: *"Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface."*
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`): tracks JIS / JASO standard updates relevant to advisory-class navigation packages; surfaces relevant publication deltas to AAA at next monthly cycle.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design** per AAA bylaws Article 17 (β) safe-default boundary.
**Concrete locus**:
- README.md L189-197 §Equal-dignity invariant
- KNOWN_LIMITATIONS.md L465+ Equal-dignity invariant: severity-driven, not profile-driven
- CHANGELOG.md L146 0.4.2 founding declaration: *"plane-allocation priority MUST be severity-driven, never profile-driven"*
- 0.4.2 founding commit `61b06e3` (per VAA spawn -29 carry-forward MEMORY)

**Operational consequence**: load gates DELIVERY MODE not severity. Per-profile differentiation lives in `AlertExplainer` (verbosity, locale) + `AlertDensityThrottle` (per-profile alerts/min cap with critical-bypass invariant) — never in the visibility or preemption path.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete locus**:
- README.md L155-158 §Standards mapping: *"the driver performs the dynamic driving task at all times; the package's surfaces inform the driver but never actuate the vehicle and never close a control loop"*
- README.md L182-184 §What this is NOT: *"Action verbs in `AlertExplainer` are advisory; speed numbers are published reference points, not system-enforced limits. The driver retains full control authority."*
- `lib/src/alert_explainer.dart` L19-34 advisory-mood discipline: *"Action verbs are advisory ('reduce' / 'avoid' / 'maintain'). This is a Pure Dart, advisory-only surface. It does not actuate the vehicle."*

**Axis anchor**: per `outputs/governance_transformation/our_axis_driver_sovereignty_2026_05_03.md` §1 — driver is subject not object; the agency to choose what to do next remains with the driver. This package's surfaces are designed for that cognitive moment of choice, never around it.

## 7.1 — Driver-facing looms (0.8.0)

This section enumerates the driver-facing looms shipped at the
`navigation_safety_core` boundary. Each entry names the loom, its
operational discipline, and the SAE J3016 / ISO 26262 / SOTIF posture
under which the loom is permitted to fire.

- **`AlertDensityThrottle`** — per-profile rolling-window rate-limiter
  for advisory alerts. Operational discipline: *the throttle protects
  the driver from advisory-tier desensitization; the critical-bypass
  invariant preserves credibility of safety-critical alerts.* The
  throttle gates info / warning tiers against alarm-fatigue;
  `AlertSeverity.critical` always fires regardless of in-window count.
  Severity-not-profile invariant preserved: the throttle modulates
  density per profile, never gates severity-class. ASIL-QM advisory
  per §2.

- **`AlertExplainer`** — action-coupled (condition, action, verbosity,
  locale) tuple for each `(RoadSurfaceCondition, DriverProfile)` pair.
  Operational discipline: *the explainer ships the (condition, action)
  tuple at the package boundary so the integrator-developer is not
  silently absorbed responsibility for action-coupling.* The 36-cell
  action table sources from JAF / MLIT / NEXCO public driver-guidance
  vocabulary; advisory-mood verbs only; speed numbers are published
  reference points, not system-enforced limits. The driver retains
  full control authority. ASIL-QM advisory per §2.

- **`LoomFitTelemetry`** (new in 0.8.0) — emit-only broadcast stream
  of `LoomFitTelemetryRecord` observations. Operational discipline:
  *the telemetry surfaces calibration-class observations to the
  consuming-app's analytics layer; no driver-competence judgment.*
  The stream emits one record per `shouldFire` decision (outcomes:
  `fired`, `droppedByThrottle`, `criticalBypass`, `coldStart`); the
  schema names the loom's outcome, not the driver's response. The
  package does not classify "fit" vs "misfit" itself, does not enact
  any policy change in response, and does not harvest driver-identity
  data — detection logic, when an integrator wants it, lives in the
  integrator's analytics layer where the integrator owns the
  privacy-class boundary. An integrator that never subscribes incurs
  zero data-flow cost. SOTIF-class operational discipline: the
  observation surface enables the calibration loop that asks *did the
  loom fit the operator?* not *did the operator fail?* ASIL-QM
  advisory per §2; WP.29 touchpoint at integrator's analytics
  boundary, not at this package.

## 8 — Driver-facing loom (D-VGC189-1)

**What HER experiences when this package fires**: *the alert that arrives in time + makes sense + is calm enough to ignore safely.* When `navigation_safety_core` fires through an integrator HMI, HER sees an alert that:
- **arrives in time** — threshold-tuned to her profile (snowZoneExperienced gets earlier visibility-warning floor than ageingRural; per `forProfile` factory) AND adjusted upward for live driving conditions where they exceed the per-profile floor (`forProfileWithContext`).
- **makes sense** — vocabulary in her language (`AlertExplainer` locale-class differentiation), at action-coupled granularity (advisory verbs not raw severity codes), with the action she can take (*"reduce", "avoid", "maintain"*) coupled to the condition.
- **is calm enough to ignore safely** — `AlertDensityThrottle` per-profile alerts/min cap prevents desensitization. Critical alerts always fire (documented invariant); info and warning gates against alarm-fatigue.

**Sakichi reading**: the loom serves HER without requiring HER vigilance. HER agency is preserved (*"the driver retains full control authority"*) — the loom catches the broken thread (the unexpected snow, the dropping visibility), HER does not have to scan for it.

**Audible-to-edge-developer**: an integrator reading `AlertExplainer` source today sees the action-mood discipline + locale + verbosity mapping. Nothing in the API surface is patronizing-to-developer; the trait+state separation respects the integrator's modeling choices (Regan, Hallett & Gordon 2011-class anchoring is published-literature substrate not unit-internal vocabulary).

## 9 — Cross-references

- README.md §Standards mapping L153-168 + §What this is NOT L170-188 + §Equal-dignity invariant L189-197
- KNOWN_LIMITATIONS.md §Standards-mapping-current-advisory-framing + §Equal-dignity invariant L465+
- CHANGELOG.md 0.4.2 founding entry L146
- LOOMS.md (runtime-loom catalog: AlertDensityThrottle + AlertExplainer pair)
- LICENSE BSD-3-Clause
- D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
- D-VGC188-1 / D-VGC188-2 (Driver Sovereignty axis + 5-test framework)
- AAA bylaws Article 17 (β) safe-default boundary

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization (spawn -50 Task 1). Subject = We / AAA. OPS-RULE-055 verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
