# Known limitations

This document lists known limitations of the current `navigation_safety_core`
package, with citations to public sources, so that consumers can integrate
with eyes open and contribute corrections from informed positions.

The list names what we don't yet know rather than letting silent gaps
reach drivers.

---

## DriverState-axis scaffolding (added in 0.10.0) — UNVERIFIED magnitudes

The 0.10.0 release scaffolds three additional state-axis inputs onto
the existing `forDriverContext` factory: time-of-day circadian-phase,
driving-session-state, and self-assessed-confidence with the
cap-override-with-confirmation pattern. The **API shapes** are the
base for a planned, complete `DriverState` class; the **magnitudes** in
the per-input lookup tables are design-default hypotheses pending
field-measurement validation.

### What is UNVERIFIED at 0.10.0

- **`CircadianPhase` per-phase multipliers** (`earlyMorning` 1.2 /
  `morning` 1.0 / `afternoon` 1.1 / `evening` 1.05 / `night` 1.3 /
  `lateNight` 1.5). The phase boundaries (00:00 / 04:00 / 08:00 /
  12:00 / 16:00 / 20:00) follow the four-hour-block partitioning
  used in driver-fatigue reporting and are qualitatively-anchored in
  chronobiology (sleep inertia post-wake, post-lunch dip, evening
  fatigue accumulation, circadian-low-into-trough overnight). The
  multiplier values themselves are NOT yet anchored in a published
  population study mapping hour-of-day to an
  effective-reaction-time-multiplier specifically; the values are
  conservative-only (every multiplier `>= 1.0`) and ordered to match
  the qualitative literature. Per-population calibration is deferred
  pending fleet-class field measurement.
- **`CumulativeFatigueClass` day-thresholds** (`rested` 0–2 / `mild`
  3–4 / `accumulated` 5–6 / `severe` 7+). The boundaries are
  design-default hypotheses; the integrator's own fleet-class data
  may show different empirical breakpoints. The **per-class
  visibility lifts** (`mild` +25m / `accumulated` +50m / `severe`
  +100m) are similarly conservative engineering-judgement values
  pending field-measurement validation.
- **`Confidence` cap modifiers** (low: cap × 0.75 with floor 1.0
  alerts/min; high-confirmed: cap × 1.25). The 25% magnitude is
  engineering judgement consistent with the alert-density bound
  literature (PMC12181921 + AAA-FTS), but no published source maps
  driver self-assessed-confidence directly to an
  optimal-cap-tighten-ratio. Per-population calibration is deferred.

### What is verified at 0.10.0

- **API shape** — three inputs compose orthogonally into the
  existing trait + state + live-context + vehicle-class layering;
  every input is opt-in (defaults preserve 0.9.x behaviour exactly).
- **Caution-add-only contract** — circadian + session-state may make
  warning thresholds fire earlier than the post-state-delta floor,
  never later. The confidence cap-modifier is the ONLY layer
  permitted to relax (loosen) and only via the
  cap-override-with-confirmation pattern; the cap-loosen direction
  requires `isHighConfidenceConfirmed == true` (driver-always-drives
  invariant). The four new test files check this, but none of them
  makes an assertion fire, and none of their checks of the cap
  passes a vehicle-class override: from 0.10.0 through 0.11.6 that
  layer could loosen the cap without confirmation (next item).
- **Driver-always-drives contract** — for `Confidence.high` without
  confirmation, the confidence step in `forDriverContext` returns the
  cap it received, unchanged, in every build mode; the cap-flow tests
  in `test/confidence_provider_test.dart` check this with no
  vehicle-class override. The runtime debug-assertion beside that
  step compares the step's result with the cap it received, so a cap
  raised before the step passes it. From 0.10.0 through 0.11.6 a
  vehicle-class override could raise the cap before the step, with no
  confirmation and without tripping the assertion (10.0 against the
  `ageingRural` default of 1.2, on every published version in that
  range). From 0.11.7 `VehicleThresholdOverrides` refuses any change
  to the cap. A registry whose class implements
  `VehicleThresholdOverrides`, or extends it and replaces
  `applyOverrideForToken`, is checked only if that method returns
  what this package's `applyOverrideForToken` returns; otherwise it
  can still change the cap, unchecked and unreported (see
  `SAFETY_BOUNDARY.md` section 7.2).
- **Back-compat** — `forProfile`, `forProfileWithContext`, and
  `forDriverContext` (without the five new optional parameters)
  unchanged from 0.9.x.

### Out of scope at 0.10.0

- Live-detection of any of the three inputs (drowsiness from
  steering entropy, fatigue from heart-rate variability, confidence
  from gaze-tracker / micro-expression analysis, etc.) is out of
  scope. All three values are integrator-supplied; this package does
  not infer them.
