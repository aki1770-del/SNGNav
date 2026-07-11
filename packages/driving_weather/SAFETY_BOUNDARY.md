# driving_weather — Safety-Class Boundary Record

**Package**: `driving_weather`
**Version**: 0.5.0
**Boundary record version**: 2.0
**Authoring skill**: AAA (automotive-adas-analyst)
**Date**: 2026-05-05; **corrected 2026-07-12**
**Anchor**: driver-facing-loom-as-default architectural discipline (per-package boundary record per AAA spawn-50 precedent)

---

## 0 — Correction notice (2026-07-12, record v2.0)

**Boundary record v1.0 certified properties the code did not have.** It is
corrected here in the same commit as the code, not after it — a document
claiming a property the code lacks is the certificate of a defect, and is worse
than no certificate.

Three claims in v1.0 were **false of versions up to and including 0.4.4**:

| v1.0 claim | Reality in ≤ 0.4.4 |
|---|---|
| §2: "it surfaces the data as received" | `WeatherCondition.clear()` hardcoded +5.0 °C / 10000 m / 0.0 km/h / `iceRisk: false`, and `DigitrafficWeatherProvider` returned it for an **empty** advisory feed. Data was **manufactured**, not surfaced as received. |
| §8: the loom "never asserts more than it observes" | It asserted a temperature, a visibility, a wind speed and an ice-risk verdict it had **never observed**, and the Digitraffic severity mapping invented -4.0 °C / 150 m / 40 km/h for advisories that carry no measurements at all. |
| §3: "network failures surface as exceptions or null returns" | A failed fetch **silently re-emitted the last condition with no staleness marker**. Old data was indistinguishable from fresh. With no prior data, the stream went **silent**, which a UI cannot distinguish from "not fetched yet". |

