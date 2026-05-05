# driving_consent — Safety-Class Boundary Record

**Package**: `driving_consent`
**Version**: 0.4.0 (instrumentation-class consent surface; additive over 0.3.0)
**Boundary record version**: 1.1
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-05
**Anchor**: driver-facing-loom-as-default architectural discipline (per-package boundary record per AAA spawn-50 precedent)

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's `ConsentService` interface answers the question "may this purpose-class data flow from this driver's vehicle to a downstream consumer?" with one of three states (granted / denied / unknown). The driver chooses; the package records and gates.
**No L2+ claim.** The package emits no actuator signal and holds no automation. Per-purpose, per-jurisdiction consent records are pure data; the consuming integrator decides whether to dispatch the data to a fleet aggregator, a crash-data sink, or any other downstream receiver. The package is the *gate*, not the *driver*.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: `driving_consent` produces a binary decision at a privacy boundary — *grant* / *deny*. No safety-critical assertion is added at this layer; consent decisions are policy-class, not control-loop-class. The package exposes a `ConsentService` interface with `requestConsent`, `revokeConsent`, `consentStatus`, plus an in-memory implementation; integrators provide their own persistence-class implementation. No actuator authority is exposed.
**Integrator responsibility**: any integration where consent gates a control loop (e.g. an automated emergency-data upload that would otherwise interlock vehicle behavior) requires the integrator to perform fresh ASIL classification at the closed-loop boundary. The package's contract is QM and refuses to imply otherwise.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither feature nor control; it delivers a privacy-class gate the integrator queries before initiating any data egress. The driver makes the consent decision; the integrator queries the consent state; the data either flows or does not.
**Honesty discipline at adapter boundary** (SOTIF-class operational discipline):
- **UNKNOWN equals DENIED** (`ConsentStatus.unknown` semantics in `consent_record.dart`): the package treats the absence of an explicit grant as a denial. The integrator that has never asked the driver cannot assume permission. *Jidoka* discipline: the line stops itself when consent is unknown; the human (driver) restarts it. **Extension at v0.4.0**: the same semantics extend to instrumentation-class purposes — `InstrumentationService.recordEvent` throws `StateError` when consent is not explicitly `granted`. Per-purpose, not blanket.
- **Per-purpose, not blanket** (`ConsentPurpose` enum): the package decomposes consent into purpose-class buckets. v0.3.0 set: `fleetLocation` / `weatherTelemetry` / `diagnostics`. v0.4.0 instrumentation-class additions: `alertExperienceInstrumentation` / `voiceExperienceInstrumentation` / `cohortCalibrationInstrumentation` / `tripContextInstrumentation`. The driver grants alert-instrumentation without granting voice-instrumentation; the gate stays per-purpose. Blanket consent is forbidden by the API surface itself.
- **Per-jurisdiction posture** (`Jurisdiction` enum): the package surfaces a jurisdiction-class label so integrators can branch on regulatory regime (GDPR / CCPA / APPI / other). The package does not invent legal interpretations; it surfaces the label so the integrator's compliance-class adapter can route appropriately.
- **Revocability per session**: the consent record is mutable; `revokeConsent` flips a previously-granted purpose to denied. The integrator's downstream pipeline observes the revocation and stops the data flow at its next gate-check. There is no "permanent grant" surface in the API.
- **Pluggable storage interface** (`ConsentService` + `InstrumentationService` abstract): the package does not lock the integrator into a specific persistence backend. The in-memory implementations (`InMemoryConsentService` / `InMemoryInstrumentationService`) are for tests; production integrators implement their own (encrypted at rest, jurisdiction-appropriate retention, etc.). Storage-class concerns are integrator-responsibility. The in-memory instrumentation service carries an explicit *not for production* comment at the top of its source file.
- **On-device default at v0.4.0**: instrumentation-class data flows are scoped *on-device* by default. The four new purpose-class enum values gate feedback-class loops the driver's own profile uses for next-trip calibration. Off-device data flows (integrator-aggregated / maintainer-class aggregation) are reserved for v0.5+ separate substrate-class decisions and are not opened by v0.4.0.
These six disciplines collectively form the package's SOTIF-class advisory-honesty posture at the privacy-class gate boundary.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **integrator-class; package boundary minimal but adjacent to vehicle data flow.**
**Status**: **out of scope at this package's boundary, but the consent surface gates flows that fall under WP.29 R155 review at integration time.**
**Concrete WP.29 surface at this package**:
- Inputs: purpose-class enum value, jurisdiction-class enum value, status-class enum value. No network I/O at this package layer.
- Outputs: `ConsentRecord` value-objects; status query results. No external sink at the package boundary; integrators dispatch records to whatever persistence they choose.
- Authentication: none at package layer; the consuming integrator authenticates the driver and presents the consent surface; the package records the result.
- Input validation: enum-class inputs only; no parsing of external bytes (no JSON / no protobuf / no YAML / no binary).
- Privacy: the package is *the privacy primitive itself*. Records contain purpose-class + jurisdiction-class + status-class + timestamp; no PII is in scope at this package's API.
- Supply-chain: depends on `equatable` only. Single dependency; reviewed.

