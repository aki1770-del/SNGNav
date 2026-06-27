# kalman_dr — Safety-Class Boundary Record

**Package**: `kalman_dr`
**Version**: 0.3.0 (current pub.dev release)
**Boundary record version**: 1.1 (2026-06-27 — §3 finite-position invariant PROMOTED from documented-known-limitation to ENFORCED-with-tests; §3/§8/§9 dangling `KNOWN_LIMITATIONS-class material` reference drift corrected to the in-repo enforcing tests. CT build-track, closing AAA-carried guard conditions.)
**Authoring skill**: AAA (automotive-adas-analyst); v1.1 §3 promotion by CT (build-track lead)
**Date**: 2026-05-05 (v1.0); 2026-06-27 (v1.1)
**Anchor**: driver-facing-loom-as-default architectural discipline (per-package boundary record per AAA spawn-50 precedent)

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's `KalmanFilter` produces `GeoPosition` estimates (lat / lon / speed / heading + accuracy) from a stream of GPS fixes plus a constant-velocity prediction model. When GPS drops out (tunnel, urban canyon, snow-heavy bridge canopy), the filter predicts forward and grows the covariance honestly, so the consumer sees the uncertainty grow rather than seeing a stale-but-confident position.
**No L2+ claim.** The package emits a *position estimate*; nothing about position-actuator-fusion / closed-loop control is in scope. The integrator may use the estimate to drive a map-display, a route-keeper, or an off-route detector — all advisory. Closed-loop authority (e.g. lane-keeping that consumes the position estimate) requires fresh ASIL classification at the integrator's closed-loop boundary.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: `kalman_dr` produces a numerical position estimate with declared uncertainty (`accuracy` field). The estimate is advisory; the package does not assert accuracy beyond what the covariance arithmetic produces. Numerical-safety lifecycle hardening (NaN propagation, divergence under degenerate input) is a known concern; integrators using this package in safety-class control loops perform their own numerical-stability audit at their boundary.
**Integrator responsibility**: any integration where Kalman-DR position gates a control loop (e.g. an automated emergency-stop that consumes position to decide stopping geometry) requires the integrator to perform fresh ASIL classification at the closed-loop boundary, including failure-mode analysis under tunnel-class GPS dropouts, sensor-noise-class spikes, and floating-point edge cases.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither feature nor control; it delivers a position-estimate-class advisory the integrator already plans to consume for map-display or route-following advisories. The driver reads the rendered surface; the driver decides; the driver always drives.
**Honesty discipline at adapter boundary** (SOTIF-class operational discipline):
- **Covariance grows under prediction-only** (`KalmanFilter.predict` increases P uncertainty at each call): when GPS drops, the filter does not pretend the position is still known with prior accuracy. The covariance grows, the `GeoPosition.accuracy` field grows correspondingly, and the consumer sees the honest decay. This is the package's primary SOTIF discipline.
- **GPS fusion clamps covariance under measurement**: when GPS arrives, the update step fuses prediction with measurement and reduces covariance per Kalman gain arithmetic. The recovery from prediction-only mode is honest, not ornamental.
- **Constant-velocity prediction model**: the prediction model is documented as constant-velocity (speed + heading held). The package does not pretend to model accelerations / yaw rates; the integrator wanting more sophisticated motion models implements outside the package.
- **`accuracy` field as honesty-channel**: every `GeoPosition` carries an `accuracy` value computed from the covariance. The integrator's HMI surface uses this to decide whether to render the position dot solid (high confidence) or dotted / faded (low confidence). The package surfaces honesty; the integrator renders it.
- **Finite-position invariant (ENFORCED, not merely documented)**: a non-finite (NaN / ±infinity) latitude, longitude, or accuracy can never poison the fused state nor reach a map boundary. This is now an *enforced* invariant with regression tests at every layer — not a known limitation an integrator must defend alone. The filter floors a non-finite accuracy (`_diagFromAccuracy`) and rejects a non-finite determinant (`_invertMat`); the `DeadReckoningProvider` drops a non-finite coordinate at ingest *before* the GPS-back / watchdog logic. Critically — and this is the load-bearing property — a SUSTAINED garbage stream does NOT masquerade as a live fix: because the drop sits before `_resetGpsWatchdog`, the stream is invisible to the watchdog and the system ages HONESTLY into dead-reckoning takeover and then the 500m `DeadReckoningAccuracyExceededException` "position unavailable" cap. Package tests: `test/finiteness_guard_test.dart` — the `KalmanFilter` floor + determinant guards, the ingest drop (linear + kalman), and the two `does NOT mask as live GPS` cases (DR-takeover-under-sustained-garbage + 500m-cap-under-sustained-garbage). At the SNGNav integration layer the same invariant is re-verified end-to-end: `test/bloc/location_bloc_finiteness_guard_test.dart` (chokepoint drop + the stale-watchdog `does NOT mask as a live fix` case), `test/providers/geoclue_finiteness_guard_test.dart` (source-ingest skip + accuracy coercion), and `test/fluorite/snow_scene_3d_view_confidence_radius_nan_test.dart` (a NaN confidence-radius renders a finite max-fog scrim + a suppressed `±N m` label — no `±NaN m`). The residual numerical-safety class is the NaN-on-pole Jacobian singularity under *closed-loop* integrator use, which stays an integrator-audit item per §2 — it is NOT a non-finite-input gap (that surface is now closed and tested).
These disciplines collectively form the package's SOTIF-class advisory-honesty posture.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **integrator-class; package boundary minimal.**
**Status**: **out of scope at this package's boundary.**
**Concrete WP.29 surface at this package**:
- Inputs: GPS fix value-objects (lat / lon / speed / heading / accuracy / timestamp), prediction interval `Duration`. No network I/O.
- Outputs: `GeoPosition` value-objects (lat / lon / speed / heading / accuracy / timestamp) + filter-state-class accessors. No external sink.
- Authentication: none; the package consumes GPS fixes provided by the integrator-owned location source.
- Input validation: numerical types only; out-of-range or NaN inputs are an integrator-class responsibility (the package operates on the float64 numerics it receives).
- Privacy: lat / lon stay in-process; the package emits no telemetry, performs no logging by default. PII concerns (logging coordinates) are integrator-responsibility at the integrator's logging surface.
- Supply-chain: depends on `equatable` only. Single dependency; reviewed.

