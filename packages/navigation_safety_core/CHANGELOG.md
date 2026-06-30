# Changelog

## 0.10.5
- docs: correct stale README install pin to current version (no API change).

## 0.10.4

Conservative-on-uncertain hardening — a non-finite value must never
silently defeat a conservative alert.

- **SafetyScore (GAP-1):** `SafetyScore` now maps non-finite component
  inputs (`NaN` / `±Infinity`) to the worst-case `0` so they alert
  conservatively instead of slipping through unclamped. Without the
  guard a `NaN` overall compares `false` to every threshold in
  `toAlertSeverity` (no alert), and `+Infinity` clamped to `1` (no
  alert) — both inverting the "if uncertain, alert conservatively"
  intent.
- **NavigationSafetyConfig (GAP-2):** the constructor now rejects a
  non-finite score floor (`NaN` / `±Infinity`) with an `ArgumentError`.
  The previous `floor < 0 || floor > 1` range checks were
  NaN-permissive (`NaN` compares `false` to both bounds), so a
  non-finite floor passed construction silently and then poisoned
  `toAlertSeverity` on the *threshold* operand: `overall < NaN` is
  always `false`, so even a worst-case `overall == 0` yielded NO alert.
  This closes the same failure family as GAP-1 on the operand the
  score-side guard does not reach. Regression tests assert the
  worst-case score still alerts `critical`.

## 0.10.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.10.2 — 2026-05-10 — Pana score recovery (Theme α P4)

- Trim pubspec `description` to within the pana 60–180 character target.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.10.1 — 2026-05-10 — Vehicle-CAN composition example (j1939)