**WP.29-class operational discipline**: integrators deploying this package perform WP.29 R155 audit at the *integrator's* data-egress boundary. The package's role is to ensure that egress gate has an authoritative consent answer to query; the package does not gate the egress pipe itself.

## 5 — JIS / JASO conformance

**Conformance status**: **applies at the integrator's HMI surface, not at this package.**
**Reasoning**: Japanese-region consent UX surfaces in the integrator's privacy-disclosure HMI; this package emits the consent decision but does not specify display-class signage / icon-class HMI vocabulary that JIS / JASO standards regulate. Where a JIS / JASO standard regulates privacy-disclosure HMI directly, the integrator owns the audit at deployment.
**APPI specifics**: the package's `Jurisdiction.appi` enum value flags Japan's Act on the Protection of Personal Information regime; integrators querying this label adjust their disclosure surface to the APPI consent-class disclosure requirements (purpose specificity, retention period disclosure, third-party transfer disclosure). The package surfaces the label; the integrator owns the disclosure.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: consent decisions are gated by `ConsentStatus` (granted / denied / unknown) and `ConsentPurpose`. Driver profile (snowZoneExperienced / ageingRural / foreignTouristSnowZone / etc.) does not enter the gate decision; consent is per-purpose, per-jurisdiction, not per-profile. A foreign-tourist driver and a snow-zone-experienced driver receive the same consent-gate semantics; the disclosure surface in the integrator's HMI may render in profile-aware vocabulary, but the gate state itself is profile-blind. *Severity-class (status) decides whether/what; profile only decides how the disclosure is rendered.*
**Composition pattern**: integrator HMI presents the consent surface in profile-aware language → driver chooses → package records purpose-class + jurisdiction-class + status-class. Profile awareness lives upstream at the rendering layer, never at the gate.
**Extension at v0.4.0 (instrumentation-class)**: the instrumentation gate is profile-blind by the same discipline. `InstrumentationService.recordEvent` reads only the consent status for the requested purpose; it does not inspect `driverProfile` to permit or deny the call. The `driverProfile` field carried in event subtypes (`AlertFired.driverProfile`, etc.) is *payload* used by the integrator's downstream calibration loop, never gate input. A foreign-tourist-snow-zone driver's instrumentation events are recorded under the same gate semantics as a default-profile driver's; HMI rendering may differ, the gate does not.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: the package mounts no actuator. Outputs are `ConsentRecord` value-objects + boolean gate answers + (v0.4.0) `InstrumentationEvent` records read back via `readEvents`. The driver decides whether to grant; the integrator decides whether to dispatch downstream; the driver always drives. The consent-gate is *upstream* of any actuator-class flow; the gate's only authority is to refuse data egress, not to alter vehicle behavior.
**Axis anchor**: per the unit's driver-sovereignty axis substrate — driver is subject not object. The driver's consent is *the driver's*; the package preserves the driver's right to revoke per session. The gate enforces UNKNOWN = DENIED so a silent integrator cannot accidentally harvest data the driver never authorized.
**Extension at v0.4.0 (instrumentation-class)**: instrumentation is **feedback-class, not control-loop-class**. The events recorded under the four new purpose classes are read back by the driver's own profile-default calibration; they never enter a control loop. `readEvents` returns chronological records; `setRetention` bounds storage; `deleteAllEvents` lets the driver wipe the history. None of these operations alter vehicle behavior. The driver continues to perform the dynamic driving task at all times.

## 8 — Driver-facing loom

**What the driver experiences when this package fires**: *consent surface that respects every driver's right to choose what data flows from her vehicle to fleet aggregation, with revocability per session.* When `driving_consent` fires through an integrator HMI:
- The driver sees a per-purpose disclosure (e.g. "Share vehicle position with fleet aggregation server for snow-road hazard detection?") — not a blanket "agree to everything" toggle.
- The driver chooses *grant* or *deny* per purpose; the choice is recorded with purpose, jurisdiction, and timestamp.
- The driver can revoke a previously-granted purpose at any session boundary; the integrator's downstream pipeline observes the revocation at its next gate-check and stops the flow.
- The driver never has data flow under UNKNOWN status — the silent default is DENIED, not GRANTED.

**Extension at v0.4.0 — instrumentation-class disclosure**: the integrator HMI surfaces a distinct disclosure for each instrumentation-class purpose. Sample disclosure copy (recommended; integrator owns final wording):

