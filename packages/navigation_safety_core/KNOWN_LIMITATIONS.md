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
  12:00 / 16:00 / 20:00), the order of the multipliers and their
  values are recorded decisions, meant to reflect sleep inertia after
  waking, a post-lunch dip, fatigue building through the evening and
  an overnight low. No source is cited for any of them. The values are
  conservative-only (every multiplier `>= 1.0`). Per-population
  calibration is deferred pending fleet-class field measurement.
- **`CumulativeFatigueClass` day-thresholds** (`rested` 0–2 / `mild`
  3–4 / `accumulated` 5–6 / `severe` 7+). The boundaries are
  design-default hypotheses; the integrator's own fleet-class data
  may show different empirical breakpoints. The **per-class
  visibility lifts** (`mild` +25m / `accumulated` +50m / `severe`
  +100m) are similarly conservative engineering-judgement values
  pending field-measurement validation.
- **`Confidence` cap modifiers** (low: cap × 0.75 with floor 1.0
  alerts/min; high-confirmed: cap × 1.25). The 25% magnitude is
  engineering judgement, a recorded decision. No source is cited for an
  alert-density bound or for mapping driver self-assessed confidence to
  a change in the cap. Per-population calibration is deferred.

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
  matrix is a v1.0
  architecture decision; 0.10.0 ships the orthogonal axes and the
  composition factory only.

---

## DriverState (state-axis spike, added in 0.6.0) — UNVERIFIED magnitudes

The `DriverState` enum and `DriverContext` trait/state composite were
added in 0.6.0 per Regan and Strayer 2014 (PMC4001671), whose account
of the Regan, Hallett and Gordon 2011 taxonomy names driver conditions
(e.g. young, inexperienced, old) and driver states (e.g. bored, sleepy,
fatigued, drugged, emotional) as factors that may give rise to
inattention processes or moderate their impact. The **shape** of the
API is intentional and stable for this spike; the **magnitudes** of
the per-state delta
applied by `NavigationSafetyConfig.forDriverContext` are NOT
literature-anchored and are placeholders pending state-axis
calibration.

### What is UNVERIFIED at 0.6.0

