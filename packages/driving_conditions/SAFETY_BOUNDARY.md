# driving_conditions — Safety-Class Boundary Record

**Package**: `driving_conditions`
**Version**: 0.5.0 (DEPLOY)
**Boundary record version**: 1.0
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-03
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces produce advisory road-surface classification + grip estimation + visibility degradation parameters + Monte Carlo safety scores — **all consumed by the integrator's HMI for driver presentation**, never closed-loop into the vehicle's longitudinal or lateral control authority.
**No L2+ claim.** Monte Carlo `SafetyScoreSimulator` outputs are advisory: `result.score` informs the driver via integrator HMI; the driver decides response (slow down / detour / continue). Speed inputs are observed not commanded; grip factors are estimated not enforced.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are advisory-class deterministic computation outputs (decision tree from weather → road surface; grip estimation; Monte Carlo simulation). No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary.
**Integrator responsibility**: the integrator performs the hazard analysis at their HMI scope where the safety-score is rendered to the driver. Any integration where the safety score gates a control loop (e.g. ADAS speed limiter consumption) requires the integrator to perform fresh ASIL classification at that surface — the package does not pre-empt or claim ASIL clearance.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither an automated driving feature nor a control surface; it delivers `RoadSurfaceState` + `gripFactor` + `VisibilityDegradation` + `SafetyScoreSimulator` outputs that the integrator HMI surfaces to the driver as advisory information. SOTIF triage is performed by the integrator at the HMI scope where the driver sees the advisory.
**Equal-dignity invariant**: this package does not consume `DriverProfile` or `DriverContext`. Severity-not-profile invariant applies at downstream consumer scope (`navigation_safety` 0.6.0 + integrator HMI). This package is profile-agnostic by design; severity emerges from physical computation (grip + visibility + speed) not from driver class.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **upstream consumer-side at `WeatherCondition` ingress.** This package consumes `WeatherCondition` from `driving_weather` (upstream); when the integrator's `driving_weather` consumer pulls from external feeds (NOAA / NWS / JMA / MET Norway), the WP.29 touchpoint is at that ingress not at this package's boundary. Per UPA `noaa_nws_adapter` 0.0.1 explore-phase pattern: any external-data adapter is itself the WP.29 touchpoint owner.
**Native engine surface**: `NativeSafetyScoreSimulationEngine` C FFI engine introduces a native-code surface. Integrators deploying with the native engine perform native-code-supply-chain WP.29 audit at integration time. The pure-Dart `CpuSafetyScoreSimulationEngine` is the cybersecurity-simpler default.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.**
**Reasoning**: Japanese-domestic certification is integrator-class concern. Road-surface classification vocabulary and grip-factor magnitudes are anchored to physics-of-tire-grip published research (decision-tree thresholds at lines 44-49 README.md); JIS / JASO equivalents (where they exist for road-surface vocabulary) are reconciled by the integrator at the integration certification surface.
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`): tracks JIS / JASO standard updates relevant to road-surface-classification packages; surfaces relevant publication deltas to AAA at next monthly cycle.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — at consumer-class composition.**
**Concrete reasoning**: this package is profile-agnostic by construction; severity is computed from physical inputs (grip + visibility + speed) not from driver class. The severity-not-profile invariant from `navigation_safety_core` 0.6.0 is satisfied at this package's boundary trivially — no profile axis exists here. Downstream consumers composing `driving_conditions` Monte Carlo output with `navigation_safety_core` profile-tuned thresholds inherit the severity-not-profile discipline at the composition surface.
**Composition pattern**: per README.md §Works With (L249-253) — `driving_conditions` outputs feed `navigation_safety` (downstream, where profile-class differentiation enters). The boundary is clean: physics here, profile-tuned-thresholds downstream, severity-driven HMI presentation final.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are deterministic typed value-objects (`DrivingConditionAssessment`, `SimulationResult`, `SafetyScore`) consumed by integrator code; the package emits no control signal, holds no actuator authority, exposes no API that closes a control loop. `advisoryMessage` field on `DrivingConditionAssessment` is the explicit advisory-class surface (advisory-mood text presented to driver via integrator HMI).
**Axis anchor**: per `outputs/governance_transformation/our_axis_driver_sovereignty_2026_05_03.md` §1 — driver is subject not object. Monte Carlo simulation outputs (mean score + variance + incident count) inform HER decision; never substitute for HER decision. Variance reporting is the explicit honesty-discipline at the boundary: the integrator HMI surfaces *uncertainty*, the driver retains the agency to weigh it.

## 8 — Driver-facing loom (D-VGC189-1)

**What HER experiences when this package fires**: *the safety score that says how confident the road feels right now, with honest variance.* When `driving_conditions` fires through an integrator HMI, HER sees:
- a road-surface classification (*"compactedSnow grip=0.30"*) in the language of physical condition not vendor jargon
- an advisory message (`assessment.advisoryMessage`) in advisory mood not imperative-on-control
- a safety score with variance (*"score: 0.42, variance: 0.08"*) — the variance signals to the integrator HMI when to surface uncertainty rather than confidence

**Sakichi reading**: the loom measures the road-thread (precipitation + temperature + visibility + speed) and reports the tension HER cannot directly feel. The Monte Carlo run is the loom doing the measuring; HER does not have to scan grip and visibility independently. The variance is the loom's honesty: *"this score is uncertain; confidence depends on whether your fleet-confidence input is real."*

**Audible-to-edge-developer**: integrator reading `SafetyScoreSimulator.simulate()` API today sees explicit `seed` parameter for deterministic tests, explicit `FleetConfidenceProvider` injection point for replacing the 0.8 default with real fleet data, and explicit `NativeSafetyScoreSimulationEngine` opt-in for higher throughput. Nothing patronizes the developer's modeling choices; defaults are honest (0.8 explicit baseline; not hidden).

**Driver-facing-loom field**: this section is the canonical D-VGC189-1 declaration for `driving_conditions` 0.5.0. Subsequent versions update this field on material changes to the driver-experience surface (e.g. variance reporting shape change → field update; internal Monte Carlo iteration count change → no field update).

## 9 — Cross-references

- README.md §Core Models L36+ (RoadSurfaceState decision tree + grip table) + §SafetyScoreSimulator L113-126 (Monte Carlo formula) + §Works With L249-253
- pubspec.yaml `version: 0.5.0` (canonical version-of-record; README L33 install string `^0.3.0` carries documentation drift to be reconciled at next README-pass)
- LICENSE BSD-3-Clause
- D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
- D-VGC188-1 / D-VGC188-2 (Driver Sovereignty axis + 5-test framework)
- AAA bylaws Article 17 (β) safe-default boundary
- Composition: navigation_safety_core 0.6.0 SAFETY_BOUNDARY.md (severity-not-profile invariant inherited at HMI scope)

---

**Note on documentation drift**: README.md L33 install string declares `^0.3.0` but pubspec.yaml line 6 is `version: 0.5.0`. AAA flags for next README-pass; not a safety-class boundary divergence (the safety boundary is the version-of-record per pubspec, which is 0.5.0). FDD bylaws Rule 6 spike-to-package gate covers this drift class at next package PR cycle.

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization (spawn -50 Task 1). Subject = We / AAA. OPS-RULE-055 verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
