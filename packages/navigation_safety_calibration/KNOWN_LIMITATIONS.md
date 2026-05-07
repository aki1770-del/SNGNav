# Known limitations

This document lists known limitations of the three calibration
primitives shipped in `navigation_safety_calibration` 0.1.0, with
citations to public sources, so that consumers can integrate with
eyes open and contribute corrections from informed positions.

The list is honest by intent — surfacing what we don't yet know
rather than letting silent gaps reach drivers.

---

## Surface-moisture exponential decay (`computeSurfaceMoistureFraction`)

### What is UNVERIFIED at 0.1.0

- **90-minute default half-life.** The exponential-decay shape is the
  standard first-order-evaporation model used in pavement-engineering
  and atmospheric-science references. The 90-minute default is
  conservative-by-design rather than population-validated for any
  particular climate, surface material, sun exposure, or wind
  condition. Most road surfaces dry faster than 90 minutes under sun
  and wind; some dry slower (shaded, cold, low-wind environments).
- **Half-life dependence on ambient conditions.** The qualitative
  dependency on temperature, wind, and solar load is well-documented
  in pavement-engineering literature; no single published number
  captures every road context. The current API accepts
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
  fraction as "definitely dry"; the value is a
  conservative-bias-toward-still-wet indicator, not a measurement.

---

## Magnus-formula effective temperature (`computeEffectiveTemperatureCelsius`)

### What is verified at 0.1.0

- **Magnus formula constants.** `a = 17.625`, `b = 243.04 °C` follow
  the modern August-Roche-Magnus parameterisation documented in
  Alduchov & Eskridge (1996), the standard reference for this
  parameterisation in atmospheric-science literature.

### What is UNVERIFIED at 0.1.0

- **Effective road-surface temperature approximation.** The function
  approximates effective surface temperature as
  `ambient - dew_point_depression`. Real road-surface temperature
  depends on emissivity, sky cloud cover, surface material,
  time-of-night, wind, and solar loading; the approximation is
  conservative-by-design (biased toward earlier frost-risk warning)
  rather than measured. Consumers should treat the output as a
  frost-risk indicator rather than a measured surface temperature.
- **Magnitude of nighttime radiative cooling vs. ambient under varied
  cloud cover.** Well-documented qualitatively in surface-meteorology
  references; no single magnitude captures every road context.

### Bounded validity range

The Magnus parameterisation `a = 17.625`, `b = 243.04 °C` is
documented as accurate over the temperature range typical of
near-surface meteorology (roughly −40 °C to +50 °C ambient). Outside
that range, dew-point error grows; the function does not enforce a
range check and consumers should clamp inputs to plausible ambient
ranges before feeding the helper.

---

## Speed-adjusted visibility floor (`computeSpeedAdjustedVisibilityMeters`)

### What is anchored to literature

- **Hazard-perception reaction time for novice vs experienced
  drivers.** Novice 3.58 s, experienced 1.32 s, per
  [PubMed 16313881](https://pubmed.ncbi.nlm.nih.gov/16313881/).
- **Trait-state framing of reaction time.** Regan, Hallett & Gordon
  2011 ([PMC4001671](https://pmc.ncbi.nlm.nih.gov/articles/PMC4001671/))
  distinguishes trait reaction-time (driver class) from state
  reaction-time (drowsy / distracted). The `driverReactionTimeSeconds`
  parameter encodes the trait axis; consumers passing a state-aware
  value should compose the two axes themselves.

### What is UNVERIFIED at 0.1.0

- **Per-profile reaction-time defaults.** The
  `snowZoneExperienced` ≈ 1.8 s, `professional` ≈ 1.5 s,
  `agriculturalForestry` ≈ 2.0 s, and `foreignTouristSnowZone` ≈ 3.5 s
  values cited in the docstring are reasonable engineering anchors
  pending field-measurement validation; they are conservative
  relative to the 1.32 s experienced anchor and are explicitly
  marked UNVERIFIED in the source.
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
above (population study mapping hour-of-day to reaction-time
multiplier; pavement-evaporation half-life by climate band; per-class
braking deceleration on snow / ice surfaces), please open an issue at
<https://github.com/aki1770-del/SNGNav/issues>.

Citations to a published source are sufficient; a fleet-data PR with
methodology disclosure is welcome. The caution-add-only contract is
load-bearing: any contribution that would let the per-profile
visibility floor lower, or shorten the moisture half-life beyond the
conservative-by-design 90-minute anchor, must include independent
field validation.
