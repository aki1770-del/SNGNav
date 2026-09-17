# Changelog

## 0.1.5

A documentation release. No value this package computes has changed: outside
comments and doc comments, `lib/` is unchanged, and
`computeSpeedAdjustedVisibilityMeters` still uses the deceleration you pass it.
One test is renamed.

**If you pass 3.0 or 1.5 m/s² because these docs suggested them, read this.**
The docs in `lib/src/speed_dependent_visibility.dart`, where
`computeSpeedAdjustedVisibilityMeters` is defined, said: "For snow / ice
surfaces the consumer should pass a lower value (≈3.0 m/s² for compacted snow;
≈1.5 m/s² for glare ice)." `KNOWN_LIMITATIONS.md` said the same. A single
figure does not fit a surface. Friction surveys give ranges: compacted snow or
ice, the surface most frequently observed, around 0.2 to 0.3; new snow
compacted by traffic 0.10 to 0.15; ice 0.1 to 0.2 (TRB Special Report 115);
packed snow 0.20–0.30 and wet black ice 0.05–0.10 (VTI meddelande 911A).
Multiplied by 9.81 m/s², these bound deceleration from above; they are not
measured stopping figures. Against those ranges, 3.0 m/s² (about 0.31) is just
above the top of the compacted-snow and packed-snow ranges, and 1.5 m/s²
(about 0.15) is inside the ice range and above the wet black ice range. The
docs now give the ranges instead. The default is still 5.5 m/s², a figure this
package chose for dry pavement.

**Renamed test.** In `test/calibration_values_test.dart`,
`lower deceleration (e.g. snow ≈ 3.0) raises required distance` is now
`lower deceleration (e.g. 3.0) raises required distance`. It checks the same
thing. If you run this package's tests by name, use the new name.

## 0.1.4

A documentation release. No API or behaviour change: outside comments and doc
comments, `lib/` is unchanged. Every function returns what it returned in
0.1.3.

**Values that no cited source gives.** The docs placed these values beside
citations or called them "conservative". We read the cited sources. None of
them gives these values, and none shows that the half-life is conservative.
The docs now call each one a recorded decision: a value this package chose.

- **The 90-minute default of `evaporationHalfLifeMinutes`** in
  `computeSurfaceMoistureFraction`, and the exponential shape of the
  decay. The docs called 90 minutes "deliberately conservative", biased toward
  "still wet". Nothing cited shows that. A longer half-life keeps the moisture
  fraction, and any warning margin your app derives from it, higher for
  longer. The one cited source on how long a surface stays wet (PMC7917919, an
  urban-surface evaporation study) reports that the concrete layer's water
  content stayed at its peak "for a few days after the rain". It gives no
  half-life. If you have your own measure of how long roads stay wet where
  your app is used, pass it as `evaporationHalfLifeMinutes`.
- **The six per-profile reaction times** in the `speed_dependent_visibility`
  header: ageingRural 2.5 s, noviceUrban 3.58 s, snowZoneExperienced 1.8 s,
  professional 1.5 s, agriculturalForestry 2.0 s, foreignTouristSnowZone
  3.5 s. The docs attributed 3.58 s (novice) and 1.32 s (experienced) to
  PubMed 16313881. That paper (Sagberg and Bjørnskau 2006) gives no reaction
  times in seconds in its abstract. It found that the decrease in
  hazard-perception reaction time with experience "was not significant".
- **The 3.0 °C ambient ceiling** of `isRadiativeFrostBlackIce`
  (`radiativeFrostAmbientCeilingCelsius`). The docs called it the envelope
  that the cited sources document. They give no ceiling.
- **The road-surface temperature estimate** of
  `computeEffectiveTemperatureCelsius`. The docs called it "a conservative
  estimate". It returns the dew point. Using the dew point as the road-surface
  temperature is a modelling decision, not a measurement, and nothing cited
  compares it with a measured road surface.

**Citations corrected:**

- PMC4001671 was cited as Regan, Hallett and Gordon 2011. It is Regan and
  Strayer 2014, which describes Regan, Hallett and Gordon's 2011 taxonomy.
  It lists driver conditions and driver states as factors that may lead to
  inattention, or change how much inattention affects driving. It gives no
  reaction times. The trait/state split is this package's design.
- Black ice at air temperatures above 0 °C. The docs now give the conditions
  their sources state. Wikipedia's "Black ice" says so only when the air warms
  suddenly after a prolonged cold spell has left the road surface well below
  freezing. Wikipedia's "Radiative cooling" says it for surfaces under a clear
  night sky, and gives no temperature.
- The Magnus constants (a = 17.625, b = 243.04 °C) are now cited to the paper
  that gives them, Alduchov and Eskridge 1996, with the range over which that
  paper compared its approximations (−40 °C to +50 °C).

`navigation_safety_core` re-exports this package and points to these headers
for its citations. Its 0.11.8 docs describe them as they read in this
release.

Tests: one group name and one test name changed. The test name now gives the
Magnus dew point at 20 °C and 50 % relative humidity as ≈ 9.26 °C, not ≈ 9.27 °C.
No assertion changed.

## 0.1.3

- Add `isRadiativeFrostBlackIce({ambientCelsius, humidityRHPercent})` — the
  single source of truth for the radiative-frost black-ice classification
  (no-precipitation, above-zero-ambient window). Both the pre-trip advisor and
  the in-drive road-surface classifier now call this one function so the two
  surfaces can never disagree about black ice. Caution-add-only; never throws
  (every rejected humidity class returns `false`); takes humidity in PERCENT and
  adapts the percent→fraction boundary internally. Exposes the documented
  envelope constants `radiativeFrostAmbientCeilingCelsius` (3.0 °C) and
  `radiativeFrostSurfaceTempCelsius` (0.0 °C). No change to the existing
  primitives.

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.

## 0.1.0 — 2026-05-07

Initial release. Three pure-computation calibration primitives
extracted verbatim from `navigation_safety_core` 0.10.0:

- `computeSurfaceMoistureFraction` — exponential surface-moisture
  decay after precipitation; default 90-minute half-life
  (conservative); accepts ambient temperature for forward-compatible
  API shape.
- `computeEffectiveTemperatureCelsius` — Magnus formula dew-point
  computation and effective road-surface temperature for frost-risk
  reasoning. Constants `a = 17.625` / `b = 243.04 °C` per Alduchov &
  Eskridge (1996).
- `computeSpeedAdjustedVisibilityMeters` — speed-adjusted visibility
  floor combining reaction-time and braking distance over a
  per-profile baseline. Caution-add-only — the per-profile floor
  never lowers.

Source files are byte-identical to the corresponding files in
`navigation_safety_core` 0.10.0 (zero diff verified at extraction
time). No Flutter dependency. No transitive dependencies beyond
`test` and `lints` for development.

License: BSD-3-Clause (mirrors `navigation_safety_core`).

This release ships the package standalone. A subsequent
`navigation_safety_core` 0.11.0 release will depend-on and re-export
from this package for ABI-compat; that is a separate next-cadence
spawn and not part of this 0.1.0 release.

`KNOWN_LIMITATIONS.md` is authored at extraction time honest-disclosing
heuristic-class scope (Magnus formula bounded validity range / decay
coefficient empirical anchor / visibility heuristic single-axis) per
the caution-add-only invariant inherited from `navigation_safety_core`.
