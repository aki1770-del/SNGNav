# navigation_safety_core — Safety-Class Boundary Record

**Package**: `navigation_safety_core`
**Version**: 0.11.7 (first written for 0.10.0)
**Boundary record version**: 1.4 (0.11.7: the vehicle-class refusal in section 7.2 covers every threshold field; corrections in sections 1, 3, 5, 6, 7, 7.1, 7.3, 8 and 9)
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-05; revised for 0.11.7
**Anchor**: D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
**Related**: README.md §Standards mapping + KNOWN_LIMITATIONS.md §Standards mapping (current advisory framing) + LICENSE BSD-3-Clause

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's surfaces inform the driver but **never actuate the vehicle and never close a control loop**.
**No L2+ claim.** Any handover-class or supervision-class deployment requires the integrator to add their own driver-attention monitoring, take-over-request signalling, and minimum-risk-manoeuvre fallback per L2+ standards. See README.md §What this is NOT.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package outputs are advisory-class threshold configuration + alert vocabulary + density-throttle policy. No control authority. No ASIL-A through ASIL-D claim asserted at the package boundary.
**Integrator responsibility**: the integrator performs the hazard analysis and decides the final ASIL classification for their integration. The package's wording discipline is consistent with QM at the application layer.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package does not deliver an automated driving feature; it delivers advisory threshold + vocabulary substrate consumed by integrator HMI surfaces. SOTIF triage is performed by the integrator at their HMI scope where the alert is rendered.
**Equal-dignity invariant** (load-bearing): per README.md §Equal-dignity invariant — alert visibility, severity ordering, and plane-allocation priority MUST be **severity-driven, never profile-driven**. Per-profile differentiation belongs in verbosity, locale, and density-cap; it MUST NOT enter the visibility or preemption path. This invariant is the package's SOTIF-class operational discipline.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **none at package boundary.** The package consumes only typed value-objects (`DriverProfile`, `DriverState`, `DriverContext`, `DrivingContext`); no external data ingress at this layer. No network surface; no over-the-air update surface; no key-management surface.
**Integrator responsibility**: any integrator who feeds external data (sensor / cloud / fleet) into the package's `DrivingContext` is the consumer-side WP.29 touchpoint owner. Integrator declares cybersecurity scope at their layer; the package does not pre-empt that declaration.

## 5 — JIS / JASO conformance