The 0.5.0 code makes all three claims **true** (see §2, §3, §8 as corrected
below). The defect is disclosed in `CHANGELOG.md` 0.5.0, because pub.dev
versions are immutable and a silent fix would be a silent recall.

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's `WeatherProvider` interface produces `WeatherCondition` value-objects describing precipitation type, intensity, wind, visibility, and ice-risk — observational state only. The driver hears or sees the rendered surface, decides response.
**No L2+ claim.** The package emits no actuator signal, holds no automation, performs no handover. Pluggable provider implementations (`OpenMeteoWeatherProvider` for live HTTP fetch; `SimulatedWeatherProvider` for tests) deliver state-class data; the integrator translates state into HMI advisories or feeds it into a `condition_aggregator` for fusion with road-surface and visibility signals.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: `driving_weather` produces an observational weather signal — no safety-critical assertion is added at this layer. Open-Meteo upstream is a public free-tier API; the package does not make safety claims about freshness, accuracy, or coverage. **As of 0.5.0 it surfaces the data as received, and nothing else** — every measured field is nullable, `null` means NOT MEASURED, and no constructor substitutes a literal for a field the feed did not supply. *(This sentence was false of ≤ 0.4.4; see §0.)* Network-class freshness and provider-class trustworthiness are integrator-responsibility at the closed-loop boundary — but the package now **states** staleness rather than concealing it (see §3).
**Integrator responsibility**: any integration where weather signal gates a control loop (e.g. an automated chain-warning that interlocks vehicle speed) requires the integrator to perform fresh ASIL classification at the closed-loop boundary, including provider-class trust-anchor analysis (Open-Meteo's terms of service, SLA, jurisdiction).

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.** Converges with `condition_aggregator` per the aggregation-thesis architectural pattern: weather signal is one substrate input, fused with road-surface and visibility into a single decision substrate the driver can read at a glance.
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither feature nor control; it delivers a weather-class observational substrate the integrator already plans to render or aggregate. The driver reads or hears the result; the driver decides; the driver always drives.
**Honesty discipline at adapter boundary** (SOTIF-class operational discipline):
- **Provider pluggability** (`WeatherProvider` interface): production builds choose `OpenMeteoWeatherProvider` (live HTTP); tests choose `SimulatedWeatherProvider` (deterministic state). Provider choice is integrator-class; the package does not lock in a vendor.
- **Free-tier upstream** (Open-Meteo): the production provider is a public no-API-key endpoint. Integrators considering paid providers (national meteorological services, commercial APIs) implement their own `WeatherProvider`; the package boundary accommodates substitution.
- **Observational state, not forecast assertion**: the package surfaces *current* weather state at the vehicle's location. Forecast-class assertions (next-30-minute snow probability, etc.) are out-of-scope at this package; integrators wanting forecast-class signal compose with a separate forecast adapter.
- **Ice-risk surface**: `WeatherCondition` exposes a **nullable** ice-risk field (`bool? iceRisk`); the integrator decides whether the field's value triggers a hazard advisory at the integrator's HMI surface. `null` means the risk could not be determined — it never means "no ice". The package does not emit an alert; it exposes the substrate.
- **HTTP-class failure surface**: network failures surface as **typed readings**, not as concealed values. `WeatherProvider.conditions` emits a sealed `WeatherReading`: `WeatherObserved` (fetched this poll), `WeatherStale` (refresh failed — carries the last known condition, when it was ACTUALLY observed, its real age, and the cause), or `WeatherUnavailable` (no data at all, and since when). `fetchWeather()` still throws `HttpException` for direct callers. The integrator's retry/backoff policy remains the integrator's responsibility (per the `noaa_nws_adapter` 0.0.2 retry/backoff pattern). *(≤ 0.4.4 silently re-emitted stale data with no marker and went silent when it had none; see §0.)*
- **Absence is a value, never a default** (0.5.0): every measured quantity is nullable and safety verdicts are **tri-state** (`SafetyVerdict.hazardous | notHazardous | unknown`), never `bool`. A `bool` cannot express "I do not know" and therefore resolves absence into its `false` branch — which, for `isHazardous`, was the *clear-road* branch. The verdicts are deliberately **asymmetric**: positive hazard evidence fires on partial data; the negative ("all clear") verdict requires complete data. Offline is `unknown`, never a green light — and never a fabricated alarm.
- **An assertion is not a measurement** (0.5.0): road-authority feeds (Digitraffic) declare *situations* with a CAP severity and measure no weather. That declaration is carried as `HazardAssertion` with every unmeasured field left `null`, rather than laundered into invented sensor readings.

**Known performance insufficiency (SOTIF, carried forward, not fixed in 0.5.0)**: `OpenMeteoWeatherProvider` derives `iceRisk` as `temperature <= 0 && precipType != none`. A sub-zero **clear** hour therefore derives `iceRisk == false` even though residual/black ice may be present on the road surface. This is a *derivation from present measurements*, not an absence-fabrication, so it is out of scope for the 0.5.0 honest-absence repair — but it is a real insufficiency and is recorded here rather than left unstated. The `humidityRH` field exists to let a downstream radiative-frost classifier do better; the integrator owns that classification.

These disciplines collectively form the package's SOTIF-class advisory-honesty posture.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **integrator-class; package boundary involves outbound HTTP fetch to public weather API.**
**Status**: **out of scope at this package's boundary, but the HTTP-fetch surface falls under WP.29 R155 audit at integration time.**
**Concrete WP.29 surface at this package**:
- Inputs: latitude / longitude (double); HTTP GET to Open-Meteo public endpoint.
- Outputs: `WeatherCondition` value-objects parsed from JSON response.
- Authentication: none (Open-Meteo free tier requires no API key).
- Input validation: JSON response is parsed by the provider; malformed responses surface as exceptions; the value-object schema is enforced at the package boundary.
- Privacy: latitude / longitude leave the device en route to Open-Meteo. Per Open-Meteo's privacy posture, the request is anonymous (no user identifier); the integrator preparing a deployment must verify this against current Open-Meteo terms of service.
- Supply-chain: depends on `equatable` and `http`. Both reviewed.

**WP.29-class operational discipline**: integrators deploying this package perform WP.29 R155 audit at their network-egress boundary. The egress surface for this package is *one HTTPS request per fetch*, with no authentication and no PII other than coordinates the consuming app already has by virtue of holding location services. The smallest reasonable network attack surface for a free-tier public weather API.

## 5 — JIS / JASO conformance

**Conformance status**: **applies at the integrator's HMI surface, not at this package.**
**Reasoning**: Japanese-region weather rendering surfaces in the integrator's HMI; this package emits the observational state but does not specify display-class signage / icon-class HMI vocabulary that JIS / JASO standards regulate. Where a JIS / JASO standard regulates weather-class icon vocabulary directly, the integrator owns the audit at deployment.
**JMA crosswalk note**: Japan Meteorological Agency advisory class (注意報 / 警報 / 特別警報) maps to weather-class severity at the integrator's translation layer; the package surfaces observational state in Open-Meteo vocabulary; the integrator's adapter is responsible for mapping to JMA-recognized advisory vocabulary if the deployment surfaces JMA-aligned alerts.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: weather state is gated by intensity-class enums (`PrecipitationIntensity.heavy` vs `moderate` vs `light`) and ice-risk-class boolean. Driver profile does not enter the weather state; the same precipitation intensity reads the same value for every profile. Integrator's downstream HMI surface may render in profile-aware vocabulary (`navigation_safety_core` `RoadSurfaceConditionGlossary.forConditionAndProfile()` pattern, applied analogously), but the weather state at this package is profile-blind. *Severity-class (intensity + ice-risk) decides whether/what; profile only decides how the integrator renders.*
**Composition pattern**: `driving_weather` observational state → `condition_aggregator` fusion with road-surface + visibility → integrator HMI in profile-aware vocabulary. The fusion-layer (`condition_aggregator`) is also profile-blind; profile awareness lives at the rendering layer downstream.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are `WeatherCondition` value-objects. The package emits no actuator signal, holds no closed-loop authority, exposes no API that gates vehicle behavior. The driver hears or sees the rendered weather; the driver decides response; the driver always drives.
**Axis anchor**: per the unit's driver-sovereignty axis substrate — driver is subject not object. The package observes the world for HER; HER decides what to do with the information. The rendering layer at the integrator is where dignity-class differentiation per profile lives; this package is the upstream observer.

## 8 — Driver-facing loom

**What HER experiences when this package fires**: *weather signal that converges with road-surface and visibility into a single decision substrate the driver can read at a glance.* When `driving_weather` fires through an integrator HMI:
- HER sees the weather state surfaced at her vehicle's location: precipitation type, intensity, wind speed, visibility distance, ice-risk flag — **or, for each of these, an honest "unknown" when the source did not measure it.**
- **When the road could not be assessed, HER is TOLD that** (`SafetyVerdict.unknown`), instead of being shown a fabricated "conditions normal". When the data is old, HER is told how old (`WeatherStale`). When there is no data, HER is told there is none (`WeatherUnavailable`). This is the D3-worst-case answer: when the feed is gone, the app SAYS SO.
- HER sees the weather state composed with road-surface state and visibility state via `condition_aggregator` into a single fused decision substrate — not three separate alert streams competing for attention.
- HER hears or reads the rendered surface in profile-aware vocabulary at the integrator's HMI; HER cognitive budget is respected per `DriverProfile`.
- HER drives the dynamic driving task; the package never reaches into the actuator chain.

**Sakichi reading**: the loom is *the upstream observer that surfaces the world's state honestly, **never asserts more than it observes**, and yields the rendering choice to the integrator's profile-aware HMI*. As of 0.5.0 this is **true of the code**, and enforced by its types: absence is `null`, verdicts are tri-state, staleness and unavailability are types the consumer cannot ignore. *(In ≤ 0.4.4 this sentence was an aspiration the code contradicted — it asserted +5.0 °C and "no ice" for roads it had never observed. See §0. Sakichi's loom stopped when a thread broke; it did not keep weaving defective cloth. This package kept weaving. It now stops, and it says why.)*

**Audible-to-edge-developer**: integrator reading `WeatherProvider` API today sees the pluggable-provider pattern surfaced explicitly + the `SimulatedWeatherProvider` provided as a test-class scaffold + the `OpenMeteoWeatherProvider` documented as the production provider with no-API-key requirement and Open-Meteo terms-of-service responsibility surfaced for the integrator. Nothing patronizes the developer.

**Driver-facing-loom field**: this section is the canonical driver-facing-loom declaration for `driving_weather` 0.5.0. Subsequent versions update this field on material changes to the weather-class surface (new providers, new fields, new fusion patterns, etc.).

**Driver-impact chain (≤4 hops)**:
```
weather observation (Open-Meteo public API)
  -> WeatherProvider.fetchCurrent (this package)
    -> condition_aggregator fusion + integrator HMI rendering
      -> driver in unexpected snow region reads the converged advisory
```
Four hops; HER is terminal beneficiary; satisfies HER-trace ≤4-hop discipline.

## 9 — Cross-references

- `lib/src/weather_condition.dart` (`PrecipitationType` / `PrecipitationIntensity` / `ObservationSource` / `HazardAssertion` / `SafetyVerdict` / `WeatherCondition` value-object)
- `lib/src/weather_reading.dart` (sealed `WeatherReading` = `WeatherObserved` | `WeatherStale` | `WeatherUnavailable`)
- `lib/src/weather_provider.dart` (`WeatherProvider` abstract interface)
- `lib/src/open_meteo_weather_provider.dart` (production HTTP provider; Open-Meteo free tier)
- `lib/src/digitraffic_weather_provider.dart` (Finnish road-authority advisories, carried as `HazardAssertion`)
- `lib/src/simulated_weather_provider.dart` (test-class deterministic provider; the one legitimate asserter of a complete "clear")
- `CHANGELOG.md` 0.5.0 (the defect disclosure — pub.dev versions are immutable, so the CHANGELOG is the recall)
- `pubspec.yaml` `version: 0.5.0`
- LICENSE: BSD-3-Clause (matches the rest of SNGNav)
- AAA bylaws Article 17 (β) safe-default boundary
- PHIL-001 boundary preserved: `driving_weather` is the upstream observer; it is **not** a crash-data-harvester; the package boundary refuses crash-class data routing by virtue of its scope (weather observations only).
- Composition: `driving_weather` observational state → `condition_aggregator` fusion (per spec §3.2; data-fusion component class) → integrator HMI in profile-aware vocabulary.
- Open-Meteo upstream: <https://open-meteo.com/> — public no-API-key tier; integrator owns terms-of-service compliance.

---

**Boundary record authored** by AAA per VAA-as-SEO operational pen authorization. Subject = We / AAA. Verbatim citation discipline observed. PHIL-001 8-test PASS preserved at boundary scope. D4 dignity audit clear (weather observation respects every driver-class equally; profile-class differentiation lives at the rendering layer downstream).