**WP.29-class operational discipline**: integrators deploying this package perform WP.29 R155 audit at their location-source boundary (where GPS fixes enter the app) and at their position-consumer boundary (where the rendered position appears in the HMI or a downstream pipe). This package is the *math* between those two boundaries.

## 5 — JIS / JASO conformance

**Conformance status**: **applies at the integrator's HMI surface, not at this package.**
**Reasoning**: Japanese-region position rendering surfaces in the integrator's map / HMI; this package emits the position estimate but does not specify display-class signage / icon-class HMI vocabulary that JIS / JASO standards regulate. Where a JIS / JASO standard regulates position-class HMI directly (precision indicator class, dropout-state indicator class), the integrator owns the audit at deployment.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: position estimate is a numerical-class output. Driver profile does not enter the math; the same GPS fix sequence produces the same `GeoPosition` regardless of profile. Integrator's downstream HMI may choose to render the accuracy field in profile-aware vocabulary (e.g. wider visual margin for `ageingRural` per the per-profile rendering pattern), but the position estimate at this package is profile-blind. *Severity-class (accuracy degradation) decides whether/what to surface; profile only decides how the integrator renders.*
**Composition pattern**: `kalman_dr` numerical position estimate → integrator's map surface → profile-aware rendering (uncertainty-margin, dot-fading, etc.). Profile awareness lives at the rendering layer; the math is profile-blind.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are `GeoPosition` value-objects + filter-state accessors. The package emits no actuator signal, holds no closed-loop authority, exposes no API that gates vehicle behavior. The driver reads the rendered position; the driver decides response; the driver always drives.
**Axis anchor**: per the unit's driver-sovereignty axis substrate — driver is subject not object. The Kalman filter is honest about its own uncertainty; HER reads the honest signal at the integrator's HMI; HER decides what to do under degraded GPS.