**Conformance status**: **not mapped at this scope.**
**Reasoning**: Japanese-domestic certification is integrator-class concern. Per README.md §Standards mapping: *"Consult a qualified Japanese-domestic functional-safety partner before any IVI-vendor or OEM-pilot integration that targets the Japanese-domestic certification surface."*
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`): tracks JIS / JASO standard updates relevant to advisory-class navigation packages; surfaces relevant publication deltas to AAA at next monthly cycle.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design** per AAA bylaws Article 17 (β) safe-default boundary.
**Concrete locus**:
- README.md §Equal-dignity invariant
- KNOWN_LIMITATIONS.md §Equal-dignity invariant: severity-driven, not profile-driven
- CHANGELOG.md 0.4.2 entry, founding declaration: *"plane-allocation priority MUST be severity-driven, never profile-driven"*
- 0.4.2 founding commit `61b06e3` (per VAA spawn -29 carry-forward MEMORY)

**Operational consequence**: load gates DELIVERY MODE not severity. Per-profile differentiation lives in `AlertExplainer` (verbosity, locale) + `AlertDensityThrottle` (per-profile alerts/min cap with critical-bypass invariant) — never in the visibility or preemption path.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete locus**:
- README.md §Standards mapping: *"the driver performs the dynamic driving task at all times; the package's surfaces inform the driver but never actuate the vehicle and never close a control loop"*
- README.md §What this is NOT: *"Action verbs in `AlertExplainer` are advisory; speed numbers are published reference points, not system-enforced limits. The driver retains full control authority."*
- `lib/src/alert_explainer.dart` class documentation, advisory-mood discipline: *"Action verbs are advisory ("reduce" / "avoid" / "maintain"), never imperative-on-control … This is a Pure Dart, advisory-only surface. It does not actuate the vehicle."*

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
  The rolling window is shared across severities: every alert that
  fires takes a slot, critical and info alike, and the cap does not
  rank a warning above an info alert. A warning can therefore be
  dropped because info or critical alerts fired shortly before it
  (measured with the `ageingRural` default cap of 1.2: two info
  alerts, or two critical alerts, 10 s apart, then a warning 10 s
  later: the warning is dropped).
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
  The stream carries one record per call to `LoomFitTelemetry.record`.
  `AlertDensityThrottle` does not call it, so an integrator who wants
  one record per `shouldFire` decision records it at the seam where it
  fires alerts, as the class documentation shows (outcomes: `fired`,
  `droppedByThrottle`, `criticalBypass`, `coldStart`); the
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

## 7.2 — Vehicle-class threshold-override surface (0.9.0)

This section addends the safety-class boundary for the vehicle-class
threshold-override surface added in 0.9.0
(`VehicleClassProvider` + `VehicleThresholdOverrides` +
`DrivingContext.vehicleClassToken`).

**Caution-add-only invariant**: vehicle-class adjustments may make
warning thresholds fire EARLIER than the per-profile baseline + the
live-context floor; NEVER later. This, and the severity-not-profile
invariant below, are refused in every build mode, in two places.
`VehicleThresholdOverrides.validated(...)` probes each registered
transform against a finite battery of baselines and throws
`ArgumentError` at registration when any probe breaks either
invariant; the whole registry is refused. On the drive path,
`VehicleThresholdOverrides.applyOverrideForToken` checks the produced
config again and never throws: each field that breaks an invariant
is reset to its baseline value and reported, every other field of
the override is kept, and the result is always a config that a fully
legal transform could have produced. A transform that throws is
refused whole: the baseline is returned and the error is reported.
Negative-test coverage in `test/vehicle_threshold_overrides_test.dart`
and `test/vehicle_threshold_overrides_all_fields_test.dart` confirms
both refusals on relaxing warning floors, on a changed score floor,
and on changes in either direction to the critical thresholds, the
info thresholds and the cap override; `tool/release_mode_proof.dart`
exercises the drive path with assertions elided.

**Severity-not-profile invariant** (load-bearing per §6 above):
vehicle-class tunes warning TIMING only (warn-earlier-floors). An
override may not change any other threshold field, in either
direction: the score-floor tiers (`safeScoreFloor` /
`infoScoreFloor` / `warningScoreFloor`), the critical thresholds
(`criticalVisibilityMeters` / `criticalTemperatureCelsius`), the info
thresholds (`infoVisibilityMeters` / `infoTemperatureCelsius`), or
the alerts-per-minute cap override (`alertsPerMinuteCapOverride`,
where `null` must stay `null` and `NaN` counts as a change). A tighter
value is not safe by construction either: a critical alert bypasses
the density cap but still takes a slot in its rolling window, info
alerts share the cap with warnings, and a transform receives no
`DriverProfile`, so a cap it writes replaces the per-profile default
with a constant that ignores the driver. Through 0.11.6 the critical
thresholds, the info thresholds and the cap override were checked by
neither and were applied as written; from 0.11.7 an override that
tightened one of them has that field reset to the baseline. This
preserves the existing severity-driven (not profile-driven, not
vehicle-class-driven) plane-allocation discipline. The vehicle-class
dimension lives entirely in the threshold-tuning layer; it does NOT
enter the visibility / preemption / severity-ordering paths.

**Driver-always-drives invariant** (load-bearing per §7 above):
`VehicleClassProvider` returns advisory tokens consumed for
threshold tuning. It does NOT actuate the vehicle, NOT close any
control loop, NOT modulate alert severity. Tokens are advisory
strings, NOT control inputs: returning `'kei-car'` does not change
vehicle behaviour, it only sharpens the threshold-tuning floor for
the kei-car cohort. The driver retains full control authority.

**Built-in `'kei-car'` default**: ships via
`VehicleThresholdOverrides.withKeiCarDefault()`. Deltas are
**design-default hypotheses** pending field-measurement validation;
see `CHANGELOG.md` 0.9.0 entry for the UNVERIFIED-magnitude flag and
the kei-car-class calibration-validation follow-up note.

**ASIL-QM advisory** per §2 (no functional-safety claim asserted at
the package boundary). **WP.29 touchpoint** at integrator's
analytics boundary, not at this package (per §4; the
`VehicleClassProvider` interface is consumer-implemented; the
package consumes only the typed token at this layer).

## 7.3 — DriverState-axis scaffolding (0.10.0)

This section addends the safety-class boundary for the DriverState-
axis scaffolding added in 0.10.0 (`CircadianPhase` +
`SessionStateProvider` + `SessionState` + `CumulativeFatigueClass` +
`ConfidenceProvider` + `Confidence` + four new optional named
parameters on `NavigationSafetyConfig.forDriverContext`). All three
inputs compose as caution-adding adjustments AFTER the trait
baseline, the live-context layering, the vehicle-class override, AND
the existing state-delta.

**Caution-add-only invariant**: circadian-phase + session-state
adjustments may make warning thresholds fire EARLIER than the
per-profile baseline + live-context + state-delta floor; NEVER
later. Both floors, the multiplier `>= 1.0` (circadian) and the
visibility lift `>= 0` (session-state), hold in every build mode.
The two inputs are closed enums whose values are fixed inside this
package: every `CircadianPhase` multiplier is between 1.0 and 1.5,
and the `CumulativeFatigueClass` lifts are 0, 25, 50 and 100 m, so no
caller can supply a relaxing value. `forDriverContext` also applies a
circadian result only when it raises the warning visibility floor,
and a fatigue lift only when it is positive; those two checks are
ordinary `if` statements, not assertions, so release builds keep
them. Its debug-mode assertions additionally flag a multiplier or
lift edited below its floor inside this package; no public input can
make them fire, and no test does. `test/circadian_phase_test.dart`
checks that every multiplier is `>= 1.0`;
`test/session_state_provider_test.dart` checks that `rested` adds no
lift and that the lift rises with each fatigue class; and
`test/navigation_safety_config_driver_state_inputs_test.dart` checks
that the warning visibility floor stays at or above the profile
baseline across the 16 phase, fatigue and confidence combinations it
runs, that the critical thresholds are preserved, and that an
unconfirmed `Confidence.high` never changes the cap. The
cap-override-with-confirmation pattern (#30) is the ONLY exception
to the warn-thresholds-only-add-caution rule and applies only to the
alerts-per-minute cap (rate-limit), never to the warning visibility
/ temperature floors.

**Severity-not-profile invariant** (load-bearing per §6 above): all
three inputs tune warning TIMING (warn-earlier-floors) + alert
DENSITY (cap modification under #30) only. They do NOT modify the
score-floor tiers (`safeScoreFloor` / `infoScoreFloor` /
`warningScoreFloor`), the critical thresholds, or the
critical-bypass behaviour (`AlertSeverity.critical` always fires
regardless of cap). The DriverState-axis scaffolding lives entirely
in the threshold-tuning + density-rate-limit layer; it does NOT
enter the visibility / preemption / severity-ordering paths.

**Driver-always-drives invariant** (load-bearing per §7 above):
`SessionStateProvider` and `ConfidenceProvider` return advisory
signals consumed for threshold tuning. They do NOT actuate the
vehicle, NOT close any control loop, NOT modulate alert severity.
`CircadianPhase` is a purely-typed advisory enum carrying no
side-effect surface. The **cap-override-with-confirmation pattern**
explicitly encodes the driver-always-drives invariant for #30:
`Confidence.high` does NOT auto-loosen the alerts-per-minute cap;
the integrator must build a confirmation surface and set
`isHighConfidenceConfirmed = true` ONLY after the driver has
affirmatively confirmed. Without the affirmative confirmation flag,
`Confidence.high` is treated as `Confidence.medium` (no-op). The
confidence step returns the baseline cap for an unconfirmed
`Confidence.high` in every build mode, and the factory also carries a
debug-mode assertion that catches any divergence
(*"Confidence.high without isHighConfidenceConfirmed must NOT modify
alertsPerMinuteCapOverride; driver-always-drives invariant violated."*).
Within this package's factories the cap is loosened only through this
pattern: the system never auto-relaxes the safety cap from a
high-confidence reading alone, and from 0.11.7 a vehicle-class
override may not change the cap (section 7.2); through 0.11.6 it
could, without the driver's confirmation. An integrator that sets
`alertsPerMinuteCapOverride` directly owns that decision.

**UNVERIFIED-magnitude flags**: per-phase circadian multipliers,
per-class fatigue lifts, and confidence cap modifiers are
**design-default hypotheses** pending field-measurement validation;
see `CHANGELOG.md` 0.10.0 entry and `KNOWN_LIMITATIONS.md`
(DriverState-scaffolding section, 0.10.0) for the per-input
disclosure.

**ASIL-QM advisory** per §2 (no functional-safety claim asserted at
the package boundary). **WP.29 touchpoint** at integrator's
analytics boundary, not at this package (per §4; the
`SessionStateProvider` and `ConfidenceProvider` interfaces are
consumer-implemented; the package consumes only the typed value at
this layer).

## 8 — Driver-facing loom (D-VGC189-1)

**What HER experiences when this package fires**: *the alert that arrives in time + makes sense + is calm enough to ignore safely.* When `navigation_safety_core` fires through an integrator HMI, HER sees an alert that:
- **arrives in time** — threshold-tuned to her profile (ageingRural gets an earlier visibility-warning floor than snowZoneExperienced, 300 m against 200 m, per the `forProfile` factory; a higher floor warns earlier) AND adjusted upward for live driving conditions where they exceed the per-profile floor (`forProfileWithContext`).
- **makes sense** — vocabulary in her language (`AlertExplainer` locale-class differentiation), at action-coupled granularity (advisory verbs not raw severity codes), with the action she can take (*"reduce", "avoid", "maintain"*) coupled to the condition.
- **is calm enough to ignore safely** — `AlertDensityThrottle` per-profile alerts/min cap prevents desensitization. Critical alerts always fire (documented invariant); info and warning gates against alarm-fatigue.

**Sakichi reading**: the loom serves HER without requiring HER vigilance. HER agency is preserved (*"the driver retains full control authority"*) — the loom catches the broken thread (the unexpected snow, the dropping visibility), HER does not have to scan for it.

**Audible-to-edge-developer**: an integrator reading `AlertExplainer` source today sees the action-mood discipline + locale + verbosity mapping. Nothing in the API surface is patronizing-to-developer; the trait+state separation respects the integrator's modeling choices (Regan, Hallett & Gordon 2011-class anchoring is published-literature substrate not unit-internal vocabulary).

## 9 — Cross-references

- README.md §Standards mapping + §What this is NOT + §Equal-dignity invariant
- KNOWN_LIMITATIONS.md §Standards mapping (current advisory framing) + §Equal-dignity invariant: severity-driven, not profile-driven
- CHANGELOG.md 0.4.2 entry
- LOOMS.md (runtime-loom catalog: AlertDensityThrottle + AlertExplainer pair)
- LICENSE BSD-3-Clause
- D-VGC189-1 (driver-facing-loom-as-default architectural discipline)
- D-VGC188-1 / D-VGC188-2 (Driver Sovereignty axis + 5-test framework)
- AAA bylaws Article 17 (β) safe-default boundary

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization (spawn -50 Task 1). Subject = We / AAA. OPS-RULE-055 verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear.
