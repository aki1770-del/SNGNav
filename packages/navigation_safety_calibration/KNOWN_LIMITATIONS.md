# Known limitations

This document lists known limitations of the three calibration
primitives shipped in `navigation_safety_calibration` 0.1.0. It names
the public sources that show what they are cited for, and says where a
value is a recorded decision that no cited source gives, so that
consumers can integrate with eyes open and contribute corrections from
informed positions.

The list is honest by intent — surfacing what we don't yet know
rather than letting silent gaps reach drivers.

---

## Surface-moisture exponential decay (`computeSurfaceMoistureFraction`)

### What is UNVERIFIED at 0.1.0

- **90-minute default half-life.** The exponential-decay shape and the
  90-minute default are recorded decisions; no source is cited for
  either, and neither is population-validated for any particular
  climate, surface material, sun exposure, or wind condition. A longer
  half-life keeps the moisture fraction higher for longer; no source is
  cited showing that 90 minutes is conservative. Published
  urban-surface evaporation work
  ([PMC7917919](https://pmc.ncbi.nlm.nih.gov/articles/PMC7917919/))
  reports that the "water content of the concrete layer had been in the
  peak for a few days after the rain"; it publishes no half-life for
  residual moisture on a road surface and does not describe drying as
  exponential.
- **Half-life dependence on ambient conditions.** PMC7917919 names
  "wind speed, net radiation" among the "other meteorological factors
  that affect the evaporation process"; no source cited here gives a
  half-life for any road context. The current API accepts
  `evaporationHalfLifeMinutes` so consumers with telemetry can
  override the default toward a population-fitted value.
- **`ambientCelsius` parameter is not yet used.** The parameter is
  accepted for forward-compatible API shape (a future revision may
  modulate the half-life by temperature) and is currently a no-op
  inside the function. Naming it now lets the signature stabilise
  before that calibration lands.

### When NOT to use the default half-life

- Indoor / sheltered-storage applications where evaporation physics
  diverge from outdoor pavement.
- Frozen-precipitation contexts where solid-phase persistence
  dominates the moisture budget; the exponential model fits
  evaporation, not melt-freeze cycling.
- Any safety-critical decision that would treat a low moisture
  fraction as "definitely dry"; the value is a modelled indicator
  from a recorded-decision half-life, not a measurement.

---

## Magnus-formula effective temperature (`computeEffectiveTemperatureCelsius`)

### What is verified at 0.1.0

- **Magnus formula constants.** `a = 17.625`, `b = 243.04 °C` are the
  constants Alduchov & Eskridge give for their AEKR Magnus-form
  approximation ("Improved Magnus Form Approximation of Saturation Vapor
  Pressure", Journal of Applied Meteorology, 1996).

### What is UNVERIFIED at 0.1.0

- **Effective road-surface temperature approximation.** The function
  approximates effective surface temperature as
  `ambient - dew_point_depression`, which equals the dew point. Real
  road-surface temperature depends on emissivity, sky cloud cover,
  surface material, time-of-night, wind, and solar loading; the
  approximation is a recorded modelling decision, not measured. In
  unsaturated air the estimate is below ambient, so a frost-risk test
  on it can fire while the air is above 0 °C; in saturated air it
  equals ambient. No source cited here compares it with a measured
  road surface. Consumers should treat the output as a frost-risk
  indicator rather than a measured surface temperature.
- **Magnitude of nighttime radiative cooling vs. ambient under varied
  cloud cover.** No magnitude is cited. The University of Washington
  roadway-icing tutorial
  ([Roadway Icing and Weather tutorial, U. Washington](https://www.atmos.washington.edu/~cliff/Roadway3.html))
  says frost "tends to occur on cold, relatively clear nights when
  wind speeds are low" and that on such nights "temperature at ground
  level can be 2-5F cooler than air temperature only a few feet
  above"; no single magnitude fits every road context.

### Bounded validity range

Alduchov & Eskridge compared the accuracy of their approximations,
this one included, over −40 °C to +50 °C, and note that the largest
relative errors usually occur at the end points of that range. This
record cites no evaluation outside it. The function does not enforce a
range check and consumers should clamp inputs to plausible ambient
ranges before feeding the helper.

---

## Speed-adjusted visibility floor (`computeSpeedAdjustedVisibilityMeters`)

### What the cited sources show, and what they do not

- **Reaction times.** No source cited here gives any of the per-profile
  reaction times in seconds; all six are recorded decisions. Sagberg
  and Bjørnskau 2006
  ([PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/)), whose
  abstract gives no reaction times in seconds, found that average
  hazard-perception reaction times "tended to decrease with
  experience, but the decrease was not significant", with "some
  significant differences in the expected direction for individual
  test items".
- **Trait and state.** The trait/state split of reaction time is this
  package's design. Regan and Strayer 2014
  ([PMC4001671](https://pmc.ncbi.nlm.nih.gov/articles/PMC4001671/))
  list driver conditions (e.g. young, inexperienced, old) and driver
  states (e.g. bored, sleepy, fatigued, drugged, emotional) as factors
  in driver inattention; they give no reaction times. The
  `driverReactionTimeSeconds` parameter encodes the trait axis;
  consumers passing a state-aware value should compose the two axes
  themselves.

### What is UNVERIFIED at 0.1.0

- **Per-profile reaction-time defaults.** The `ageingRural` ≈ 2.5 s,
  `noviceUrban` ≈ 3.58 s, `snowZoneExperienced` ≈ 1.8 s,
  `professional` ≈ 1.5 s, `agriculturalForestry` ≈ 2.0 s, and
  `foreignTouristSnowZone` ≈ 3.5 s values in the docstring are recorded
  decisions pending field-measurement validation; no source cited here
  gives any of them.
- **Default braking deceleration of 5.5 m/s².** A typical
  passenger-car dry-pavement value; surface friction coefficient is
  the dominant variable. For snow / ice surfaces consumers should
  pass a lower value (≈ 3.0 m/s² for compacted snow; ≈ 1.5 m/s² for
  glare ice). No single default fits every road condition.

### Caution-add-only contract

The function is constructed so that the per-profile baseline acts as
a strict lower bound: context (speed, reaction time, deceleration)
can only **raise** the warning-visibility floor (warn earlier), never
lower it. This is the same caution-add-only invariant carried by the
upstream `navigation_safety_core` thresholds; a return value smaller
than `profileBaseMeters` would indicate a math error and is
explicitly excluded by the implementation.

---

## Out-of-scope at 0.1.0

This package contains **no live-detection logic**. None of the inputs
(time-since-precipitation, ambient/humidity, speed, reaction time,
deceleration) are inferred. All values are integrator-supplied;
consumers are responsible for sourcing them from sensors, telemetry,
or fleet defaults.

The package does not depend on `navigation_safety_core` and does not
import any of its types. Consumers wanting the calibration values
composed with the broader threshold model should use
`navigation_safety_core` directly.

---

## How to contribute corrections

If you have field-measurement data for any of the UNVERIFIED magnitudes
above (per-profile reaction times; pavement-evaporation half-life by
climate band; per-class braking deceleration on snow / ice surfaces),
please open an issue at
<https://github.com/aki1770-del/SNGNav/issues>.

A published source that shows the value is sufficient; a fleet-data PR
with methodology disclosure is welcome. The caution-add-only contract
is load-bearing: any contribution that would let the per-profile
visibility floor lower, or shorten the moisture half-life below the
90-minute recorded default, must include independent field
validation.