- Per-population-validated magnitude tables (the 0.10.0 magnitudes
  are placeholders pending the integrator's own fleet-class
  telemetry; the `LoomFitTelemetry` 0.8.0 stream is the
  package-boundary surface for that calibration loop).
- The full trait × state × time × session × confidence five-axis
  matrix per Regan-Hallett-Gordon T3 + downstream is a v1.0
  architecture decision; 0.10.0 ships the orthogonal axes and the
  composition factory only.

---

## DriverState (state-axis spike, added in 0.6.0) — UNVERIFIED magnitudes

The `DriverState` enum and `DriverContext` trait/state composite were
added in 0.6.0 per Regan-Hallett-Gordon 2011 (PMC4001671) trait/state
separation. The **shape** of the API is intentional and stable for
this spike (Regan T3); the **magnitudes** of the per-state delta
applied by `NavigationSafetyConfig.forDriverContext` are NOT
literature-anchored and are placeholders pending state-axis
calibration.

### What is UNVERIFIED at 0.6.0

- **`fatigued` state** — reaction-time penalty (+0.5 s) and warning-
  temperature lift (+1 °C). The +0.5 s magnitude is a conservative
  lower-bound consistent with Williamson & Feyer 2000
  ([PubMed 10984335](https://pubmed.ncbi.nlm.nih.gov/10984335/)),
  which reports that 17–19 hours of wakefulness produces response-speed
  degradation of up to 50% on some tasks (equivalent to ~0.05% BAC),
  and 24+ hours produces impairment equivalent to ~0.10% BAC. The
  package's +0.5 s sits within the lower-bound region of that
  distribution; full per-hour-of-wakefulness calibration is deferred
  pending field telemetry. The +1 °C warning-temperature lift remains
  engineering judgement (no direct literature anchor for the
  fatigue↔frost-margin mapping).
- **`distracted` state** — reaction-time penalty (+1.0 s). Strayer &
  Drews 2007
  ([Cell-Phone-Induced Driver Distraction](https://appliedcognition.psych.utah.edu/publications/cellphone.pdf))
  and the AAA Foundation cognitive-distraction series
  ([Cognitive Distraction: Something to Think About](https://aaafoundation.org/wp-content/uploads/2018/01/CognitiveDistractionReport.pdf))
  document a roughly two-fold increase in failure-to-detect rate plus
  measurable RT slowing under cognitive load (with P300 amplitude
  reduced ~50% during hands-free conversation). The +1.0 s magnitude
  is a conservative population-applicable bracket consistent with the
  RT-slowing distributions reported in that body of work; per-task
  calibration (texting vs. conversation vs. nav-menu) is deferred.
- **`impairedVisibility` state** — visibility-tier scale-up (×1.25).
  FHWA roadway-visibility research
  ([Current Research and Practices, FHWA visibility section](https://highways.dot.gov/safety/other/visibility/roadway-visibility-research-needs-assessment/2-current-research-and))
  documents that fog reduces contrast and produces longer visual
  response times, with drivers underestimating speed and reducing
  preview distance; the eLife "Foggy perception slows us down"
  finding ([eLife article](https://elifesciences.org/articles/00031))
  reports drivers averaging 85.1 km/h in good visibility dropping to
  70.9 km/h in severe fog. The ×1.25 scale-up is directional and
  sits within the qualitative envelope of those reductions, but no
  published source maps a single visibility-tier multiplier to a
  fixed acuity-degradation factor across fog / whiteout / glare; the
  exact magnitude remains UNVERIFIED and will be refined when a
  per-condition multiplier is field-calibrated.
- **`alert` state** — no delta applied; this is by definition the
  baseline and is verified to be unchanged from 0.5.0 behaviour.

### What is verified at 0.6.0

- **API shape** — trait × state separation per Regan-Hallett-Gordon
  2011 (PMC4001671) T3 finding.
- **Conservative-only contract** — state delta may make thresholds
  warn earlier than the per-profile baseline, never later. Verified
  by tests that compare `forDriverContext(ctx)` against
  `forProfile(ctx.profile)` for every state and assert
  warningTemperatureCelsius monotonic-up and visibility-tier
  monotonic-up. An earlier threshold does not only add caution:
  `impairedVisibility` also moves the info and critical visibility
  thresholds earlier, every alert that fires takes a slot in
  `AlertDensityThrottle`'s rolling window, and a later warning can be
  dropped (measured with `ageingRural` and its default cap of 1.2,
  readings of 1600 m, 1600 m and 250 m, 10 s apart: in the `alert`
  state the warning fires; under
  `impairedVisibility`, with the info threshold at 1875 m, two info
  alerts fire and the warning is dropped).
- **Back-compat** — `forProfile` and `forProfileWithContext`
  unchanged from 0.5.0.

### Out of scope at 0.6.0

- The full trait × state matrix (`DriverProfile` × `DriverState`)
  with per-cell calibration is a v1.0 architecture decision. 0.6.0
  ships the orthogonal axes and the composition factory; per-cell
  calibration is deferred.
- Live state detection (drowsiness from steering entropy, distraction
  from gaze trackers, etc.) is out of scope. The state value is
  caller-supplied; this package does not infer it.

---

## DriverProfile taxonomy (added in 0.2.0)

### Missing classes

The 5 profiles of 0.2.0 (`ageingRural`, `snowZoneExperienced`,
`noviceUrban`, `professional`, `agriculturalForestry`) did not cover
the two classes below. There are six profiles now: 0.3.0 added
`foreignTouristSnowZone` for the first.

- **Foreign-tourist driver in unfamiliar snow-zone.** Hokkaido winter
  accidents involve foreign self-driving tourists at meaningful rates
  ([reference](https://www.explorelifehub.com/en/hokkaido-winter-driving-guide/);
  exact magnitude is single-source — directional). The class is currently
  mis-mappable to either `snowZoneExperienced` (wrong — they have neither
  experience nor local equipment) or `noviceUrban` (location-wrong).
  **Addressed in 0.3.0** with new profile `foreignTouristSnowZone`.

- **Driver with sensory disability** (deaf / low-vision / hearing-aid user).
  HMI accessibility literature treats this as a first-class class
  ([PMC10561786](https://pmc.ncbi.nlm.nih.gov/articles/PMC10561786/),
  [Springer ADAS visual+auditory interfaces](https://link.springer.com/chapter/10.1007/978-3-540-70540-6_8)).
  No accessibility axis in v0.2.0 / v0.3.0. **Deferred** until the design
  for cross-cutting accessibility axes is settled (likely v0.4 or later
  in coordination with consuming Flutter packages).

### Trait-only taxonomy

The six profiles encode driver **trait** (who-the-driver-is). Industry
literature (Regan, Hallett & Gordon 2011 —
[PMC4001671](https://pmc.ncbi.nlm.nih.gov/articles/PMC4001671/))
separates trait from **state** (drowsy / distracted / alert / asleep).
A `DriverState` axis crossed with `DriverProfile` would match how risk
is actually modeled. **Addressed in 0.6.0** with `DriverState` and
`DriverContext` (see the DriverState section above); the full trait ×
state matrix with per-cell calibration remains a v1.0 architecture
decision.

### Frailty-vs-robust split inside `ageingRural`

The Kasama rural-Japan study
([ScienceDirect S2214140520301134](https://www.sciencedirect.com/science/article/abs/pii/S2214140520301134))
identifies the frailty-phenotype as the within-cohort discriminator for
ageing-driver risk. Our `ageingRural` is monolithic. **Deferred** until
sub-cohort granularity is justified by evidence.

---

## Threshold magnitudes (added in 0.2.0)

The threshold deltas per profile were initially chosen by intuitive
"more conservative" reasoning rather than published literature. The
direction of each shift is correct (older + less experienced = warn
earlier); the magnitudes have known calibration issues:

### Adjusted in 0.3.0 per literature

- **`noviceUrban warningVisibilityMeters`**: 0.2.0 set this at 250m
  (+50m over standard). Novice hazard-perception RT is 3.58s vs 1.32s
  experienced ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/));
  at 60 km/h that's ~37m additional reaction-distance from RT alone.
  +50m left no margin. **0.3.0 raises to 320m** (RT-margin + braking
  margin per published novice-fog crash-rate elevation —
  [Konstantopoulos et al PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/)).

- **`ageingRural warningTemperatureCelsius`**: 0.2.0 set this at 1°C
  (+1°C over standard). Black ice forms with road-surface ≤0°C even
  when ambient air is several degrees warmer (well-documented; see
  [Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice)). 1°C
  was barely above the formation envelope. **0.3.0 raises to 2°C** to
  give meaningful margin above the formation threshold.

- **`ageingRural infoTemperatureCelsius`**: 0.2.0 set this at 5°C
  (+2°C over standard). Combined with `infoVisibilityMeters` at 1500m,
  this fires the "info" tier on most autumn evenings in Hokkaido /
  Tohoku — an alert-fatigue risk ([arxiv 2410.06388](https://arxiv.org/html/2410.06388),
  [AAA-FTS ADAS-exposure report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf)).
  Over-warning is a silent safety failure: by the actual black-ice
  morning, the driver has been desensitized. **0.3.0 lowers to 4°C**
  to preserve information-tier signal without firing on routine
  autumn evenings.

### Unverifiable (kept at 0.2.0 values)

- **`safeScoreFloor` / `infoScoreFloor` / `warningScoreFloor` shifts**
  per profile (+0.05 on all three for ageingRural; +0.05, +0.05 and
  +0.02 for noviceUrban) — no published mapping exists between
  numerical safety scores and reaction-time / cognitive-load deltas.
  Score floors stay at 0.2.0 values pending evidence that justifies a
  specific magnitude.

### Wrong dimensions tuned (deferred to broader v0.x or v1.x design)

Literature suggests the dimensions that most-strongly predict crash
risk are NOT the ones we tuned:

- **UFOV (Useful Field of View)** — single strongest older-driver crash
  predictor (86% sensitivity / 84% specificity;
  [Ball et al PubMed 24642933](https://pubmed.ncbi.nlm.nih.gov/24642933/)).
  We expose no peripheral-clutter / map-density / glance-budget
  governor. Adding UFOV-aware governance would require coordination
  with consuming Flutter map / overlay packages.

- **Glance-time budget (NHTSA 2-second / 12-second guidance)** — direct
  safety-of-secondary-task standard ([NHTSA visual-manual guidelines](https://www.nhtsa.gov/document/visual-manual-nhtsa-driver-distraction-guidelines-vehicle-electronic-devices-0)).
  Ties more directly to crash risk than `safeScoreFloor`. Same
  consuming-package coordination needed.

These dimensions are **deferred** — they require coordination across
the package boundary, not a Pure Dart core unilateral change.

---

## Threshold-only differentiation (architectural)

`navigation_safety_core` (Pure Dart) sets thresholds per profile.
**UX behavior** — voice-guidance verbosity, modal-alert duration,
glance-time targets, alert-explainer surfaces — lives in consuming
Flutter packages (`navigation_safety`, `voice_guidance`), and when this
section was written for 0.3.0 it was **not differentiated per
profile** in those packages.

Consequence at 0.3.0: an app developer who called
`NavigationSafetyConfig.forProfile(DriverProfile.ageingRural)` and
integrated with `navigation_safety` (Flutter wrapper) got EARLIER
alerts but in the SAME format as for `snowZoneExperienced`. Same voice
verbosity. Same modal duration. Same glance-time. Same explainer
(none). Both packages have added per-profile behaviour since:
`navigation_safety` 0.9.6 scales the modal-alert duration per profile
(`modalAlertDurationFor`) and, when an alert carries a road-surface
condition, builds its message with
`AlertExplainer.forConditionAndProfile` for the driver profile it is
given; `voice_guidance` 0.7.7 sets a per-profile speaking rate
(`VoiceGuidanceConfig.forProfile`).

The format-mismatch can erase the earlier-alert benefit
([Bian et al PubMed 38669900](https://pubmed.ncbi.nlm.nih.gov/38669900/)
shows earlier triggering reduces collisions only when alerts persist
long enough to be processed; [Strayer/AAA PMC7283540](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283540/)
shows identical voice formats cost older drivers 8+ seconds more
eyes-off-road than younger).

**0.3.0 added `assertUxDifferentiated()`** as a no-op stub. It is no
longer a stub: calling `assertUxDifferentiated(profile)` throws an
`AssertionError` in a debug build when no UX differentiator is
registered for that profile (`registerUxDifferentiator`), and does
nothing in a release build. Selecting a profile does not call it;
integration code has to.

---

## What this document means for consumers

If you are an app developer integrating `navigation_safety_core`:

1. **You may use the package today.** The defects above are real but
   the substrate provides usable per-profile differentiation; the
   threshold direction is correct even where magnitudes are imperfect.
2. **Pin the patch version**, not the minor version, if you need
   stability. Threshold magnitudes are still being calibrated per
   ongoing literature review; minor versions may adjust them.
3. **If you serve a driver-class that none of the six profiles
   fits**, fall back to `DriverProfile.snowZoneExperienced` (the
   standard default) and document the mapping in your own integration
   layer — and consider filing an issue describing your use case so
   the next iteration can incorporate it. A foreign tourist driving in
   an unfamiliar snow zone is not such a class: that driver's profile
   is `DriverProfile.foreignTouristSnowZone`.
4. **For UX-differentiated alert formatting** (voice verbosity, modal
   timing, glance-budget), check what the consuming Flutter package
   you use already differentiates per profile (see "Threshold-only
   differentiation" above) and implement the rest yourself.

---

## RoadSurfaceCondition glossary (added in 0.3.1)

### Black ice not separately enumerated

The 0.3.1 patch adds `RoadSurfaceCondition` aligned to the upstream VSS
allowed-value set (`UNKNOWN, DRY, WET, SNOW, ICE, SLUSH, WET_ICE,
LOOSE_GRAVEL`). [Black ice](https://en.wikipedia.org/wiki/Black_ice) is
a documented sub-class of `ICE` (transparent ice film, hardest to
detect by visual inspection) but is not a distinct enum value because
the upstream VSS signal does not expose it. The glossary acknowledges
this in code comments; it does not invent a value not in the upstream
signal. If a future VSS revision adds black-ice as a distinct allowed
value, this enum updates to match.

### Glossary text is informational only

The 0.3.1 glossary surfaces display labels (`jaName`, `enName`) and
TTS-ready phrases (`jaSpeakString`, `enSpeakString`). It does NOT
actuate any vehicle behavior and is NOT safety-critical in the control
sense (per the package's ASIL-QM display-only stance). Speed
advisories, action-coupled explanations, and alert-density throttling
were planned as separate surfaces for the next minor release, and
shipped in 0.4.0 as `AlertExplainer` and `AlertDensityThrottle`.

### Per-profile vocabulary tested but not yet population-validated

The per-profile speak-string variants (`forConditionAndProfile`) reflect
documented Japanese-driver vocabulary preferences (kanji-native for
`ageingRural`, terse for `snowZoneExperienced` / `professional`,
English-default for `foreignTouristSnowZone`). They are sourced from
JAF / MLIT / NEXCO public driver-guidance materials, not invented.
Population-validation (does each profile's actual cohort prefer the
proposed wording?) is deferred until field-data exists; this is the
same defer pattern as the 0.3.0 threshold magnitudes.

---

## AlertDensityThrottle + AlertExplainer (added in 0.4.0)

### Per-profile caps are literature-anchored DEFAULTS, not population-validated

The 6 per-profile alerts/min cap defaults (`professional` 4.0,
`snowZoneExperienced` 3.0, `agriculturalForestry` 2.0, `noviceUrban`
1.5, `ageingRural` 1.2, `foreignTouristSnowZone` 1.0) come from the
literature anchors cited in `alert_density_throttle.dart` and the
0.4.0 changelog entry — alarm-fatigue ([PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/)),
ADAS exposure ([AAA-FTS](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf)),
hazard-perception RT ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)),
voice-format cost differential by age ([PMC7283540](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283540/)),
novice-fog crash-rate elevation ([PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/)),
and over-warning silent failure ([arxiv 2410.06388](https://arxiv.org/html/2410.06388)).

These are DEFAULTS, not invariants. None of these caps has been
validated against actual population field-data — that work is
deferred until field telemetry exists (the same defer pattern as the
0.3.0 threshold magnitudes and the 0.3.1 per-profile vocabulary).

Integrating apps with measured per-population data should override
via `NavigationSafetyConfig.alertsPerMinuteCapOverride`.

### `bypassForCritical = true` is a documented invariant

The `AlertDensityThrottle` constructor accepts `bypassForCritical`
as a parameter for testability and for forward-compatibility, but the
documented contract is that this stays `true`. Changing the default
to `false` would alter the package's safety contract: the throttle
exists to prevent advisory-tier desensitization, not to mask
high-severity warnings. Any change to this default in a future
release requires an explicit decision by the package maintainers.

### Action-string speed references are advisory, not enforced

The action strings produced by `AlertExplainer.forConditionAndProfile`
include speed references (30 km/h, 20 km/h). These are published
reference points sourced from JAF / MLIT public driver-guidance
materials, expressed in advisory mood (「以下に減速」 / "Slow to" /
"drive below"). The package does NOT actuate the vehicle. The driver
retains full speed authority. Applications integrating these strings
must not present them as system-enforced limits.

### Per-profile action vocabulary not yet population-validated

The 36 (condition × profile) action strings reflect documented
Japanese-driver vocabulary preferences and the per-profile verbosity
mapping designed for this release. Population-validation (does each
profile's actual cohort prefer the proposed wording?) is deferred
until field-data exists — same defer pattern as the 0.3.1 per-profile
glossary speak-strings.

### Cap arithmetic uses strict less-than

`AlertDensityThrottle.shouldFire` admits a new alert when
`in_window_count < cap`. With `cap = 1.5` and 1 prior alert in the
window, 1 < 1.5 → fire (count becomes 2); with 2 prior, 2 < 1.5 is
false → drop. This is the documented semantic — fractional caps
function as integer ceilings on per-window count. Apps that need
strict integer caps should pass an integer literal as the override.

---

## `looms.dart` barrel + `LOOMS.md` (added in 0.4.1)

### No runtime registry

The `lib/src/looms.dart` barrel, added in 0.4.1, re-exports the
runtime looms (`AlertDensityThrottle`, `AlertExplainer` and
`LoomFitTelemetry`) under a category-level doc-comment, and `LOOMS.md`
describes `AlertDensityThrottle` and `AlertExplainer`. The catalog
does NOT auto-discover its members: there is
no runtime registry, no introspection at app start, and no
auto-instantiation. Integrating apps instantiate each loom explicitly
where they wire it into their alert pipeline. A reflection-based or
code-generated registry is **deferred** to a future minor release
(likely v0.5+) — once enough runtime looms exist that explicit wiring
becomes a meaningful integration cost.

---

## Standards mapping (current advisory framing)

This section declares the package's working standards-mapping framing
under the current advisory-only shape. It is the package authors'
internal interpretation under documented design discipline, not a
certified classification. Where the mapping is conditional or
undetermined, this section flags it explicitly so integrators can
re-run the classification at their own integration boundary.

### ISO 26262 (functional safety, road vehicles)

The package's surfaces — `AlertSeverity`, `AlertExplainer`,
`AlertDensityThrottle`, `SafetyScore`, `NavigationSafetyConfig`,
`RoadSurfaceCondition` — are HMI for safety-relevant **advisories**.
They inform the driver; they never actuate the vehicle, never close a
control loop, and never participate in an automation-handover safety
contract.

Under that framing, the package likely sits at **QM (quality-managed,
no ASIL)** at the application layer. The wording discipline supports
this framing: `AlertExplainer` action verbs are advisory-mood, not
imperative-on-control; speed numbers are published reference points
sourced from public driver-guidance materials (JAF / MLIT / NEXCO),
not system-enforced limits; no action string promises an outcome.
`AlertDensityThrottle.bypassForCritical = true` is documented as a
safety contract: criticals always fire. These choices are consistent
with QM at the application layer.

**FLAG: undetermined at the integration boundary.** Whether ISO 26262
governs a specific deployment depends on the **integrator's hazard
analysis**, not on this package alone. If an integrator builds a
deployment where this package's alerts are part of a driver-supervision
loop whose closure includes alert acknowledgment, or where actuation
depends on an alert chain, the ASIL classification can rise. **The
integrator owns the final ASIL determination for their integration.**
Evidence supporting current QM-likely framing lives in the wording
discipline cited above and in the `bypassForCritical` invariant; that
evidence does not certify any specific ASIL outcome.

### SAE J3016 (driving automation levels)

This package is **L0 / L1 supportive**: the driver performs the
dynamic driving task (DDT); the alert is supportive; loss of an alert
frame degrades support but does not lose a fallback. This is the
most-permissive regime under J3016, and it matches the package's
current shape.

**Non-claim on L2+.** Consumers operating at L2 or above are
responsible for adding their own handover-class supervision —
take-over-request signalling, driver-attention monitoring,
minimum-risk-manoeuvre fallback. This package does not provide those
surfaces. Treating advisory output as the supervision surface in a
partial-or-higher-automation regime is a misuse of the package's
documented scope.

If a consuming app evolves toward L2+ pilots, the substrate-fitness
question for this package's surfaces would need to be re-asked under
the J3016 handover-class safety contract — that work is **out of
scope today** and would require explicit re-classification.

### JIS / JASO (Japanese-domestic automotive standards)

**FLAG: not mapped at this scope.** Japanese-domestic HMI standards
likely apply to deployments targeting the Japanese-domestic
certification surface — for example JASO Z 008 driver-information
display guidelines and JIS D 0207 series for display ergonomics — but
this package has not done a deep mapping against those standards.
The action-string vocabulary in `AlertExplainer` is sourced from
public driver-guidance materials (JAF, MLIT, NEXCO), which are
public-corpus anchors rather than certified JIS/JASO-conformant text.

**Recommendation for vendor / OEM integration**: when a consuming app
moves toward IVI-vendor or OEM-pilot integration that targets the
Japanese-domestic certification surface, run a dedicated JIS / JASO
conformance pass via a **qualified Japanese-domestic functional-safety
partner** before substrate adoption. The package authors' internal
interpretation does not substitute for certification.

### Equal-dignity invariant: severity-driven, not profile-driven

Cross-package design invariant for any HMI built on top of this
package: **alert visibility, severity ordering, and plane-allocation
priority in the consuming HMI must be severity-driven, never
profile-driven.** Per-profile differentiation has a legitimate home in
verbosity (`AlertExplainer` `VerbosityLevel`), in locale tagging
(`AlertExplainer` locale), and in density-cap behaviour
(`AlertDensityThrottle.forProfile` / `defaultCapFor`). It does NOT
have a legitimate home in:

- the visibility decision (does the alert reach the driver at all?)
- severity preemption order (does a critical preempt a warning?)
- hardware-overlay-plane allocation in a display-server / KMS layer
  (which alert is composed onto a hardware overlay plane vs. software-
  composited fallback?)

Encoding `DriverProfile` into any of those three paths would create a
"VIP-path" failure: a `professional` profile alert reaches the driver
faster or with higher fidelity than a `foreignTouristSnowZone` alert
under contention. That is a violation of equal-dignity-per-driver-class
and is incompatible with the package's documented design intent.
Consumers that want profile-aware behaviour must route it through the
density cap and the explainer-verbosity surface, NOT through
visibility, preemption, or plane allocation.

This invariant is named here so it is preserved across the package
boundary and inherited by any HMI / display-server integration that
consumes these surfaces.

---

## Driving-context formulas (added in 0.5.0)

The 0.5.0 minor release adds a context-aware factory
`NavigationSafetyConfig.forProfileWithContext(profile, context: ...)`
that adjusts thresholds based on a `DrivingContext` value-object
carrying optional speed, humidity, precipitation-history, and ambient
temperature inputs. The factory is purely additive: the existing
`forProfile()` factory is unchanged, and a null context delegates to
`forProfile()`. No existing call site is affected.

The new factory composes three formulas, provided since 0.11.0 by the
standalone `navigation_safety_calibration` dependency (re-exported from
core's barrel; formerly vendored under `lib/src/calibration/`):

### Speed-dependent visibility floor (`speed_dependent_visibility.dart`)

Returns `max(profileBase, RT_distance + braking_distance)` where
`RT_distance = reactionTime × speed` and
`braking_distance = speed² / (2 × deceleration)`. Standard kinematics.

Reaction-time per-profile defaults are documented in the module
header and used by the factory. Two of the six are
literature-anchored:

- `noviceUrban` 3.58s — sourced from
  [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)
  (hazard-perception RT 3.58s novice vs 1.32s experienced).
- `ageingRural` 2.5s — older drivers; published distribution.

The other four (`snowZoneExperienced` 1.8s, `professional` 1.5s,
`agriculturalForestry` 2.0s, `foreignTouristSnowZone` 3.5s) are
derived defaults rather than direct cites:

- `professional` 1.5s — bracketed by professional-truck-driver
  simulator work ([Driver Response Time and Age Impact, MDPI](https://www.mdpi.com/2227-7390/10/9/1489),
  [Evaluation of Driver's Reaction Time PMC9099898](https://pmc.ncbi.nlm.nih.gov/articles/PMC9099898/))
  reporting professional-driver RT around 1.0–1.35s in controlled
  conditions; 1.5s sits as a conservative on-road default with margin.
- `snowZoneExperienced` 1.8s — derived as the experienced-baseline
  1.32s ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/))
  plus a surface-friction margin for snow/ice; no single source
  quotes this composite directly.
- `agriculturalForestry` 2.0s — informed by the FHWA rural-roadway
  finding that drivers familiar with rural roadways show **slower**
  brake-activation RT than unfamiliar drivers in sudden-event
  scenarios ([FHWA Rural Two-Lane Curved Roadways](https://www.fhwa.dot.gov/publications/research/safety/12073/index.cfm))
  combined with the ageing-farmer demographic profile (average ~60y
  with documented age-related RT slowing — 2–6 ms per decade plus
  task-load multipliers per
  [PMC9423772](https://pmc.ncbi.nlm.nih.gov/articles/PMC9423772/)).
  The 2.0s default is a directional bracket; no single source quotes
  this exact value.
- `foreignTouristSnowZone` 3.5s — bracketed by the novice
  hazard-perception RT of 3.58s
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/))
  on the assumption that foreign tourists driving Hokkaido / Tohoku
  snow roads for the first time face a novice-equivalent
  hazard-perception load on the snow-specific axis (rental-car
  industry reports document concrete tourist-accident clusters at
  TOMARE intersections and on whiteout-prone passes — see
  [ExploreLifeHub Hokkaido Winter Driving](https://www.explorelifehub.com/en/hokkaido-winter-driving-guide/),
  [Powderlife driving and surviving Hokkaido winters](https://www.powderlife.com/blog/driving-surviving-hokkaido-winters/)).
  The exact magnitude remains an engineering bracket; no source
  quotes 3.5s for this specific population.

Same defer pattern as the 0.3.1 per-profile vocabulary speak-strings
and the 0.4.0 density caps — these are literature-informed defaults,
not field-validated population values.

The factories compute this floor with the calibration's default
braking deceleration, 5.5 m/s² (typical dry pavement). No parameter of
`forProfileWithContext`, `forDriverContext` or `DrivingContext` takes
a different value, so the speed floor they return assumes dry-pavement
braking on every surface. Surface friction is the dominant variable
and no single default fits every road condition: on compacted snow
(about 3.0 m/s²) or glare ice (about 1.5 m/s², the calibration's own
figures), reacting and stopping takes more distance than the floor
the factories return in 19 of the 30 cases measured (each profile at
60, 80, 100, 110 and 130 km/h, with speed the only input). At 80 km/h
`snowZoneExperienced` gets a 200 m floor, and stopping on glare ice
after its 1.8 s reaction time takes 204.6 m.
`computeSpeedAdjustedVisibilityMeters`, which this package re-exports,
accepts `brakingDecelerationMps2`; the factories do not pass it.

### Humidity-dependent effective temperature (`humidity_dependent_temperature.dart`)

Computes a dew-point-based effective road-surface temperature using the
Magnus formula (Magnus 1844; modern parameter constants `a = 17.625`,
`b = 243.04°C` per Alduchov & Eskridge 1996). Black ice can form on a
road surface when ambient air is several degrees above 0°C if
clear-sky radiative cooling drops the surface to the dew point — see
[Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice).

The approximation `effective = ambient - depression` is anchored in
documented road-meteorology physics: on clear nights with light winds,
road surfaces commonly cool 2–5 °F (≈1.1–2.8 °C) below ambient air
temperature via radiative cooling, and the surface temperature must
reach the dew point for frost / ice formation
([Roadway Icing and Weather tutorial, U. Washington](https://www.atmos.washington.edu/~cliff/Roadway3.html);
[Investigating Road Ice Formation Mechanisms, MDPI Climate](https://www.mdpi.com/2225-1154/12/5/63);
[Wikipedia radiative cooling](https://en.wikipedia.org/wiki/Radiative_cooling)).
Modern Magnus parameter constants (a = 17.625, b = 243.04 °C) are
from Alduchov & Eskridge 1996.

The approximation remains **directional but UNVERIFIED** for any
specific surface as a predicted ground-truth measurement: the actual
surface temperature depends on emissivity, sky cloud cover, surface
material, time-of-night, and wind speed. No single published value
captures every road context. Treat the output as a frost-risk
indicator anchored in published radiative-cooling magnitudes, not a
measured surface temperature.

### Precipitation-history exponential decay (`precipitation_history_decay.dart`)

Returns `exp(-ln2 × t / halfLife)` clamped to `[0, 1]`. Default
half-life 90 minutes — **deliberately conservative** so the consuming
app warns longer rather than shorter on residual surface moisture.
Most road surfaces dry faster under sun and wind; some dry slower
(shaded, cold, low-wind environments).

Research attempted: published road-pavement and urban-surface
evaporation work
([Mechanisms and Empirical Modeling of Evaporation from Hardened
Surfaces in Urban Areas, PMC7917919](https://pmc.ncbi.nlm.nih.gov/articles/PMC7917919/))
documents first-order-evaporation as the standard model and reports
that hardened-surface evaporation occupies 16–29% of total urban
evaporation, with cooling effects from precipitation lasting on the
order of "a few days." Practical-engineering guidance commonly cites
asphalt drying timeframes of 48–72 hours under typical conditions,
with relative humidity above 80% roughly doubling drying time. None
of these sources publishes a single half-life value for residual
surface-moisture impact on driver-relevant friction. **The 90-minute
default remains UNVERIFIED as a population value;** it sits at a
conservatively short fraction of the practical-drying envelope so
the warning fires longer rather than shorter. Consumers with
telemetry that informs a more accurate half-life should override.

The exponential-decay shape is the standard first-order-evaporation
model used in pavement-engineering and atmospheric-science references;
the `ambientCelsius` parameter is accepted for forward-compatible API
shape but does not currently modulate the half-life. A future revision
may modulate it without an API break.

### API surface is additive only

`NavigationSafetyConfig.forProfile(profile)` is unchanged in 0.5.0.
The new `forProfileWithContext(profile, context: ...)` factory adds
context-aware adjustments alongside the existing factory. The
per-profile baseline acts as a floor for every threshold: context can
only warn earlier (raise the floor / shift toward conservative), never
later. That does not hold when the context carries a vehicle-class
token (0.9.0) and the registry's class implements
`VehicleThresholdOverrides`, or extends it and replaces
`applyOverrideForToken`, with a method that does not return what this
package's `applyOverrideForToken` returns: what that method returns
is applied unchecked, even a warning threshold below the baseline
(see `SAFETY_BOUNDARY.md` section 7.2). Consumers that do not pass a
context, or pass a context with
all fields null, receive the same configuration as
`forProfile(profile)` — no behaviour change.

The equal-dignity invariant continues to apply: severity-driven
visibility, severity ordering, and plane allocation are not affected
by the new factory or by `DrivingContext`. Context tunes thresholds,
not the severity of the resulting alerts.

---

## Why this list is published

The package is meant to help drivers, including drivers caught by
unexpected snow. Silent gaps are a worse failure than acknowledged
ones, so this document names, where any consumer can see them, the
gaps the package cannot show by itself.

If you spot a gap not listed here, please open an issue. The list grows
with what we hear, not with what we hide.