## 8 — Driver-facing loom

**What HER experiences when this package fires**: *position estimate honest about its own uncertainty when the GPS drops in a tunnel or under snow-heavy bridge canopy.* When `kalman_dr` fires through an integrator HMI:
- HER sees HER position dot rendered with fidelity that decays gracefully when the GPS drops out (covariance grows; accuracy field reflects the growth; integrator's HMI renders the dot wider / dotted / faded).
- HER sees the position recover sharply when the GPS reacquires (Kalman update step clamps covariance; HMI tightens the rendering).
- HER never sees a stale-but-confident position pretending the GPS is still locked when it is not — the package's primary discipline is to forbid that lie.
- HER drives the dynamic driving task; the package never reaches into the actuator chain.

**Sakichi reading**: the loom is *the position estimator that admits its own uncertainty rather than fabricating confidence*. The Sakichi-class loom in this package is the covariance-growth-under-prediction discipline: when the input thread (GPS fix) breaks, the loom's output (position estimate) does not fabricate continuity; the line stops growing in confidence and lets the integrator render the honest decay. The driver decides under honest uncertainty; the package never imposes a lie on HER.

**Audible-to-edge-developer**: integrator reading `KalmanFilter` API today sees the predict / update cycle documented in dartdoc + the `accuracy` field documented as covariance-derived + the constant-velocity prediction model documented explicitly + the finite-position invariant noted as ENFORCED by the package's `test/finiteness_guard_test.dart` regression suite (§3), with the residual closed-loop NaN-on-pole class flagged for integrator audit per §2. Nothing patronizes the developer; the math discipline is explicit at the surface.

**Driver-facing-loom field**: this section is the canonical driver-facing-loom declaration for `kalman_dr` 0.3.0. Subsequent versions update this field on material changes to the position-estimate surface (new motion models, new uncertainty models, new dropout-handling discipline, etc.).

**Driver-impact chain (≤4 hops)**:
```
GPS fix sequence (integrator's location source)
  -> KalmanFilter.predict / update (this package)
    -> integrator HMI position rendering with honest accuracy
      -> driver in tunnel sees the honest decay; decides under uncertainty
```
Four hops; HER is terminal beneficiary; satisfies HER-trace ≤4-hop discipline.

## 9 — Cross-references

- `lib/src/kalman_filter.dart` (Extended Kalman Filter; predict + update cycle; covariance arithmetic)
- `lib/src/geo_position.dart` (`GeoPosition` value-object; `accuracy` honesty-channel)
- `lib/src/dead_reckoning_provider.dart` (`DeadReckoningProvider` interface)
- `lib/src/dead_reckoning_state.dart` (`DeadReckoningState` value-object)
- `lib/src/location_provider.dart` (location-source abstraction; GPS-fix entry point)
- `pubspec.yaml` `version: 0.3.0`
- LICENSE: BSD-3-Clause (matches the rest of SNGNav)
- AAA bylaws Article 17 (β) safe-default boundary
- PHIL-001 boundary preserved: `kalman_dr` is the math primitive; it is **not** a crash-data-harvester; the package boundary refuses crash-class data routing by virtue of its scope (numerical position estimation only).
- Composition: `kalman_dr` numerical estimate → integrator's map / route / off-route-detector surface → profile-aware rendering at the HMI layer.
- SDE Rule 1 numerical-safety lifecycle hardening (class-1 + class-2 owner per FDD + SDE joint scope) — the finite-position invariant is ENFORCED by `test/finiteness_guard_test.dart` (see §3); the residual NaN-on-pole Jacobian-singularity class is an integrator closed-loop audit item (§2), not a documented-but-unenforced package gap. *(kalman_dr ships no `KNOWN_LIMITATIONS.md`; the earlier "KNOWN_LIMITATIONS-class material" wording was a dangling reference, corrected here to the in-repo enforcing tests.)*

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization. Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear (position estimate respects every driver-class equally; honesty-channel via `accuracy` field is profile-blind; rendering-layer profile differentiation lives downstream).