Adds an illustrative `example/can_bus_integration.dart` showing how
`navigation_safety_core` composes with the [`j1939`](https://pub.dev/packages/j1939)
package to translate SAE J1939 vehicle-bus events into a
`DrivingContext` and an `AlertExplainer` advisory action. Documents
two J1939/71 PGNs (CCVS1 0xFEF1 wheel-based vehicle speed; ET1 0xFEEE
engine coolant temperature) as composition anchors. Adds a
"Vehicle Data Integration" section to the README naming the j1939
+ NMEA 2000 cohorts as integrator-developer surfaces. No SDK source
changes; example-only release.

## 0.10.0 — 2026-05-05 — DriverState-axis scaffolding (#28+#29+#30)

Adds three additive opt-in inputs to the existing trait/state
`DriverContext` architecture (Regan-Hallett-Gordon 2011, PMC4001671)
as Wave 1 sub-bundle 2 NSC scaffolding for the #23 DriverState
complete-class graduation: time-of-day circadian-phase classification
(#28), driving-session-state with consecutive-day + cumulative-fatigue
classification (#29), and self-assessed-confidence with
cap-override-with-confirmation pattern (#30). All three compose into
the existing `forDriverContext` factory as caution-adding adjustments
applied AFTER the trait baseline AND AFTER the live-context +
vehicle-class layering AND AFTER the state-delta.

### Added

- **`CircadianPhase`** — enum partitioning the 24-hour clock into six
  phases (`earlyMorning` 04–07 / `morning` 08–11 / `afternoon` 12–15
  / `evening` 16–19 / `night` 20–23 / `lateNight` 00–03) with a
  caution-adding multiplier in `[1.0, 1.5]` exposed via the
  `CircadianPhaseMultiplier.multiplier` extension. `morning` is the
  baseline (`1.0`); `lateNight` is the cap (`1.5`,
  circadian-trough). Helper `circadianPhaseFromHour(int)` maps a
  24-hour clock hour to the corresponding phase.
- **`SessionStateProvider`** — abstract interface returning
  `SessionState? get sessionState`. The integrator owns persistence
  (consecutive-day counter across trips, day-rollover semantics,
  opt-in scope) and the privacy-class boundary; the package consumes
  only the typed value at the factory call-site.
- **`SessionState`** — immutable value class carrying
  `consecutiveDrivingDays` (integrator-tracked raw counter) +
  `cumulativeFatigue` (integrator-derived `CumulativeFatigueClass`).
- **`CumulativeFatigueClass`** — enum (`rested` 0–2 / `mild` 3–4 /
  `accumulated` 5–6 / `severe` 7+) determining the
  threshold-adjustment magnitude.
- **`ConfidenceProvider`** — abstract interface returning
  `Confidence? get confidence` AND `bool get
  isHighConfidenceConfirmed`. The two signals together form the
  cap-override-with-confirmation pattern.
- **`Confidence`** — enum (`high` / `medium` / `low`).
- **`NavigationSafetyConfig.forDriverContext`** — four new optional
  named parameters: `vehicleOverrides` (re-surfaced from 0.9.0 so
  `forDriverContext` callers can compose vehicle-class through the
  state-axis factory), `circadianPhase`, `sessionState`,
  `confidence`, and `isHighConfidenceConfirmed` (default `false`).
- Re-exported from `package:navigation_safety_core/navigation_safety_core.dart`.

### Cap-override-with-confirmation pattern (#30; load-bearing)

The `Confidence` signal modulates the alerts-per-minute cap under a
pattern that preserves the **driver-always-drives invariant**:

- `Confidence.low` → automatically TIGHTENS the cap (caution-add
  direction; effective cap = `defaultCapFor(profile) × 0.75`, floored
  at `1.0` alerts/min).
- `Confidence.medium` → no-op (no cap modification).
- `Confidence.high` → does NOT auto-loosen the cap. Without explicit
  integrator-supplied confirmation
  (`isHighConfidenceConfirmed == false`), `Confidence.high` is
  treated as `Confidence.medium` (no cap modification). The system
  never auto-relaxes the safety cap from a high-confidence reading
  alone; the driver must affirmatively confirm via an
  integrator-supplied confirmation surface (e.g. an explicit toggle).
  When `isHighConfidenceConfirmed == true`, the cap loosens by 25%
  (`defaultCapFor(profile) × 1.25`).

### UNVERIFIED-magnitude flags

All three input magnitudes are **design-default hypotheses** pending
field-measurement validation, flagged verbatim per the kei-car-cohort
precedent (CHANGELOG.md 0.9.0 entry):

- **`CircadianPhase` multipliers** (`earlyMorning` 1.2 / `morning`
  1.0 / `afternoon` 1.1 / `evening` 1.05 / `night` 1.3 / `lateNight`
  1.5). Phase boundaries follow standard four-hour-block
  partitioning used in driver-fatigue reporting; multiplier values
  qualitatively-anchored in chronobiology (sleep inertia post-wake,
  post-lunch dip, evening fatigue accumulation, circadian-low at
  night-into-late-night, circadian-trough 00–03) but not yet
  field-calibrated to a population study mapping
  hour-of-day → effective-RT-multiplier specifically. See
  `KNOWN_LIMITATIONS.md` (DriverState-scaffolding section, 0.10.0).
- **`CumulativeFatigueClass` day-thresholds** (`rested` 0–2 / `mild`
  3–4 / `accumulated` 5–6 / `severe` 7+) AND per-class visibility
  lifts (`mild` +25m / `accumulated` +50m / `severe` +100m). Both
  the day-bucket boundaries and the visibility-lift magnitudes are
  design-default hypotheses pending fleet-class field measurement.
- **`Confidence` cap modifiers** (low: -25%; high-confirmed: +25%).
  The 25% magnitude is engineering judgement; per-population
  calibration of the optimal cap-tighten ratio for low-confidence
  drivers is deferred.

### Why this exists

The trait + state separation per Regan-Hallett-Gordon 2011
(PMC4001671) maps onto a richer state-axis surface than the four
`DriverState` enum values alone. Three additional state-axis inputs
were surfaced as Wave 1 sub-bundle 2 scaffolding for the #23
DriverState complete-class graduation: time-of-day (circadian phase
shapes baseline alertness regardless of trait or live state), session
history (cumulative fatigue compounds across days even when the
driver self-reports as alert today), and self-assessed confidence
(the driver's own read on their current capability is information
the integrator has access to that the package does not). All three
are advisory inputs the integrator wires when the signal is
available; the per-profile + live-context + vehicle-class baseline
remains the operational floor.

### Discipline

- **Caution-add-only invariant preserved.** Circadian-phase + session
  -state adjustments may make warning thresholds fire EARLIER than
  the per-profile baseline + live-context + state-delta floor;
  NEVER later. The factory enforces the multiplier `>= 1.0` floor
  (circadian) and the lift `>= 0` floor (session-state) at runtime
  via debug-mode assertions in `forDriverContext`. Confidence cap
  modification is the ONLY exception to the warn-thresholds-only-add
  -caution rule and applies only to the alerts-per-minute cap; the
  cap-loosen direction is gated by the confirmation flag.
  Negative-test coverage in
  `test/circadian_phase_test.dart`,
  `test/session_state_provider_test.dart`,
  `test/confidence_provider_test.dart`, and
  `test/navigation_safety_config_driver_state_inputs_test.dart`
  confirms the assertions fire on relaxing inputs.
- **Severity-not-profile invariant preserved.** All three inputs
  tune warning TIMING + alert DENSITY only. They do NOT modify the
  score-floor tiers (`safeScoreFloor` / `infoScoreFloor` /
  `warningScoreFloor`), the critical thresholds, or the
  critical-bypass behaviour (`AlertSeverity.critical` always fires
  regardless of cap).
- **Driver-always-drives invariant preserved.** All three
  providers (`SessionStateProvider`, `ConfidenceProvider`) AND the
  `CircadianPhase` enum are advisory inputs; they do NOT actuate the
  vehicle, do NOT close any control loop, do NOT modulate alert
  severity. The cap-override-with-confirmation pattern explicitly
  encodes this invariant for #30: the system never auto-relaxes the
  safety cap from a high-confidence reading alone; the driver must
  affirmatively confirm. Runtime debug-assertion in
  `forDriverContext` catches any divergence.
- **Backward compatible.** Existing 0.9.x callers see no behaviour
  change. `forDriverContext` without the four new optional
  parameters produces identical output to the 0.9.x signature.
  No naming collision with sibling-package types (verified via
  `flutter analyze` from monorepo root); no breaking change to
  `forProfile` / `forProfileWithContext` / `forDriverContext`
  signatures (additive named parameters only).

### Tests

- New tests across four files:
  - `test/circadian_phase_test.dart` — multiplier bounds (every
    phase `>= 1.0`); `lateNight` = 1.5 cap; baseline `morning` =
    1.0; `circadianPhaseFromHour` mapping coverage; `RangeError` on
    out-of-range hour.
  - `test/session_state_provider_test.dart` — interface contract;
    null-fallback (provider returns null → no effect); `SessionState`
    equality + props; exhaustive `CumulativeFatigueClass` lift
    coverage.
  - `test/confidence_provider_test.dart` — interface; `.low`
    tightens cap; `.medium` no-op; `.high` without confirmation =
    no-op (defaults to `medium`); `.high` WITH confirmation loosens
    cap; cap floor at `1.0` alerts/min.
  - `test/navigation_safety_config_driver_state_inputs_test.dart`
    — cross-feature integration: all three inputs at once +
    caution-add-only invariant verification + composition with
    existing `DrivingContext` + `vehicleOverrides`.

Total NSC test count: 253 → 285.

## 0.9.0 — 2026-05-05 — vehicle-class threshold-override surface

Adds an integrator-supplied vehicle-class signal path through the
existing context-aware threshold-config factory. The threshold floor
for a known under-served cohort (kei-car driven by the over-65
rural-Japan demographic) can now be sharpened without changing alert
severity, alert ordering, or the existing per-profile baselines that
today's integrators already depend on.

### Added

- **`VehicleClassProvider`** — abstract interface with a single
  getter `String? get vehicleClassToken`. The integrator implements
  this to surface a stable token (e.g. `'kei-car'`,
  `'compact-sedan'`, `'4wd'`, `'commercial-light'`). The package
  does not prescribe a vehicle-class taxonomy at the type system
  level; the integrator picks the tokens that best describe the
  vehicle population they serve. Tokens are advisory strings, NOT
  control inputs.
- **`VehicleThresholdOverrides`** — value class wrapping a
  `Map<String, NavigationSafetyConfig Function(NavigationSafetyConfig baseline)>`.
  The integrator registers caution-adding-only transforms keyed by
  vehicle-class token. The factory enforces the caution-add-only +
  severity-not-profile invariants at runtime via debug-mode
  assertions in `applyOverrideForToken`. A
  `VehicleThresholdOverrides.withKeiCarDefault()` factory ships the
  built-in kei-car override.
- **`DrivingContext.vehicleClassToken`** — new optional field on the
  existing `DrivingContext` value-object. `null` (the default) means
  no vehicle-class signal; thresholds fall back to the per-profile
  baseline. Composes independently with the existing `speedMps` /
  `humidityRH` / `timeSincePrecipitation` / `ambientTempCelsius`
  fields.
- **`NavigationSafetyConfig.forProfileWithContext`** — new optional
  named parameter `vehicleOverrides`. When supplied AND
  `context.vehicleClassToken` is non-null AND the token matches a
  registered key, the registered transform applies AFTER the
  per-profile baseline AND AFTER the live-context adjustments.
- Re-exported from `package:navigation_safety_core/navigation_safety_core.dart`.

### Built-in kei-car override

`VehicleThresholdOverrides.withKeiCarDefault()` ships the built-in
`'kei-car'` token override. The deltas:

- `warningVisibilityMeters` += 50m (kei-car windscreen + headlight
  cluster smaller than compact-sedan baseline; warn earlier on
  visibility loss to preserve reaction-margin).
- `warningTemperatureCelsius` += 1°C (kei-car cabin lower thermal
  mass + faster glass condensation in winter; warn earlier on
  cold-temperature transitions).

**UNVERIFIED-magnitude flag**: these deltas are **design-default
hypotheses** pending field-measurement validation. Kei-car-specific
visibility and thermal-mass calibration is not yet anchored in
published literature at the vehicle-class layer specifically; the
deltas compose qualitatively-known kei-car geometry and thermal mass
with the existing literature-anchored
`forProfile(DriverProfile.ageingRural)` reaction-time baseline
(PubMed 16313881 + downstream). A kei-car-class
calibration-validation follow-up is queued; integrators running
fleet-class telemetry are encouraged to surface deviations from the
design-default through the existing `LoomFitTelemetry` emit-only
stream.

### Why this exists

The kei-car-driven-by-over-65 cohort composes two known under-served
dimensions: a smaller-windscreen vehicle class commonly driven in
Hokkaido and Tohoku rural areas where snow-zone visibility loss is
the load-bearing safety question, AND an over-65 driver with the
slower hazard-perception reaction time the existing
`DriverProfile.ageingRural` calibration already encodes. The
per-profile baseline alone does not see the vehicle dimension; the
live-context adjustments (speed / humidity / precipitation) do not
either. This release adds the third dimension as an opt-in surface
the integrator wires when they have the signal, with the existing
caution-add-only invariant preserved as the operational floor.

### Discipline

- **Caution-add-only invariant preserved.** Vehicle-class
  adjustments may make warning thresholds fire EARLIER than the
  per-profile baseline + live-context floor; NEVER later. The
  factory enforces this at runtime via debug-mode assertions in
  `VehicleThresholdOverrides.applyOverrideForToken`. Negative-test
  coverage in `test/vehicle_threshold_overrides_test.dart` confirms
  the assertions fire on relaxing transforms.
- **Severity-not-profile invariant preserved.** Vehicle-class tunes
  TIMING (warn-earlier-floors) only; it does NOT modify the
  score-floor tiers (`safeScoreFloor` / `infoScoreFloor` /
  `warningScoreFloor`), the critical thresholds, or the
  alerts-per-minute cap override. Score-floor preservation is
  asserted at runtime in the same `applyOverrideForToken` enforcer.
- **Driver-always-drives invariant preserved.** `VehicleClassProvider`
  returns advisory tokens consumed for threshold tuning. It does NOT
  actuate the vehicle, NOT close any control loop, NOT modulate
  alert severity. The driver retains full control authority.
- **Backward compatible.** Existing 0.8.x callers see no behaviour
  change. `forProfileWithContext` without `vehicleOverrides`
  produces identical output. `DrivingContext` with the new
  `vehicleClassToken: null` default produces identical equality +
  hash + `toString` output for callers that did not set the field.
  No naming collision with the existing `VehicleClass` enum in
  `package:driving_consent/src/instrumentation_event.dart`
  (driving_consent 0.4.1): `VehicleClassProvider` is a different
  name and serves a different role (NSC threshold-tuning advisory
  vs. driving_consent instrumentation-event payload).

### Tests

- 32 new tests across four files:
  - `test/vehicle_class_provider_test.dart` (4 tests) — interface
    contract + null-token-falls-back-to-baseline + arbitrary-token
    no-taxonomy-enforcement.
  - `test/vehicle_threshold_overrides_test.dart` (12 tests) —
    registry construction + null/unknown-token fall-back + kei-car
    default delta-shape + score-floor preservation + critical-tier
    preservation + caution-add-only assertion negative tests
    (visibility-relaxing + temperature-relaxing + score-floor-modifying
    + caution-equal-permitted).
  - `test/navigation_safety_config_vehicle_class_test.dart` (9 tests)
    — `forProfileWithContext` composition with `vehicleOverrides` +
    null-vehicle-overrides + null-token + unknown-token + kei-car
    composition with humidity-driven temperature lift + score-floor
    + critical-tier preservation + null-context edge + all-six-profile
    smoke.
  - `test/driving_context_vehicle_class_test.dart` (7 tests) — value
    class equality + props + `toString` + null-as-absent across all
    five fields.

Total NSC test count: 221 → 253.

## 0.8.0 — 2026-05-04 — emit-only telemetry stream for alert-firing observations

Adds `LoomFitTelemetry` — a Pure Dart, emit-only broadcast stream of
`LoomFitTelemetryRecord` observations covering the four disjoint
outcome classes (`fired` / `droppedByThrottle` / `criticalBypass` /
`coldStart`) of `AlertDensityThrottle.shouldFire` decisions. The
class is the package-boundary surface for the calibration loop that
asks *did the loom fit each driver-class?* — the package observes
its own firing decisions and surfaces them on a broadcast stream;
the consuming application's analytics layer owns classification
logic, the privacy-class boundary, and the threshold for "the loom
does not fit this driver-class."

### Added

- **`LoomFitTelemetry`** — broadcast stream of telemetry records;
  emit-only at the package boundary. Methods:
  - `records` — `Stream<LoomFitTelemetryRecord>` (broadcast).
  - `record(LoomFitTelemetryRecord r)` — emit a single record.
  - `dispose()` — close the stream; idempotent.
- **`LoomFitTelemetryRecord`** — immutable value-object carrying:
  - `profileClass` (`DriverProfile`)
  - `ambientThreshold` (nullable `String` identifier, e.g.
    `"icy_road_30km"`)
  - `alertSequence` (`List<DateTime>`; defensively unmodifiable)
  - `responseLatency` (nullable `Duration`)
  - `outcome` (`LoomFitOutcome`)
- **`LoomFitOutcome`** enum: `fired`, `droppedByThrottle`,
  `criticalBypass`, `coldStart`. Disjoint and exhaustive over
  `shouldFire` decisions.
- Re-exported from `package:navigation_safety_core/navigation_safety_core.dart`
  + the `lib/src/looms.dart` runtime-loom barrel.

### Why this exists

The throttle's per-profile cap defaults are literature-anchored
DEFAULTS, not population-validated. To know whether a per-profile
cap actually fits the driver-class it is nominally tuned for, the
consuming application needs to observe firing decisions in
operation: drop-rate, critical-share, cold-start-share. Those are
calibration-class questions only the integrator has the data to
answer. `LoomFitTelemetry` is the package-boundary surface for
those observations.

Anchors:
- Medical alarm-fatigue scoping review
  ([PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/))
  — calibration discipline for alert-density bounds.
- AAA-FTS ADAS-exposure / driver-workload report — per-profile
  overwhelm differentials.
- Bian et al [PubMed 38669900](https://pubmed.ncbi.nlm.nih.gov/38669900/)
  — alert-magnitude × duration as one product; format-mismatch
  erases earlier-alert benefit.

### Discipline

- **Emit-only.** No detection logic, no policy enaction, no
  classification — those live in the integrator's analytics layer.
- **No driver-grading.** The schema names the OUTCOME of the loom,
  not the DRIVER. `responseLatency` (when supplied) is information
  about the loom's fit, not the driver's competence.
- **No data harvest.** An integrator that never subscribes incurs
  zero data-flow cost. The package ships no records anywhere by
  itself.
- **Pure Dart.** No Flutter dependency, no I/O, no platform
  channels.
- **Severity-not-profile invariant preserved.** The telemetry
  surface observes outcomes; it does not modulate severity-class.

### Tests

- 9 new tests in `test/loom_fit_telemetry_test.dart` covering:
  defensive copy of `alertSequence`; record + listen round-trip;
  multiple records arrive in order; broadcast stream allows
  multiple listeners; all four outcome enum values can be emitted;
  `dispose` closes the stream; `record` after dispose silently
  no-ops; `dispose` is idempotent; record with null
  `ambientThreshold` + null `responseLatency` works.

### Unchanged (back-compat)

- All 0.7.x / 0.6.x / 0.5.x / 0.4.x surface unchanged. The new
  class is purely additive; existing `AlertDensityThrottle` and
  `AlertExplainer` callers see no behaviour change.

## 0.7.1 — 2026-05-05 — SLUSH added to per-profile high-risk subset

Adds `SLUSH` (シャーベット) to the per-profile speak-string override
set in `RoadSurfaceConditionGlossary.forConditionAndProfile()`. The
high-risk subset now covers ICE / SNOW / WET_ICE / SLUSH; the lateral-
slip risk of partially-melted snow is documented by JAF guidance
materials as a distinct skid-class hazard, and drivers unfamiliar with
snow-zone road state underestimate it.

### Added

- Per-profile SLUSH speak-string overrides for all six profiles:
  - `ageingRural` — full kanji-native phrasing with brief action cue.
  - `snowZoneExperienced` — terse single-token (`シャーベット`).
  - `professional` — terse single-token (`シャーベット`).
  - `agriculturalForestry` — terse formal label (`シャーベット路面`).
  - `noviceUrban` — explicit hazard wording (slip-class warning).
  - `foreignTouristSnowZone` — simplified JA + EN-default
    (`Slush on road, slippery`).

### Tests

- 4 new tests in `test/road_surface_condition_test.dart` covering the
  four SLUSH per-profile classes (ageingRural action-cue;
  snowZoneExperienced + professional terse single-token; noviceUrban
  explicit-hazard wording; foreignTouristSnowZone EN-default policy).
  Existing exhaustive (profile × condition) coverage test continues
  to pass.

### Substrate anchor

- VSS PR #892 (canonical road-surface allowed-value set, includes
  SLUSH).
- JAF / MLIT / NEXCO / Yahoo!カーナビ public driver-guidance
  vocabulary (slush as distinct skid-class hazard).

### Discipline

- **Additive only.** No existing speak-string mapping changed; SLUSH
  was previously a fall-through to defaults; it now resolves through
  the per-profile override path. PATCH bump (0.7.0 → 0.7.1) reflects
  the additive vocab-map expansion with no API breakage.
- **Severity-not-profile invariant preserved.** The per-profile
  speak-string overrides shape rendering vocabulary; severity-class
  gating remains upstream at the `AlertSeverity` boundary.

### Unchanged (back-compat)

- API surface unchanged (no new public functions).
- 0.7.0 / 0.6.0 / 0.5.0 / 0.4.x callers see no behavior change for
  ICE / SNOW / WET_ICE; SLUSH callers previously got the default
  glossary entry, now get a profile-tuned one (additive enrichment).

## 0.7.0 — 2026-05-04 — UX differentiation hook activated

Activates the previously-stub `assertUxDifferentiated()` runtime hook
into a working registration-and-assertion mechanism. Closes the first
concrete operationalization of the package's architectural anchor:
*"the threshold layer is necessary but not sufficient for an alert
that arrives in time + makes sense + is calm enough to ignore safely;
the per-profile UX-differentiation layer is the second half."*

### Added

- **`registerUxDifferentiator(profile, tag)`** — consuming Flutter
  packages (`voice_guidance`, `navigation_safety`) call this at
  app-bootstrap time to record that they have wired profile-aware
  behavior for `profile` under a descriptive `tag`. Idempotent on
  `(profile, tag)` pairs; accumulates distinct tags per profile.
- **`registeredUxDifferentiators(profile)`** — returns the unmodifiable
  set of tags registered for `profile`. Empty set means no
  UX-differentiator is registered.
- **`debugClearUxDifferentiatorRegistry()`** — test-only helper for
  isolating cases.

### Changed

- **`assertUxDifferentiated(profile)`** is no longer a no-op stub. In
  a debug build, an unregistered profile throws an `AssertionError`
  with an actionable message naming the profile + naming where to
  register + citing the published evidence anchors (Bian et al PubMed
  38669900 / Strayer-AAA PMC7283540). In a release build, the
  assertion is erased — production driver-facing builds never crash on
  a misconfigured profile; the gap surfaces during integration
  testing.

### Tests

- 11 new tests in `test/ux_differentiation_test.dart` covering
  empty-registry behavior, single-profile registration, idempotency,
  multi-tag accumulation, unmodifiable-view discipline,
  AssertionError throw on unregistered profile, AssertionError
  message-content discipline (profile name + registration site +
  evidence anchors), and pass/fail isolation between profiles in the
  same registry run.

### Unchanged (back-compat)

- All 0.6.0 / 0.5.0 / 0.4.x surface unchanged. Existing call-sites
  that called the no-op stub continue to compile and run; in a debug
  build they now throw if no differentiator has been registered for
  the profile in question — the desired behavior, since a silent
  no-op gave integrators no signal that the architectural intent was
  being missed.

## 0.6.0 — 2026-04-30 — trait/state spike (NOT YET PUBLISHED)

Adds the trait/state matrix per Regan-Hallett-Gordon 2011 (PMC4001671)
as an additive, opt-in axis. Existing 0.5.0 callers see no behaviour
change; state-axis tuning is opt-in via the new factory only.

This is a **spike**: state-effect magnitudes are intentionally small
and flagged UNVERIFIED in `KNOWN_LIMITATIONS.md` (state-axis section).
The shape of the API is the load-bearing piece; magnitudes pending
state-axis literature anchoring.

### Added

- **`DriverState`** — enum with four values: `alert`, `fatigued`,
  `distracted`, `impairedVisibility`. Live (transient) axis,
  orthogonal to `DriverProfile` (trait).
- **`DriverContext`** — immutable value-object coupling a
  `DriverProfile` (trait) with a `DriverState` (state). Constructible
  via the default constructor or the named factory
  `DriverContext.combineWith(profile:, state:)`. Includes
  `withState(newState)` for mid-trip state updates without losing
  the trait.
- **`NavigationSafetyConfig.forDriverContext(context, {environmentalContext})`**
  — new factory tuning thresholds to both the trait baseline and the
  state-axis delta. Optionally composes with the v0.5.0
  `DrivingContext`. Conservative-only: warns earlier than the
  per-profile baseline, never later.

### Unchanged (back-compat)

- `NavigationSafetyConfig.forProfile(profile)` — identical behaviour to 0.5.0.
- `NavigationSafetyConfig.forProfileWithContext(profile, context:)` — identical behaviour to 0.5.0.
- All other 0.5.0 surface unchanged.

## 0.5.0 — 2026-04-30

Adds an additive context-aware factory and a driving-context value
object so consuming apps can pass live conditions (speed, humidity,
precipitation history, ambient temperature) into the threshold-config
factory and receive thresholds tuned to both the per-profile baseline
and the live conditions.

### Added

- **`DrivingContext`** — immutable value-object with four optional
  fields: `speedMps`, `humidityRH`, `timeSincePrecipitation`,
  `ambientTempCelsius`. Each field is optional; a null field means
  "context not available; fall back to the non-context baseline".
  Const-constructible and equatable.
- **`NavigationSafetyConfig.forProfileWithContext(profile, context: ...)`** —
  new factory alongside the existing `forProfile()`. When context is
  null, delegates to `forProfile(profile)` for backwards-compat. When
  context fields are non-null, adjusts the relevant thresholds:
  - Speed → warning visibility floor raises to fit reaction time +
    braking distance via standard kinematics.
  - Humidity + ambient → warning temperature raises to cover
    dew-point-driven black-ice risk via the Magnus formula.
  - Precipitation history → warning visibility raises by a residual
    surface-moisture margin via exponential decay (default half-life
    90 minutes; conservative).
- **`lib/src/calibration/` directory** with three formula modules:
  - `speed_dependent_visibility.dart` — speed + reaction time +
    braking deceleration → required visibility.
  - `humidity_dependent_temperature.dart` — Magnus formula for
    dew-point-based effective road-surface temperature.
  - `precipitation_history_decay.dart` — exponential surface-moisture
    decay with overridable half-life.

### Why this exists

Per-profile baseline thresholds tuned for typical commute conditions
can leave no margin at higher speeds, dry-air black-ice mornings, or
residual-wet-surface windows. Adding a context-aware factory lets a
consuming app raise the threshold floor when live conditions warrant
without changing the per-profile baseline used by apps that lack the
sensor inputs. The factory is additive: the existing `forProfile()`
factory and every existing call site behave identically.

Citations for each formula are documented in the module headers:

- Reaction-time defaults — [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)
  (novice 3.58s vs experienced 1.32s); other per-profile RTs are
  reasonable defaults pending field validation (UNVERIFIED — see
  `KNOWN_LIMITATIONS.md`).
- Braking-distance — standard kinematics; default deceleration 5.5
  m/s² for typical dry pavement.
- Magnus formula — modern parameter constants `a = 17.625`,
  `b = 243.04°C` per Alduchov & Eskridge 1996; black-ice formation
  envelope per [Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice).
- Exponential surface-moisture decay — first-order-evaporation model;
  90-minute half-life default is conservative (UNVERIFIED for
  population values).

### Backwards-compatibility

Pure addition. Every existing API is unchanged. `forProfile()`
returns the same configuration as in 0.4.x. Existing call sites
continue to work without modification.

### Known limitations not closed in 0.5.0

- Four of the six per-profile reaction-time defaults are UNVERIFIED
  specific cites (anchors derived from surrounding literature; not
  population-validated).
- The 90-minute precipitation-decay half-life is a conservative
  default; integrating apps with telemetry should override.
- The dew-point-based effective temperature is a conservative
  estimate, not a measured road-surface temperature; real surface
  temperature depends on emissivity, cloud cover, surface material,
  and time-of-night.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from earlier
  versions, plus the new "Driving-context formulas (added in 0.5.0)"
  section.

## 0.4.2 — 2026-04-29

Documents the package's driving-automation-regime applicability at the
package boundary so consumers can ground their integration decisions
in the documented scope. Documentation patch — no API surface change.

### Added

- **`README.md` "Scope: driving automation regimes" section** — plain
  declaration that this package targets SAE J3016 Level 0 / Level 1
  supportive use and explicitly does not provide L2+ handover-class
  supervision; standards-mapping summary one-liner; concrete consumer
  guidance on when the package's alerts are appropriate vs.
  insufficient; equal-dignity invariant pointer.
- **`KNOWN_LIMITATIONS.md` "Standards mapping (current advisory
  framing)" section** — full paragraphs on:
  - **ISO 26262**: current QM-likely framing at the application layer
    under advisory-only intent; integrator owns the final ASIL
    determination for their integration; evidence supporting the
    framing cited (advisory-mood wording discipline,
    `bypassForCritical` invariant, public-corpus speed references).
  - **SAE J3016**: L0/L1 supportive mapping; explicit non-claim on L2+;
    re-classification trigger named for any consuming app evolving
    toward L2+ pilots.
  - **JIS / JASO**: explicit not-mapped at this scope; qualified
    Japanese-domestic functional-safety partner consultation required
    before any IVI-vendor / OEM-pilot integration targeting the
    Japanese-domestic certification surface.
  - **Equal-dignity invariant**: alert visibility, severity ordering,
    and plane-allocation priority MUST be severity-driven, never
    profile-driven; profile-aware behaviour belongs in verbosity,
    locale, and density-cap surfaces, not in visibility / preemption /
    plane-allocation paths.

### Why this exists

The package's surfaces are increasingly being considered as substrates
for HMI integrations (display-server, hardware-overlay-plane, IVI
vendor pilots). Without an explicit driving-automation-regime
declaration at the package boundary, integrators can mis-frame the
package as a supervision-loop input or as L2+-handover-capable, which
would be a misuse of its documented scope. This release adds the
declaration so future integrators and future package-internal cycles
can ground their work in the same intent. The standards-mapping detail
in `KNOWN_LIMITATIONS.md` is sourced from an internal standards
review.

### Backwards-compatibility

Pure documentation patch. No existing API changed. No file under
`lib/` modified.

### Known limitations not closed in 0.4.2

- ISO 26262 ASIL classification at the integration boundary remains
  with the integrator and depends on their hazard analysis; this
  package does not certify any specific ASIL outcome.
- JIS / JASO conformance is not mapped at this scope. Vendor / OEM
  integration targeting Japanese-domestic certification requires a
  qualified domestic functional-safety partner.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from earlier
  versions.

## 0.4.1 — 2026-04-28

Names and documents what 0.4.0 already shipped as runtime looms, and
binds them to the cross-language Loom Protocol vocabulary used by the
SPA AI build-time loom kit. Documentation patch — no API surface
change.

### Added

- **`lib/src/looms.dart`** — category barrel re-exporting
  `AlertDensityThrottle` and `AlertExplainer` with a class-level
  doc-comment naming them as runtime looms. Either of these imports
  surfaces the same symbols; the barrel adds the runtime-loom
  category framing:
  ```dart
  import 'package:navigation_safety_core/navigation_safety_core.dart';
  // or
  import 'package:navigation_safety_core/src/looms.dart';
  ```
- **`LOOMS.md`** at the package root — cross-reference table mapping
  each runtime loom to its 3-slot vision attribution
  (`sakichi_vision_id` / `method_vision_ids` / `stance_vision_ids`),
  plus a brief explanation of how the 3-slot schema binds this
  package's runtime looms to SPA AI's build-time looms.
- **3-slot vision attribution doc-comments** on `AlertDensityThrottle`
  and `AlertExplainer` class declarations, matching the convention
  documented in
  [SPA AI's loom-authoring guide](https://github.com/aki1770-del/spa-ai/blob/main/docs/loom_authoring_guide.md).
  - `AlertDensityThrottle` — `sakichi_vision_id: 14`,
    `method_vision_ids: [77, 18, 99]`, `stance_vision_ids: [22, 100]`.
  - `AlertExplainer` — `sakichi_vision_id: 96`,
    `method_vision_ids: [77, 99]`, `stance_vision_ids: [22, 96, 100]`.

### Why this exists

`AlertDensityThrottle` and `AlertExplainer` shipped in 0.4.0 are
runtime looms — Pure Dart classes that catch documented failure modes
(alert-fatigue, condition-without-action) at the package boundary
inside the consuming app's process. The Loom Protocol vocabulary used
by SPA AI's build-time loom kit applies to them too; 0.4.1 names that
explicitly so the cross-language convention is discoverable from this
package's own surface. This is documentation work; the runtime
behavior is unchanged from 0.4.0.

### Backwards-compatibility

Pure documentation patch. No existing API changed. Existing imports
of `AlertDensityThrottle` and `AlertExplainer` via
`package:navigation_safety_core/navigation_safety_core.dart` continue
to work unchanged. The new `src/looms.dart` barrel is additive.

### Known limitations not closed in 0.4.1

- No runtime registry. The catalog does not auto-discover its
  members; integrating apps instantiate each loom explicitly.
- No cross-language verification of the 3-slot attribution. The
  attribution is a documentation convention today; no runtime check
  enforces matching slots between this package's Dart looms and the
  SPA AI Python looms.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from 0.4.0
  and earlier.

## 0.4.0 — 2026-04-28

Adds two driver-facing surfaces that together address the documented
alert-fatigue and condition-without-action failure modes in consumer
ADAS / nav advisory layers.

### Added

- **`AlertDensityThrottle`** — per-profile rolling-window rate limiter
  for advisory alerts. Prevents desensitization on info / warning tiers
  while preserving credibility of `AlertSeverity.critical` (which
  bypasses the throttle as a documented invariant).
  - `AlertDensityThrottle.forProfile(profile)` — constructs a throttle
    with the literature-anchored per-profile cap.
  - `AlertDensityThrottle.defaultCapFor(profile)` — exposes the cap
    table for integration with `NavigationSafetyConfig`.
  - `shouldFire(now, severity)` — gating method; returns the firing
    decision and (on permit) records the timestamp.
  - `currentWindowCount(now)` — test-only inspection.
  - Per-profile cap defaults (alerts/min):
    - `professional` 4.0
    - `snowZoneExperienced` 3.0
    - `agriculturalForestry` 2.0
    - `noviceUrban` 1.5
    - `ageingRural` 1.2
    - `foreignTouristSnowZone` 1.0
- **`NavigationSafetyConfig.alertsPerMinuteCapOverride`** — optional
  field for integrating apps to override the per-profile default with
  measured per-population data. Helper:
  `effectiveAlertsPerMinuteCap(profile)` returns the override if set,
  the profile default otherwise.
- **`AlertExplainer`** — pairs a `RoadSurfaceCondition` with a
  pre-localized recommended action in the verbosity that fits the
  active `DriverProfile`.
  - `AlertExplainer.forConditionAndProfile(condition, profile)` —
    returns the AAA-designed (condition, action) tuple, the verbosity
    level, and the locale tag.
  - 36 high-action cells (6 profiles × 6 high-action conditions: WET,
    SNOW, ICE, SLUSH, WET_ICE, LOOSE_GRAVEL); UNKNOWN and DRY are
    profile-flat per design brief.
  - `VerbosityLevel` enum: `terse`, `brief`, `standard`, `full`.
  - Verbosity mapping per profile: professional → terse;
    snowZoneExperienced → brief; noviceUrban + agriculturalForestry →
    standard; ageingRural + foreignTouristSnowZone → full.
  - Locale: `en` for `foreignTouristSnowZone`; `ja` for others.

### Why this exists

- **Alert-density throttle**: alarm-fatigue is the documented failure
  mode for systems that fire too many alerts. The medical alarm-fatigue
  scoping review ([PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/))
  finds >60% of alarms get no timely response and 85% of clinicians
  report overwhelm. The [AAA-FTS ADAS-exposure / driver-workload
  report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf)
  extends the same pattern to consumer ADAS;
  [arxiv 2410.06388](https://arxiv.org/html/2410.06388) frames
  over-warning as a silent safety failure. Per-profile caps reflect
  reaction-time and overwhelm differentials documented in
  [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/) (novice
  hazard-perception RT 3.58s vs experienced 1.32s),
  [PMC7283540](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283540/)
  (older drivers cost +8s eyes-off-road on identical voice formats),
  and [PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/)
  (novice-fog crash-rate elevation).
- **Action-coupled explainer**: alerts that name a condition without
  the implied action degrade compliance. Medication-adherence
  literature ([PMID 34111571](https://pubmed.ncbi.nlm.nih.gov/34111571/))
  shows action-coupled instructions improve adherence over
  condition-only; CGM (continuous glucose monitor) alert-design
  literature (MDPI 2024 review of CGM UX patterns) finds the same in
  ambient-monitoring contexts. Driving translation: "icy road" is
  incomplete; "icy road → reduce speed to 30 km/h" is actionable.
  Per [PubMed 38669900](https://pubmed.ncbi.nlm.nih.gov/38669900/)
  (Bian), earlier triggering reduces collisions only when alerts
  persist long enough to be processed — coupling the action with the
  condition gives the driver the second the alert needs to land.

### Action-text discipline

- Action verbs are advisory (「以下に減速」 / "reduce" / "avoid" /
  "maintain"), not imperative-on-control. Speed numbers are published
  reference points (JAF / MLIT vocabulary), not system-enforced limits.
- "Stop in a safe place" is the strongest action; phrased "if
  possible" / 「可能であれば」 — no implication that the system stops
  the vehicle.
- No action string promises an outcome.

### Backwards-compatibility

Pure addition. No existing API changed. The default constructor
`NavigationSafetyConfig()` still produces the historical defaults
unchanged. New `alertsPerMinuteCapOverride` field defaults to `null`
(use the per-profile literature default).

### Known limitations not closed in 0.4.0

- Per-profile alert/min caps are literature-anchored DEFAULTS, not
  population-validated. Integrating apps with measured per-population
  data should override.
- `bypassForCritical` defaults to `true` and is a documented
  invariant. Changing this default would alter the package's safety
  contract.
- Action-string speed references (30 km/h / 20 km/h) are advisory,
  not system-enforced.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from earlier
  versions.

## 0.3.1 — 2026-04-28

Surfaces road-surface condition vocabulary aligned to the upstream VSS
`Vehicle.Exterior.RoadSurfaceCondition` signal landing via
[COVESA/vehicle_signal_specification PR #892](https://github.com/COVESA/vehicle_signal_specification/pull/892).

### Added

- **`RoadSurfaceCondition`** — enum aligned to VSS allowed-value set
  (`UNKNOWN`, `DRY`, `WET`, `SNOW`, `ICE`, `SLUSH`, `WET_ICE`,
  `LOOSE_GRAVEL`). Round-trip helpers `vssValue` and `fromVss` preserve
  the upstream string vocabulary verbatim so consuming code can
  interoperate with VSS-derived telemetry without re-mapping.
- **`RoadSurfaceConditionGlossary`** — display labels and TTS-ready
  phrases per condition, with optional per-profile overrides for the
  high-risk subset (`ICE` / `SNOW` / `WET_ICE`):
  - `forCondition(c)` — profile-neutral default
  - `forConditionAndProfile(c, profile)` — applies per-profile
    speak-string variants where vocabulary precision matters
- Per-profile vocabulary discipline:
  - `ageingRural` — kanji-native (凍結, 圧雪) per generational
    recognition reliability
  - `snowZoneExperienced` / `professional` — terse single-word phrases
  - `noviceUrban` — condition + hazard tag for explicit risk framing
  - `agriculturalForestry` — condition + off-road consideration where
    relevant
  - `foreignTouristSnowZone` — English-default TTS + simplified
    Japanese (no kanji-only output; non-native readers cannot parse
    mid-drive)

### Why this exists

Documented Japanese snow-zone driver pain point (literature review):
no major nav app provides an in-app glossary for road-surface terms
(凍結 / 圧雪 / シャーベット / ブラックアイス / アイスバーン), each with
distinct safe-driving semantic. Drivers learn through accidents or
YouTube. Sources: [JAF snow-driving safety](https://jaf.org.jp/common/attention/snow),
[MLIT Hokkaido snow-road guide](https://www.hrr.mlit.go.jp/hokugi/yukinavi/),
[JARTIC](https://www.jartic.or.jp/), [Yahoo!カーナビ winter
guidance](https://note.com/yahoo_carnavi/n/n0ecdc7700eb0).

### Backwards-compatibility

Pure addition. No existing API changed. The glossary is informational
(display labels + TTS phrases); it does not actuate any vehicle
behavior and is not safety-critical in the control sense. Bare
glossary text is conservative — no specific km/h advice (speed advice
belongs to a separate action-coupled explainer surface, planned for
a future minor release).

### Known limitations not closed in 0.3.1

- ブラックアイス (black ice) is documented as a sub-class of `ICE`; the
  upstream VSS signal does not expose it as a separate enum value, so
  this package does not invent one.
- Glossary text is informational only. Speed advisories, action-coupled
  explanations, and alert-density throttling are separate surfaces
  planned for the next minor release.
- See `KNOWN_LIMITATIONS.md` for the full list inherited from 0.3.0.

## 0.3.0 — 2026-04-27

Closes the V100 gap surfaced by post-0.2.0 autoresearch: the previous
5-profile taxonomy mis-mapped foreign-tourists-in-snow-zone, and two
threshold magnitudes were calibrated by intuition rather than published
literature.

### Added

- **`DriverProfile.foreignTouristSnowZone`** — sixth profile, closes the
  Hokkaido-foreign-tourist class. Combines novice-equivalent
  unfamiliarity with local conditions + likely non-winterised rental
  vehicle + language-localization gaps in road signage. Most-conservative
  defaults across every dimension; previously mis-mapped to either
  `snowZoneExperienced` (catastrophically wrong) or `noviceUrban`
  (location-wrong).
- **`assertUxDifferentiated(profile)`** — advisory hook stub for
  consuming Flutter packages. No-op in 0.3.0; v0.4+ will fire a runtime
  advisory when a profile is selected but the consuming UX layer has
  not registered profile-aware differentiation. Forward-compatible:
  integration code can call it today; it activates when v0.4+ ships.
- **`KNOWN_LIMITATIONS.md`** — honest disclosure of remaining defects
  the 0.3.0 ship does not close, with citations to public sources.

### Changed (calibration corrections per literature)

- **`ageingRural` `infoTemperatureCelsius`**: 5°C → 4°C. The 0.2.0
  value combined with `infoVisibilityMeters` 1500m fired the info tier
  on most autumn evenings in Hokkaido / Tohoku — V14 alert-fatigue
  risk per [arxiv 2410.06388](https://arxiv.org/html/2410.06388) +
  [AAA-FTS ADAS-exposure report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf).
  Lowered to preserve information-tier signal without firing on
  routine cold autumn evenings.
- **`ageingRural` `warningTemperatureCelsius`**: 1°C → 2°C. Black ice
  forms with road-surface ≤0°C even when ambient air is several
  degrees warmer ([Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice)).
  1°C left no margin above the formation envelope. Raised for
  meaningful margin.
- **`noviceUrban` `warningVisibilityMeters`**: 250m → 320m. Novice
  hazard-perception RT is 3.58s vs 1.32s experienced
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)); at
  60 km/h that's ~37m additional reaction-distance from RT alone, so
  +50m over standard left no braking margin. 320m gives RT-margin +
  braking margin per
  [Konstantopoulos PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/).

### Backwards-compatibility

Default constructor `NavigationSafetyConfig()` is unchanged. All five
0.2.0 profiles still exist and still resolve via `forProfile()`. Only
the *magnitudes* for `ageingRural` (two thresholds) and `noviceUrban`
(one threshold) shift; direction of every shift is preserved.

### Known limitations not closed in 0.3.0

See `KNOWN_LIMITATIONS.md`. Notably: sensory-disability axis,
trait/state separation (Regan-Hallett-Gordon 2011), frailty-vs-robust
split inside `ageingRural`, and the wrong-dimensions concern (UFOV /
glance-budget govern crash risk more strongly than score floors do —
both require coordination with consuming Flutter packages and are
deferred).

## 0.2.0 — 2026-04-27

Added `DriverProfile` enum + `NavigationSafetyConfig.forProfile()` factory
constructor for per-driver-class threshold defaults.

Five profiles in v1, each tuned to a coherent point in the cognitive-load /
experience / role / vehicle-type space:

- `DriverProfile.ageingRural` — older drivers (typically 65+) who may be
  commuting in rural areas; often novice with EV or modern ADAS-equipped
  vehicles. More conservative thresholds (warn earlier on weather +
  visibility; higher score floor for "safe" classification).
- `DriverProfile.snowZoneExperienced` — drivers experienced with
  snow-zone commute conditions. Standard thresholds (the historical
  default profile equivalent).
- `DriverProfile.noviceUrban` — newly-licensed or low-mileage drivers
  (typically first 3 years). Warn earlier on visibility; higher score
  floor; threshold-only shift (explainer-friendly UX surfaces are a
  downstream Flutter-package concern).
- `DriverProfile.professional` — commercial drivers (taxi, freight,
  delivery, rideshare). Standard thresholds; minimum-distraction UX
  optimization is a downstream concern.
- `DriverProfile.agriculturalForestry` — drivers operating off-road
  in agricultural or forestry contexts. Standard thresholds today;
  off-route-awareness semantic is a downstream extension.

Use:

```dart
final config = NavigationSafetyConfig.forProfile(DriverProfile.ageingRural);
```

Backwards-compatible: existing `NavigationSafetyConfig()` call sites
continue to work unchanged (returns the historical default profile
equivalent).

## 0.1.0 — 2026-04-27

Initial release.

Pure Dart core extracted from `navigation_safety` so non-Flutter
consumers (CLI tools, servers, test fixtures, pure-Dart packages
like `driving_conditions`) can depend on the safety-model vocabulary
without inheriting Flutter + flutter_bloc.

Exports:

- `AlertSeverity` (info / warning / critical; declaration order is load-bearing)
- `NavigationRoute`
- `NavigationSafetyConfig`
- `SafetyScenario`
- `SafetyScore`

The full `navigation_safety` Flutter package re-exports everything
here for back-compatibility.