> *"Help your navigation get better at fitting you. We can keep a small on-device record of how alerts and voice guidance work for you, so the app can fine-tune itself for your next trips. The record stays on this device. You can delete it at any time. You can change your mind and turn it off at any time."*

This disclosure is per-purpose; the four instrumentation-class enum values render as four toggles, not one umbrella switch. The default scope at v0.4.0 is *on-device*; the disclosure says so explicitly so the driver does not infer off-device flow that the package does not open.

**Sakichi reading**: the loom is *the gate that stops the line when consent is uncertain, never assumes permission, and respects the driver's right to change her mind*. The privacy-class gate matches the safety-class loom in spirit: a thread that has not been authorized cannot be woven into the fleet aggregation. The driver's decision is constitutive of the data flow; the integrator is the translator, not the source.

**Audible-to-edge-developer**: integrator reading `ConsentService` API today sees the per-purpose / per-jurisdiction / per-status decomposition surfaced explicitly + the UNKNOWN = DENIED *Jidoka* default documented in dartdoc + the in-memory implementation provided as a test-class scaffold and *never* recommended for production. Nothing patronizes the developer; the gate semantics are explicit at the surface.

**Driver-facing-loom field**: this section is the canonical driver-facing-loom declaration for `driving_consent` 0.4.0. Subsequent versions update this field on material changes to the privacy-class surface (new purpose classes, new jurisdiction classes, revocation-protocol changes, etc.). The v0.4.0 update extended the surface with four instrumentation-class purposes scoped on-device by default; off-device data flows for instrumentation-class purposes remain reserved for v0.5+ separate substrate-class decisions.

**Driver-impact chain (≤4 hops)**:
```
driver consent decision (HMI surface in integrator)
  -> ConsentService.requestConsent / revokeConsent (this package)
    -> integrator's data-egress gate (consent state queried)
      -> data flows or does not -> driver's privacy preserved
```
Four hops; HER (the driver whose data the consent governs) is terminal beneficiary; satisfies HER-trace ≤4-hop discipline.

## 9 — Cross-references

- `lib/src/consent_record.dart` (`ConsentStatus` / `ConsentPurpose` / `Jurisdiction` enums; `ConsentRecord` value-object). v0.4.0: `ConsentPurpose` extended with four instrumentation-class values.
- `lib/src/consent_service.dart` (`ConsentService` abstract interface)
- `lib/src/in_memory_consent_service.dart` (test-class implementation; not for production use)
- `lib/src/instrumentation_event.dart` (v0.4.0; sealed `InstrumentationEvent` parent + four subtypes: `AlertFired` / `VoicePaceAdjusted` / `CohortMultiplierObserved` / `TripContextCaptured`; supporting enums: `AlertSeverity` / `AlertDismissalState` / `VoicePaceAdjustmentReason` / `CohortMultiplierClass` / `ObservedFitClass` / `VehicleClass` / `PassengerPresenceClass` / `TimeOfDayClass` / `ConsecutiveDrivingDayClass` / `DriverProfileClass`)
- `lib/src/instrumentation_service.dart` (v0.4.0; `InstrumentationService` abstract interface; `recordEvent` / `readEvents` / `getRetention` / `setRetention` / `deleteAllEvents` / `pruneExpired` / `driverPseudonym`)
- `lib/src/in_memory_instrumentation_service.dart` (v0.4.0; test-class implementation; **not for production**; explicit comment at file top)
- `pubspec.yaml` `version: 0.4.0`
- LICENSE: BSD-3-Clause (matches the rest of SNGNav)
- AAA bylaws Article 17 (β) safe-default boundary
- PHIL-001 boundary preserved: `driving_consent` is the privacy primitive; it is **not** a crash-data-harvester; the package boundary explicitly refuses crash-class data routing.
- Composition: `driving_consent` upstream gate → integrator's data-egress pipeline → fleet aggregation or no aggregation per consent state. v0.4.0: the same gate composes upstream of the integrator's instrumentation aggregation pipeline (an `AlertInstrumentationGateway` pattern is sketched in `README.md`).
- Sample sngnav-app integration: integrator wires `InstrumentationService` instance behind a per-feature gateway; gateway calls `recordEvent` only after the corresponding consent purpose is granted; the integrator handles `StateError` defensively as a hard refusal.
- GDPR Article 7 (conditions for consent), CCPA Section 1798.120 (right to opt-out), APPI Article 17 (consent for personal information acquisition) — three regimes the `Jurisdiction` enum surfaces for integrator-class branching.

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization. Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear (consent surface respects every driver-class equally; UNKNOWN = DENIED protects the driver who has not yet been asked).
