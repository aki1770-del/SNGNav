# noaa_nws_adapter — Safety-Class Boundary Record

**Package**: `noaa_nws_adapter`
**Version**: 0.0.1 (the first version published to pub.dev, on 2026-05-03; earlier versions of this record said `publish_to: none`, which was not so)
**Boundary record version**: 1.0
**Authored by**: the SNGNav maintainers (safety-boundary review)
**Date**: 2026-05-03
**Design rule**: this record states, in §8, what the driver experiences when the package's output reaches her.

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task at all times. The package's `NoaaNwsClient.fetchActiveWinterAlerts()` returns `List<WinterAlert>` containing CAP-class fields (event / severity / headline / areaDesc / expires) consumed by the integrator's SNGNav weather/condition pipeline; integrator HMI surfaces relevant winter-alert advisories to the driver; driver decides response.
**No L2+ claim.** The package is a stateless HTTP adapter; no automation, no handover, no control authority anywhere in the dependency chain ending at this adapter.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety-scope).
**Reasoning**: package output is published-NWS-data-as-Dart-objects. The substrate is U.S. Federal public-domain CAP-class advisory data (NWS authority is the publisher). At adapter boundary, the package performs HTTP transport + GeoJSON parse + CAP-enum mapping; no safety-critical assertion is added beyond what the publisher asserts. No ASIL claim.
**Integrator responsibility**: any integration where NWS winter-alert data gates a control loop requires the integrator to perform fresh ASIL classification. This adapter does not pre-empt that classification; it simply renders public-domain authoritative-source advisory data in Dart-typed form.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at automated-driving-feature scope. This package delivers neither feature nor control; it delivers consumable winter-alert data from NWS to integrator pipeline.
**Honesty discipline at adapter boundary** (SOTIF-class operational discipline):
- **No retry inside the client** (per README.md L100): on 429 the call throws; caller decides backoff. *"Keeping retry policy in the caller keeps logs honest about what was actually attempted."*
- **Stateless: no polling, no cache, no stream** (README.md L104): consumer owns refresh cadence.
- **User-Agent mandatory** (README.md L107): empty value throws ArgumentError at construction; anonymous request is a programmer error per NWS publisher convention.
- **Default filter: `actualOnly: true`** (README.md L111): `Test`/`Exercise`/`System`/`Draft` entries excluded from default consumption — production driver-facing flow defaults to actual alerts only.
- **Malformed features skipped not fatal** (README.md L113): one bad CAP feature does not abort whole response.
These five disciplines collectively form the package's SOTIF-class advisory-honesty posture: the integrator (and the driver through them) sees what NWS actually published, with explicit error surfaces for transport / shape / authentication failure modes.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **at this package's boundary — first real-data adapter consuming external network feed.**
**Status**: **declared in scope by design**, as a safe default — this is the load-bearing WP.29 audit surface for SNGNav's first external-data adapter.
**Concrete WP.29 surface**:
- TLS transport: package consumes `https://api.weather.gov` exclusively (per README.md L36); no HTTP fallback; no certificate pinning at adapter scope (integrator-class concern at deployment).
- Authentication: none; NWS publishes open data. User-Agent header is rate-limit-accounting class not authentication class.
- Input validation: GeoJSON shape validation at parse layer (`NoaaNwsParseException` for shape mismatch); CAP-enum mapping with `unknown` default for unrecognized values (safe-default class; never panics on unrecognized publisher value).
- Rate limit: 429 surfaces as `NoaaNwsHttpException`; publisher recommends 5-second retry-after.
- Output integrity: `WinterAlert` is Equatable value-object; no executable content; no deserialization-class RCE surface.
- Privacy: zero PII handled at adapter boundary; the substrate is geographic-public-alert-class.
- Supply-chain: depends on `package:http` ^1.3.0 (well-known Dart HTTP package); zero native code; `equatable` ^2.0.7 for value-object semantics.

**WP.29-class operational discipline**: integrators deploying this adapter perform WP.29 audit at their app boundary (TLS-cert-store class; rate-limit-policy class; deployment-secret-handling class for the User-Agent contact email which carries integrator identity). This adapter's audit surface is small and boundary-clean.

## 5 — JIS / JASO conformance

