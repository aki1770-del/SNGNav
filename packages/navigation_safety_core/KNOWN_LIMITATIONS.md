# Known limitations

This document lists known limitations of the current `navigation_safety_core`
package, with citations to public sources, so that consumers can integrate
with eyes open and contribute corrections from informed positions.

The list is honest by intent — surfacing what we don't yet know rather
than letting silent gaps reach drivers.

---

## DriverProfile taxonomy (added in 0.2.0)

### Missing classes

The 5 v1 profiles (`ageingRural`, `snowZoneExperienced`, `noviceUrban`,
`professional`, `agriculturalForestry`) do not yet cover:

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

The 5 profiles encode driver **trait** (who-the-driver-is). Industry
literature (Regan, Hallett & Gordon 2011 —
[PMC4001671](https://pmc.ncbi.nlm.nih.gov/articles/PMC4001671/))
separates trait from **state** (drowsy / distracted / alert / asleep).
A `DriverState` axis crossed with `DriverProfile` would match how risk
is actually modeled. **Deferred** — adding a state axis is a v1.0
architecture decision, not a v0.x patch.

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
  Tohoku — V14 alert-fatigue risk ([arxiv 2410.06388](https://arxiv.org/html/2410.06388),
  [AAA-FTS ADAS-exposure report](https://aaafoundation.org/wp-content/uploads/2023/09/202309-AAAFTS-ADAS-Exposure-and-Driver-Workload.pdf)).
  Over-warning is a silent safety failure: by the actual black-ice
  morning, the driver has been desensitized. **0.3.0 lowers to 4°C**
  to preserve information-tier signal without firing on routine
  autumn evenings.

### Unverifiable (kept at 0.2.0 values)

- **`safeScoreFloor` / `infoScoreFloor` / `warningScoreFloor` shifts of
  +0.05** per profile (ageingRural / noviceUrban) — no published
  mapping exists between numerical safety scores and reaction-time /
  cognitive-load deltas. Score floors stay at 0.2.0 values pending
  evidence that justifies a specific magnitude.

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
Flutter packages (`navigation_safety`, `voice_guidance`) and is **not
yet differentiated per profile** in those packages.

Consequence: today an app developer who calls
`NavigationSafetyConfig.forProfile(DriverProfile.ageingRural)` and
integrates with `navigation_safety` (Flutter wrapper) gets EARLIER
alerts but in the SAME format as for `snowZoneExperienced`. Same voice
verbosity. Same modal duration. Same glance-time. Same explainer
(none).

The format-mismatch can erase the earlier-alert benefit
([Bian et al PubMed 38669900](https://pubmed.ncbi.nlm.nih.gov/38669900/)
shows earlier triggering reduces collisions only when alerts persist
long enough to be processed; [Strayer/AAA PMC7283540](https://pmc.ncbi.nlm.nih.gov/articles/PMC7283540/)
shows identical voice formats cost older drivers 8+ seconds more
eyes-off-road than younger).

**0.3.0 adds `assertUxDifferentiated()` scaffolding** — a runtime
advisory that fires when a profile is selected but the consuming UX
layer has not registered a differentiator. Today the advisory is a
no-op stub; full implementation requires coordination with consuming
Flutter packages and lands in v0.4+.

---

## What this document means for consumers

If you are an app developer integrating `navigation_safety_core`:

1. **You may use the package today.** The defects above are real but
   the substrate provides usable per-profile differentiation; the
   threshold direction is correct even where magnitudes are imperfect.
2. **Pin the patch version**, not the minor version, if you need
   stability. Threshold magnitudes are still being calibrated per
   ongoing literature review; minor versions may adjust them.
3. **If you serve a driver-class not in the 5 profiles**, fall back to
   `DriverProfile.snowZoneExperienced` (the standard default) and
   document the mapping in your own integration layer — and consider
   filing an issue describing your use case so the next iteration can
   incorporate it.
4. **For UX-differentiated alert formatting** (voice verbosity, modal
   timing, glance-budget), you must implement profile-aware UX
   yourself in v0.x. The profile-aware UX layer in consuming Flutter
   packages lands in v0.4+ pending coordination.

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
are separate surfaces planned for the next minor release.

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

## Why we publish this honestly

The package serves drivers — including drivers in HER cohort (the
named-weaver of the SNGNav project). Silent gaps are a worse failure
than acknowledged ones. Per the project's principle that *the absence
of a loom is the fault, never any individual*: this document is
itself a loom — it catches the gaps the package alone cannot, by
naming them where any consumer can see.

If you spot a gap not listed here, please open an issue. The list grows
with what we hear, not with what we hide.
