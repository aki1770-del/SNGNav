# Known limitations

This document lists known limitations of the current `snow_rendering`
package, with citations to public sources, so that consumers can
integrate with eyes open and contribute corrections from informed
positions.

The list is honest by intent — surfacing what we don't yet know rather
than letting silent gaps reach drivers.

---

## Radiative-frost black-ice classification (added in 0.2.6)

`RoadSurfaceState.fromCondition` now classifies the no-precipitation,
above-zero-ambient radiative-frost window as `blackIce`, via the shared
`isRadiativeFrostBlackIce` in `navigation_safety_calibration`. This closes a
proven contradiction (the in-drive screen said "Conditions normal" on a morning
the pre-trip briefing warned about black ice). The following limitations are
known and **must be read before relying on it for a live safety surface**. They
were surfaced by an adversarial multi-lens review (2026-07-06).

### 1. Reach — which feeds now supply humidity (PARTIALLY CLOSED)

The fix is humidity-gated, so it reaches HER only on a feed that supplies
humidity. Status of the feeds:

- **`OpenMeteoWeatherProvider` — supplies humidity** (`relative_humidity_2m`,
  since driving_weather 0.4.4). Online path.
- **KUKSA in-vehicle fusion (`vehicle_condition_fusion` 0.4.0) — NOW supplies
  humidity** via the standard VSS leaf `Vehicle.Exterior.Humidity`, so the D3
  compound-failure **offline** path (HER worst case) catches radiative-frost
  black ice from real vehicle sensors — BEFORE the friction/traction signals
  fire (they only reveal ice after a slip). Reaches HER when her vehicle/IVI
  runs the fusion AND publishes exterior humidity (the embedded/IVI integration
  + the vehicle sensor are the remaining links, EIE's domain).
- **`DigitrafficWeatherProvider` — does NOT supply humidity.** It synthesises a
  `WeatherCondition` from advisory severity (hardcoded temps, no real
  measurements), so it can supply neither a real temperature nor humidity for
  radiative-frost detection. This is currently the app's only *live in-drive
  stream* (`_initLiveWeather` wires a network stream only for the explicit
  Digitraffic selection); the humidity-bearing `OpenMeteoWeatherProvider` is
  kept purely local (offline-first) and is NOT wired as a live in-drive feed.

**Remaining reach work:** (a) wire `OpenMeteoWeatherProvider` (or another
humidity-bearing source) as a live in-drive feed for the phone path — an
app-level decision with an offline-first-posture implication; (b) the
embedded/IVI KUKSA integration so HER's actual vehicle runs the fusion. Until
(a)/(b), the pre-trip briefing (MET Norway humidity) remains HER radiative-frost
warning on the phone; the in-drive screen catches it on the KUKSA path and on
any online open-meteo feed.

### 2. All-hours / wind-blind — cry-wolf exposure

`isRadiativeFrostBlackIce` models a clear-sky, calm, night-time phenomenon, but
the in-drive classifier calls it on the CURRENT weather with **no time-of-day,
wind, or cloud gate** (`windSpeedKmh` and `timestamp` are available on
`WeatherCondition` but unused here). So an ordinary mild-damp winter reading
(e.g. +2 °C / 70 % RH, overcast/windy, midday) fires the STRONGEST response
(`blackIce`, grip 0.15). Unlike the pre-trip advisor (which scopes to the
commute window and fires a milder `caution` tier), the live all-hours classifier
has no such guard. Repeated false "black ice" on fine roads is trust erosion —
itself a safety harm.

**Deliberate current stance (decided 2026-07-07): caution-add-only, no gate
yet.** A wind/time gate is NOT added at this time, for two grounded reasons:
(1) there is no field data on the real false-positive rate versus wind/time, so
any threshold chosen now would be a guess — and guessing a safety parameter
violates measure-first; (2) a gate applied to the in-drive path only would
reopen the pre-trip↔in-drive contradiction this bond exists to close (the
pre-trip `radiativeFrostRisk` has no such gate either). The bounded over-warn
(0–3 °C, dew point ≤ 0 — genuinely frost-prone conditions) is accepted as the
fail-safe direction: a false "reduce speed" costs a driver a little time; a
missed black ice can cost far more. The gate is therefore **deferred pending
real field evidence** on the false-positive rate; when that exists, prefer
applying it to the shared classifier (so both surfaces stay consistent) with a
domain sign-off on the threshold.

### 3. Dew-point-vs-surface-temperature model bounds

`effective` == the 2 m-air dew point. Two consequences:
- **High-humidity / freezing-fog miss**: near-saturated air above ~+1 °C has a
  dew point ≥ 0, so the model returns not-frost — yet a radiatively-exposed
  bridge deck can be below 0 °C. Near-saturated freezing fog above ~+1 °C is
  NOT detected.
- **+3 °C ambient ceiling**: a hard cap kills warm-day cry-wolf (20 °C/25 % RH)
  but also suppresses the +3…+5 °C clear-calm bridge-deck case, where a deck can
  run several degrees below air temperature. This is a deliberate, accepted miss
  at the current calibration; a surface-vs-air offset for bridge contexts is a
  candidate refinement.
- **Dry-air fires deeper**: drier air yields a deeper computed depression, so a
  cold-dry clear morning (e.g. +2 °C / 30 % RH) fires. This is intentional
  caution-add; whether a higher moisture floor better matches real dry mornings
  is open.

### 4. Humidity-absent is presented as "Conditions normal"

When humidity is absent the no-precip branch returns `dry`, which
`DrivingConditionAssessment` maps to "Conditions normal" — byte-identical to a
genuinely verified-safe road. There is no "frost risk unknown — no humidity
data" state. On a humidity-blind feed, an unjudged frost morning therefore reads
as confident safety. A low-confidence / unknown state is a candidate improvement.

### 5. Freezing rain still under-classified (pre-existing, outside this change)

WMO codes 66/67 (freezing rain) map to `PrecipitationType.sleet` → `slush`
(grip 0.5), not `blackIce` (grip 0.15). Freezing rain is the archetypal glaze
producer; this pre-existing under-classification is unrelated to the
radiative-frost branch but is the single most dangerous precip-driven black-ice
source and is noted here for the follow-on backlog.

### 6. `humidityRH` unit naming

`WeatherCondition.humidityRH` (and `HourlyForecast.humidityRH`) carry PERCENT,
while `computeEffectiveTemperatureCelsius(humidityRH:)` takes a FRACTION `(0,1]`.
Always route humidity through `isRadiativeFrostBlackIce(humidityRHPercent:)`
(which adapts the boundary) rather than passing a percent field straight into the
fraction primitive.

---

## DataBudget per-cohort byte-budget defaults (added in 0.2.0) — UNVERIFIED magnitudes

The 0.2.0 release adds `DataBudget` + `DataBudgetConfig` +
`DataBudgetConfig.forProfile(DriverProfile)` factory + the
`relax(int, BudgetRelaxConfirmation)` cap-override-with-confirmation
pattern. The **API shape** is intentional and stable (mirrors the
`GlanceBudgetTracker` precedent from `navigation_safety` 0.9.0 + the
cap-override-with-confirmation precedent from `navigation_safety_core`
0.10.0 #30); the **magnitudes** in the per-cohort `forProfile` factory
are design-default hypotheses pending field-measurement validation.

### What is UNVERIFIED at 0.2.0

- **Per-cohort data-budget magnitudes** (`professional` /
  `snowZoneExperienced` / `agriculturalForestry` 4MB baseline /
  `noviceUrban` 3MB / `ageingRural` 2MB /
  `foreignTouristSnowZone` 2MB). The 4MB baseline is engineering-
  judgement consistent with mobile-bandwidth-respect range (typical
  2-8MB / minute supplemental overlay fetch); the per-cohort tighter-
  direction values are conservative-only (every cohort `<=` 4MB
  baseline) and ordered to match bandwidth-class assumptions
  (rural-bandwidth-margin for `ageingRural`; international-roaming-
  cost for `foreignTouristSnowZone`; urban-mobile-data-cost for
  `noviceUrban`). The specific magnitudes (3MB / 2MB / 2MB) are NOT
  yet anchored in a published study mapping driver-cohort to
  optimal-data-budget specifically. Per-population calibration is
  deferred pending fleet-class field measurement.

- **Bandwidth-class assumptions** — the per-cohort tighter-direction
  rationale assumes:
  - `ageingRural` → slower-rural-data; tighter budget reduces fetch
    wait. Assumption sensitive to actual rural data-coverage in the
    integrator's deployment region.
  - `foreignTouristSnowZone` → international-roaming-cost margin.
    Assumption sensitive to actual roaming-data-cost in the
    integrator's tourist-cohort population.
  - `noviceUrban` → urban-mobile-data-cost margin. Assumption
    sensitive to actual urban-data-cost in the integrator's
    deployment region.
  All three assumptions are integrator-tunable via the explicit
  `DataBudgetConfig` constructor; the `forProfile` factory is a
  default-only convenience.

- **`warningRatio` default of 0.75** — mirrors the `GlanceBudgetTracker`
  / `PerformanceBudget` precedents. The 75% threshold is published-
  anchor for typical budget-warning HMI patterns.

### What is verified at 0.2.0

- **API shape** — the `DataMeterProvider` interface is integrator-
  implemented and orthogonal to the existing `DrivingConditionAssessment`;
  every input is opt-in (defaults preserve 0.1.x behaviour exactly).
  Unit tests cover `record()` / `BudgetWarning` / `BudgetExhausted` /
  `RenderFidelityDrop` / `tighten()` / `relax()` / `reset()` /
  `dispose()` + per-cohort allocation.

- **Caution-add-only contract** — `DataBudgetConfig.forProfile`
  rejects per-cohort budget above the 4MB baseline at runtime via
  debug-mode assertion. `tighten(int)` rejects newBudgetBytes larger
  than active budget. Auto-relax forbidden; only `relax(int,
  BudgetRelaxConfirmation)` with affirmative confirmation may loosen
  the budget. Verified by negative-assertion tests.

- **Driver-always-drives contract** — `relax` rejects
  `confirmation.isConfirmed == false` and empty `confirmation.reason`
  at runtime via debug-mode assertion. Verified by the relax-flow
  test in `test/data_budget_test.dart`.

- **Severity-not-profile contract** — the tracker is bandwidth-class
  only; it does not modify alert severity tiers. Verified at
  `SAFETY_BOUNDARY.md` §6 + library-level docstring.

- **Back-compat** — pre-existing `RoadSurfaceState`,
  `PrecipitationConfig`, `VisibilityDegradation`, and
  `DrivingConditionAssessment` contracts unchanged from 0.1.x. Pure
  Dart property preserved (the 0.2.0 additions add only `equatable`
  and `navigation_safety_core` dependencies; both pure Dart).

### Out of scope at 0.2.0

- Live-detection of network-class (WiFi vs mobile-data vs roaming)
  is out of scope. The package consumes only the integrator-supplied
  byte-count; integrators that wish to gate behaviour on
  network-class should signal via `BudgetResetReason.networkClassChange`
  and re-configure the tracker.

- Per-cohort-validated magnitude tables (the 0.2.0 magnitudes are
  placeholders pending the integrator's own fleet-class telemetry).

- Per-fetch-class sub-budgets (overlay vs route vs surface-state
  fetch) are reserved for v2 differentiation when field evidence
  motivates them.

### Integrator-side caveats

- **`DataMeterProvider` supply-chain caveat**: the integrator is
  responsible for the adapter from their network sub-system to the
  package's `DataMeterProvider` interface. The package consumes only
  typed `DataFetchEvent` byte-count values; supply-chain provenance
  is the integrator's concern.

- **`BudgetRelaxConfirmation` discipline**: the cap-override-with-
  confirmation pattern requires the integrator to BUILD a
  confirmation surface (e.g. user-tap dialog). The package does not
  invent the surface. The discipline is: relax(...)
  must NEVER be called from a code path that does not pass through
  affirmative driver-confirmed input. The `assert` is a backstop, not
  a substitute for the discipline.

---

## Pre-existing limitations (0.1.x)

See `CHANGELOG.md` 0.1.0 entry for the founding extraction note.
No new disclosures at 0.2.0 affect the existing
`DrivingConditionAssessment` surface.