**Conformance status**: **not applicable at this scope; geographic mismatch.**
**Reasoning**: NWS data is U.S.-region (contiguous US + Alaska + Hawaii + Puerto Rico + territories per README.md L162-165). Japanese-region drivers consume a `jmaxml`-class adapter (a separate package). JIS / JASO conformance audit fires at the Japanese-region adapter not at this US-region adapter.
**JIS / JASO updates**: earlier versions of this record said a monthly watch tracked them for weather-data-adapter packages. No output from that watch has been found, so this record no longer says so. This package's JIS / JASO scope is geographic-mismatch-class.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by construction.**
**Concrete reasoning**: this package consumes published NWS CAP data and produces `WinterAlert` value-objects with CAP-class severity (Extreme / Severe / Moderate / Minor / Unknown). No `DriverProfile` axis exists at this package's API surface. CAP severity is publisher-class assertion (NWS-authoritative); downstream consumers compose with `navigation_safety_core` profile-tuned thresholds which preserve severity-not-profile-driven HMI-presentation invariant.
**Composition pattern**: NWS CAP severity → SNGNav weather/condition consumer → `driving_conditions` 0.5.0 + `navigation_safety_core` 0.6.0 → integrator HMI (where severity-driven plane-allocation invariant fires per `navigation_safety_core` SAFETY_BOUNDARY.md §6).

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are typed `WinterAlert` records carrying public-domain NWS CAP data; the package emits no control signal, holds no actuator authority, exposes no API that closes a control loop. The substrate flows via integrator HMI to the driver as advisory information; the driver decides response.
**Driver agency**: the driver is the subject, not the object. NWS authoritative winter-alert data informs the driver's awareness of region-class hazards (Winter Storm Warning, Ice Storm Warning, etc.); the integrator HMI surfaces the alert; the driver decides (continue, slow down, detour, abort trip). The package is consumer-class for an authoritative public source — exactly the pattern the project's design principles license: public-domain authoritative source + advisory-class delivery + driver-decides outcome.

## 8 — What the driver experiences

**What the driver experiences when this package fires**: *when NWS has issued a winter alert for her current point, she sees it surfaced by the integrator HMI in time, with the publisher's exact wording.* When `noaa_nws_adapter` fires through an integrator HMI, the driver sees:
- the alert event class (*Winter Storm Warning, Ice Storm Warning, Blizzard Warning, etc. — 14 winter event types per README.md L43-48*) in the publisher's vocabulary
- the headline + area description in NWS's authoritative wording (no app-class re-summarization that could alter authoritative meaning)
- the expires time honestly (so she knows alert validity window without integrator pre-interpretation)

**In plain terms**: the package is *the postman who carries the publisher's letter to the driver without rewriting it.* NWS is the publisher of winter-alert authority; the package delivers exactly what the publisher wrote, parsed into Dart-typed structure for the integrator to render. The package's restraint (no retry, no cache, no stream, no summarization, no translation per README.md §What this package deliberately does not do L143-159) is the discipline it applies to data-fusion: the package does ONE thing well; it does NOT add layers the driver did not ask for and the publisher did not author.

**For the integrating developer**: integrator reading `NoaaNwsClient` API today sees explicit User-Agent requirement + explicit error classes (`NoaaNwsHttpException` / `NoaaNwsParseException`) + explicit `actualOnly` filter + stateless design + no-retry discipline. The README §Behaviours worth knowing (L98-114) explicitly enumerates the disciplines so the integrator knows what the adapter does AND what it deliberately does not do. Nothing patronizes the developer.

**Driver-experience section**: this section is the package's declaration of what the driver experiences, written for `noaa_nws_adapter` 0.0.1. Earlier versions of this record promised a re-check at first publication; none is recorded, and the package has been on pub.dev since 0.0.1. Subsequent versions update on material changes to the driver-experience surface.

**Driver-impact chain (≤4 hops)** per README.md L20-28 verbatim:
```
NWS API (api.weather.gov)
  -> NoaaNwsClient (this package)
    -> SNGNav weather/condition consumer (forward)
      -> driver in unexpected snow region (US)
```
Four hops; the driver is the terminal beneficiary.

## 9 — Cross-references

- README.md §Why this package exists L13-31 + §Smallest slice L34-52 + §Behaviours worth knowing L98-114 + §Authentication, rate limiting, license L116-130 + §What this package deliberately does not do L143-159
- pubspec.yaml `version: 0.0.1` (published to pub.dev; earlier versions of this record said `publish_to: none`, which was not so)
- LICENSE: BSD-3-Clause source code; NWS data is U.S. Federal public-domain
- Composition: SNGNav weather/condition consumer (downstream) + `driving_conditions` 0.5.0 SAFETY_BOUNDARY.md (downstream Monte Carlo calibration consumer) + `navigation_safety_core` 0.6.0 SAFETY_BOUNDARY.md (downstream profile-tuned advisory layer)
- Scope boundary: public-domain authoritative-source consumption is explicitly compatible with the project's design principles; this is the foundational shape for SNGNav's external-data adapter pattern

---

**Boundary record authored** by the SNGNav maintainers as part of the package's safety review. Quotations in this record are verbatim. At the scope of this boundary, the record passed the project's design review and its equal-treatment review.