- **`fatigued` state** — reaction-time penalty (+0.5 s) and warning-
  temperature lift (+1 °C). Both magnitudes are engineering
  judgement, recorded decisions. Williamson & Feyer 2000
  ([PubMed 10984335](https://pubmed.ncbi.nlm.nih.gov/10984335/))
  reports that after 17–19 hours without sleep, "performance on some
  tests was equivalent or worse than that at a BAC of 0.05%", that
  "Response speeds were up to 50% slower for some tests and accuracy
  measures were significantly poorer than at this level of alcohol",
  and that after longer periods without sleep performance reached
  levels equivalent to a BAC of 0.1%. It reports test performance, not
  a driving reaction time in seconds, so it does not give the +0.5 s.
  Per-hour-of-wakefulness calibration is deferred pending field
  telemetry. No source is cited for the fatigue-to-frost-margin
  mapping behind the +1 °C lift.
- **`distracted` state** — reaction-time penalty (+1.0 s). The
  magnitude is engineering judgement, a recorded decision. Strayer &
  Drews 2007, "Cell-Phone–Induced Driver Distraction"
  ([doi:10.1111/j.1467-8721.2007.00489.x](https://doi.org/10.1111/j.1467-8721.2007.00489.x)),
  found in simulated driving that drivers in a hands-free cell-phone
  conversation were less likely to form a durable memory of objects
  they looked at. The AAA Foundation for Traffic Safety report
  "Cognitive Distraction: Something to Think About" (June 2013,
  [PDF](https://aaafoundation.org/wp-content/uploads/2026/01/CognitiveDistractionReport.pdf))
  describes degraded peripheral detection, brake reaction time and
  visual scanning when drivers engage in secondary tasks. Neither
  gives a reaction-time penalty in seconds. Per-task calibration
  (texting vs. conversation vs. nav-menu) is deferred.
- **`impairedVisibility` state** — visibility-tier scale-up (×1.25).
  The eLife article "Foggy perception slows us down"
  ([eLife article](https://elifesciences.org/articles/00031)) reports
  that drivers "recorded an average speed of 85.1 km/hr when the
  visibility was good, and this dropped to 70.9 km/hr in severe fog".
  It does not give a visibility-tier multiplier, and no source is
  cited for one across fog / whiteout / glare; the ×1.25 is a recorded
  decision, UNVERIFIED, and will be refined when a per-condition
  multiplier is field-calibrated.
- **`alert` state** — no delta applied; this is by definition the
  baseline and is verified to be unchanged from 0.5.0 behaviour.

### What is verified at 0.6.0

- **API shape** — trait × state separation per Regan and Strayer 2014
  (PMC4001671): driver conditions (e.g. young, inexperienced, old)
  and driver states (e.g. bored, sleepy, fatigued, drugged, emotional).
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

- **Foreign-tourist driver in unfamiliar snow-zone.** A Hokkaido
  winter-driving guide relays rental-car operators' accounts of
  tourist accidents, including "three separate tourist accidents at
  TOMARE intersections" in one winter
  ([reference](https://www.explorelifehub.com/en/hokkaido-winter-driving-guide/));
  it gives no accident rate. The class is currently
  mis-mappable to either `snowZoneExperienced` (wrong — they have neither
  experience nor local equipment) or `noviceUrban` (location-wrong).
  **Addressed in 0.3.0** with new profile `foreignTouristSnowZone`.

- **Driver with sensory disability** (deaf / low-vision / hearing-aid user).
  Published work studies drivers with vision loss as a group with
  their own difficulties: Xu et al. 2023
  ([PMC10561786](https://pmc.ncbi.nlm.nih.gov/articles/PMC10561786/))
  found that drivers with central vision loss "reported more
  difficulty" and "greater usefulness of technology support" than
  drivers without it. No source is cited for deaf or hard-of-hearing
  drivers; that study excluded people whose hearing impairment
  prevented them from completing its survey by voice.
  No accessibility axis in v0.2.0 / v0.3.0. **Deferred** until the design
  for cross-cutting accessibility axes is settled (likely v0.4 or later
  in coordination with consuming Flutter packages).

### Trait-only taxonomy

The six profiles encode driver **trait** (who-the-driver-is). Published
work (Regan and Strayer 2014 —
[PMC4001671](https://pmc.ncbi.nlm.nih.gov/articles/PMC4001671/))
lists driver conditions (e.g. young, inexperienced, old) and driver
**states** (e.g. bored, sleepy, fatigued, drugged, emotional) as factors
in driver inattention.
A `DriverState` axis crossed with `DriverProfile` would match how risk
is actually modeled. **Addressed in 0.6.0** with `DriverState` and
`DriverContext` (see the DriverState section above); the full trait ×
state matrix with per-cell calibration remains a v1.0 architecture
decision.

### Frailty-vs-robust split inside `ageingRural`

Liu et al. 2020, "Frailty phenotype associated with traffic crashes
among older drivers: A cross-sectional study in rural Japan"
([ScienceDirect S2214140520301134](https://www.sciencedirect.com/science/article/abs/pii/S2214140520301134)),
reports in its title an association between the frailty phenotype and
traffic crashes among older drivers in rural Japan. Our `ageingRural`
is monolithic. **Deferred** until sub-cohort granularity is justified
by evidence.

---

## Threshold magnitudes (added in 0.2.0)

The threshold deltas per profile were initially chosen by intuitive
"more conservative" reasoning rather than published literature. The
direction of each shift is correct (older + less experienced = warn
earlier); the magnitudes have known calibration issues:

### Adjusted in 0.3.0

- **`noviceUrban warningVisibilityMeters`**: 0.2.0 set this at 250m
  (+50m over standard). **0.3.0 raises to 320m**, a recorded decision
  meant to give a novice driver more reaction and braking margin; no
  source is cited for the value. Sagberg and Bjørnskau 2006
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)), whose
  abstract gives no reaction times in seconds, found that average
  hazard-perception reaction times "tended to decrease with
  experience, but the decrease was not significant", with "some
  significant differences in the expected direction for individual
  test items". Mueller and Trick 2012
  ([PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/)) found
  in a driving simulator that novice drivers "had higher hazard
  response times, greater speed and steering variability, and were
  the only drivers to have collisions".

- **`ageingRural warningTemperatureCelsius`**: 0.2.0 set this at 1°C
  (+1°C over standard). Black ice can form on a road surface below
  0°C while the air is above it: per
  [Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice), it
  "may form even when the ambient temperature is several degrees above
  the freezing point", if the air warms suddenly after a prolonged
  cold spell has left the road surface well below freezing. **0.3.0
  raises to 2°C**, a recorded decision, to give more margin.

- **`ageingRural infoTemperatureCelsius`**: 0.2.0 set this at 5°C
  (+2°C over standard). Combined with `infoVisibilityMeters` at 1500m,
  5°C was judged to fire the "info" tier too often on autumn evenings
  in Hokkaido / Tohoku, an alert-fatigue risk; how often it fires has
  not been measured. In a driving-simulator study of a
  pedestrian-crossing alert system
  ([arxiv 2410.06388](https://arxiv.org/html/2410.06388)), "Seven
  participants indicated that repeated false alarms reduced their
  trust in the system, leading to alert fatigue and, in some cases,
  ignoring subsequent warnings altogether." That study compared alert
  modalities and false alarms, not the rate of alerts about a real
  condition. **0.3.0 lowers to 4°C**, a recorded decision, to keep the
  information tier while firing it in fewer conditions.

### Unverifiable (kept at 0.2.0 values)

- **`safeScoreFloor` / `infoScoreFloor` / `warningScoreFloor` shifts**
  per profile (+0.05 on all three for ageingRural; +0.05, +0.05 and
  +0.02 for noviceUrban) — this package cites no published mapping
  between numerical safety scores and reaction-time / cognitive-load
  deltas.
  Score floors stay at 0.2.0 values pending evidence that justifies a
  specific magnitude.

### Wrong dimensions tuned (deferred to broader v0.x or v1.x design)

Published work points to dimensions that relate to crash risk and
that we did not tune:

- **UFOV (Useful Field of View)** — Wood and Owsley 2014
  ([PubMed 24642933](https://pubmed.ncbi.nlm.nih.gov/24642933/))
  describe the test as "one of the most extensively researched and
  promising predictor tests for a range of driving outcomes measures,
  including driving ability and crash risk", and add that its
  sensitivity and specificity in predicting future crash involvement
  need to be more fully evaluated in large prospective
  population-based studies.
  We expose no peripheral-clutter / map-density / glance-budget
  governor. Adding UFOV-aware governance would require coordination
  with consuming Flutter map / overlay packages.

- **Glance-time budget (NHTSA 2-second / 12-second guidance)** — the
  NHTSA Visual-Manual Driver Distraction Guidelines are "nonbinding,
  voluntary" guidelines, not a standard
  ([78 FR 24818](https://www.federalregister.gov/d/2013-09883)). They
  recommend that devices be designed so that tasks can be completed
  while driving "with glances away from the roadway of 2 seconds or
  less and a cumulative time spent
  glancing away from the roadway of 12 seconds or less", and note that
  glances away from the forward road scene longer than 2.0 seconds are
  correlated with increased crash or near-crash risk. That ties to
  crash risk more directly than `safeScoreFloor`, for which no mapping
  is cited here. Same consuming-package coordination needed.

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
   stability. Threshold magnitudes are recorded decisions, not
   field-validated; minor versions may adjust them.
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
a sub-class of `ICE` (the ice "is not black, but visually
transparent", and patches of it are "often next to invisible to
drivers") but is not a distinct enum value because
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

The per-profile speak-string variants (`forConditionAndProfile`) are
the package's recorded wording decisions (kanji-native for
`ageingRural`, terse for `snowZoneExperienced` / `professional`,
English-default for `foreignTouristSnowZone`). No source is cited for
these preferences or this vocabulary; JAF's snow-driving
page (https://jaf.or.jp/common/attention/snow) uses ブラックアイスバーン
and アイスバーン but not 圧雪 or シャーベット.
Population-validation (does each profile's actual cohort prefer the
proposed wording?) is deferred until field-data exists; this is the
same defer pattern as the 0.3.0 threshold magnitudes.

---

## AlertDensityThrottle + AlertExplainer (added in 0.4.0)

### Per-profile caps are recorded-decision DEFAULTS, not population-validated

The 6 per-profile alerts/min cap defaults (`professional` 4.0,
`snowZoneExperienced` 3.0, `agriculturalForestry` 2.0, `noviceUrban`
1.5, `ageingRural` 1.2, `foreignTouristSnowZone` 1.0) are a recorded
decision; no source is cited for any of the six values. The sources
below show the failure a cap is meant to guard against, not the
values: an
alarm-fatigue review in health care
([PMC12181921](https://pmc.ncbi.nlm.nih.gov/articles/PMC12181921/))
describes "repeated exposure to frequent or non-actionable alarms"
leading to "a gradual desensitization or reduced responsiveness"
among health-care professionals; a hazard-perception study
([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)) found
"a possible effect of experience" on individual test items; and a
driving-simulator study
([PubMed 22664714](https://pubmed.ncbi.nlm.nih.gov/22664714/)) found
novice drivers "had higher hazard response times" and "were the only
drivers to have collisions".

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
include speed references (30 km/h, 20 km/h). These are the package's
own advisory reference points, a recorded decision: no source is
cited for them, and JAF's snow-driving page
(https://jaf.or.jp/common/attention/snow) gives no speed figure. They
are expressed in advisory mood (「以下に減速」 / "Slow to" /
"drive below"). The package does NOT actuate the vehicle. The driver
retains full speed authority. Applications integrating these strings
must not present them as system-enforced limits.

### Per-profile action vocabulary not yet population-validated

The 36 (condition × profile) action strings are the package's recorded
wording and per-profile verbosity decisions for this release; no
source is cited for the vocabulary preferences they encode.
Population-validation (does each profile's actual cohort prefer the
proposed wording?) is deferred until field-data exists — same defer
pattern as the 0.3.1 per-profile glossary speak-strings.

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
imperative-on-control; speed numbers are advisory reference points
chosen by the package, not system-enforced limits; no action string
promises an outcome.
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
certification surface, but this package has not identified which
JIS or JASO documents apply and has not mapped against any of them.
The action-string vocabulary in `AlertExplainer` is the package's own
wording, not certified JIS/JASO-conformant text.

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
header and used by the factory. All six are recorded decisions. The
sources listed below are context; none is cited as the source of a
value.

- `noviceUrban` 3.58s and `snowZoneExperienced` 1.8s — Sagberg and
  Bjørnskau 2006
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)), whose
  abstract gives no reaction times in seconds, found that average
  hazard-perception reaction times "tended to decrease with
  experience, but the decrease was not significant". The 1.8s is
  meant to add a surface-friction margin for snow/ice to an
  experienced-driver baseline.
- `ageingRural` 2.5s — no source is cited for this value.
- `professional` 1.5s — Poliak et al. 2022
  ([MDPI Mathematics 10(9) 1489](https://www.mdpi.com/2227-7390/10/9/1489))
  set out "to verify whether the mean reaction time of professional
  drivers is at the level of one second" in a simulator study of
  professional truck drivers; its results are not cited here. Čulík
  et al. 2022
  ([PMC9099898](https://pmc.ncbi.nlm.nih.gov/articles/PMC9099898/))
  measured 30 drivers with an average age of about 22 in a truck-cabin
  training simulator; it is not a study of professional drivers.
- `agriculturalForestry` 2.0s — the FHWA report on rural two-lane
  curved roadways
  ([FHWA-HRT-12-073](https://www.fhwa.dot.gov/publications/research/safety/12073/index.cfm))
  relays an earlier finding that "familiar drivers had significantly
  slower reaction times to activate brakes compared to unfamiliar
  drivers when sudden events (e.g., a car pulling out) occurred in the
  roadway"; its own simulator study included no sudden events.
  Hardwick et al. 2022
  ([PMC9423772](https://pmc.ncbi.nlm.nih.gov/articles/PMC9423772/))
  state that reaction times in simple tasks "slow with age at a rate
  of 2–6 ms per decade" and that more complex tasks show greater
  differences between young and old participants. No source is cited
  for an agricultural or forestry driver's age.
- `foreignTouristSnowZone` 3.5s — set close to the novice value on the
  assumption that a tourist driving Hokkaido / Tohoku snow roads for
  the first time faces a novice-like hazard-perception load. A
  Hokkaido winter-driving guide relays rental-car operators' accounts
  of tourist accidents at 止まれ (TOMARE) stop-sign intersections
  ([ExploreLifeHub Hokkaido Winter Driving](https://www.explorelifehub.com/en/hokkaido-winter-driving-guide/));
  it gives no accident rate and no reaction time.

Same defer pattern as the 0.3.1 per-profile vocabulary speak-strings
and the 0.4.0 density caps — these are recorded-decision defaults,
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
`b = 243.04°C` per Alduchov & Eskridge 1996). Radiative cooling "can
cause frost or black ice to form on surfaces exposed to the clear
night sky, even when the ambient temperature does not fall below
freezing" ([Wikipedia radiative cooling](https://en.wikipedia.org/wiki/Radiative_cooling)).

The approximation `effective = ambient - depression` is a recorded
modelling decision, and the observations cited point in more than one
direction. The University of Washington roadway-icing tutorial
([Roadway Icing and Weather tutorial, U. Washington](https://www.atmos.washington.edu/~cliff/Roadway3.html))
says frost "tends to occur on cold, relatively clear nights when wind
speeds are low", that on such nights "temperature at ground level can
be 2-5F cooler than air temperature only a few feet above", and that
the air near the surface can cool to the dew point. Road Weather
Information System observations in Montana
([Investigating Road Ice Formation Mechanisms, MDPI Climate](https://www.mdpi.com/2225-1154/12/5/63))
found that road ice formed only when the pavement surface was at or
below 0 °C while the 2 m air temperature could be above it, but also
that on clear roads the "surface pavement temperature is generally
warmer than the air temperature during both day and night", unlike
natural land surfaces, and that bridges and lake-side roads lose more
heat. Modern Magnus parameter constants (a = 17.625, b = 243.04 °C)
are from Alduchov & Eskridge 1996.

The approximation remains **UNVERIFIED** for any specific surface as
a predicted ground-truth measurement: the actual surface temperature
depends on emissivity, sky cloud cover, surface material,
time-of-night, and wind speed. No single value is cited for every
road context. Treat the output as a frost-risk
indicator, not a measured surface temperature.

### Precipitation-history exponential decay (`precipitation_history_decay.dart`)

Returns `exp(-ln2 × t / halfLife)` clamped to `[0, 1]`. Default
half-life 90 minutes, a recorded decision. The fraction adds a margin
to the warning visibility floor that shrinks as the fraction decays,
so a longer half-life keeps the added warning distance longer; no
source is cited showing that 90 minutes is conservative. Drying time
varies with sun, wind, shade and cold.

Research attempted: published urban-surface evaporation work
([Mechanisms and Empirical Modeling of Evaporation from Hardened
Surfaces in Urban Areas, PMC7917919](https://pmc.ncbi.nlm.nih.gov/articles/PMC7917919/))
reports that the "evaporation of hardened surfaces occupies 16–29% of
the total amount of evaporation in the built-up areas in cities", and
that the "water content of the concrete layer had been in the peak for
a few days after the rain". It publishes no half-life for residual
moisture on a road surface and does not describe drying as
exponential. **The 90-minute default remains UNVERIFIED as a
population value.** Consumers with telemetry that informs a more
accurate half-life should override.

The exponential-decay shape is a recorded modelling decision; no
source is cited for it. The `ambientCelsius` parameter is accepted for
forward-compatible API shape but does not currently modulate the
half-life. A future revision may modulate it without an API break.

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
