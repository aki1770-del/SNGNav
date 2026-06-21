# condition_aggregator_nws — Safety-Class Boundary Record

**Package**: `condition_aggregator_nws`
**Version**: 0.0.6 (published; early and evolving)
**Boundary record version**: 1.0
**Boundary record template**: shared across the sibling adapter packages
**Date**: 2026-05-03

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving task
at all times. `NwsAdvisoryProvider.fetchActiveAdvisoriesAtPoint(lat, lon)`
returns a list of typed `Advisory` records consumed by the integrator's
SNGNav weather/condition pipeline; integrator HMI surfaces relevant
winter-alert advisories to the driver; the driver decides response.
**No L2+ claim.** The package is a stateless mapping wrapper; no
automation, no handover, no control authority anywhere in the
dependency chain ending at this adapter.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not functional-safety
scope).
**Reasoning**: package output is published-NWS-data-as-Dart-objects
mapped from `WinterAlert` to source-neutral `Advisory`. The substrate
is U.S. Federal public-domain CAP-class advisory data (NWS authority
is the publisher). At adapter boundary the package performs typed
field re-projection only; no safety-critical assertion is added beyond
what the publisher (and the underlying `noaa_nws_adapter`) carry. No
ASIL claim.
**Integrator responsibility**: any integration where NWS winter-alert
data gates a control loop requires the integrator to perform fresh
ASIL classification. This adapter does not pre-empt that
classification; it renders public-domain authoritative-source advisory
data in the source-neutral `Advisory` Dart-typed form.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality at
automated-driving-feature scope. This package delivers neither feature
nor control; it delivers consumable advisory data from NWS via the
underlying client to integrator pipeline.
**Honesty discipline at adapter boundary** (SOTIF-class operational
discipline):
- **No retry inside this adapter.** `noaa_nws_adapter`'s no-retry
  policy is preserved; on 429 / transport failure the underlying call
  throws; the aggregator's warn-and-continue posture captures the
  error into `result.providerErrors`.
- **No cache, no stream, no polling at this layer.** Adapter is
  stateless beyond the underlying `NoaaNwsClient` HTTP resources;
  consumer owns refresh cadence.
- **`init()` is no-op (NWS requires no init).** Documented explicitly
  so integrators do not assume hidden warm-up.
- **Verbatim field passthrough.** `eventClass`, `areaDescription`,
  `headline`, `description` are passed through unchanged. No
  app-class re-summarization that could alter authoritative meaning.
- **Severity / certainty / urgency are direct CAP-enum mappings.** No
  re-classification, no profile-driven severity tuning at this layer
  (severity-not-profile invariant).
- **`actualOnly: true` default is preserved.** Test / Exercise / System
  / Draft entries excluded by default at the underlying client; this
  adapter does not re-introduce them.

These six disciplines collectively form the package's SOTIF-class
advisory-honesty posture: the integrator (and the driver through
them) sees what NWS actually published, mapped into the source-neutral
typed shape for multi-source aggregation, with explicit error
surfaces preserved through the underlying adapter.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **delegated to `noaa_nws_adapter` boundary.**
This package performs no network I/O, no authentication, and no
deserialisation of external bytes; the underlying `noaa_nws_adapter`
is the audit surface for TLS, rate-limit accounting, GeoJSON parse,
and CAP-enum mapping. See `noaa_nws_adapter/SAFETY_BOUNDARY.md` §4
for concrete WP.29 surface detail.
**Concrete WP.29 surface at this layer**:
- Input validation: this package consumes typed `WinterAlert` records
  (already validated at the underlying client); no string parse here.
- Output integrity: `Advisory` is Equatable value-object; no
  executable content; no deserialization-class RCE surface.
- Privacy: zero PII handled; substrate is geographic-public-alert
  class.
- Supply-chain: depends on `condition_aggregator` (path) +
  `noaa_nws_adapter` (path); zero native code; transitive runtime
  deps are `equatable` and `package:http` (well-known Dart packages).

**WP.29-class operational discipline**: integrators deploying this
adapter perform WP.29 audit at their app boundary (TLS-cert-store
class via underlying client; rate-limit-policy class via aggregator
fan-out cadence; deployment-secret handling for the User-Agent
contact email). This adapter's audit surface is small and
boundary-clean.

## 5 — JIS / JASO conformance

**Conformance status**: **not applicable at this scope;
geographic mismatch.**
**Reasoning**: NWS data is U.S.-region (contiguous US + Alaska +
Hawaii + Puerto Rico + territories per `noaa_nws_adapter` README).
Japanese-region drivers consume the JMA-class adapter
(`condition_aggregator_jma`, separate package) inside the same
`AdvisoryAggregator`. JIS / JASO conformance audit fires at the
Japanese-region adapter, not at this U.S.-region adapter.
**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`):
tracks JIS / JASO standard updates relevant to weather-data-adapter
packages globally; surfaces relevant publication deltas to AAA at
next monthly cycle. This package's JIS / JASO scope is
geographic-mismatch-class; cron findings inform the sibling
JMA-class adapter rather than this package.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by
construction.**
**Concrete reasoning**: this package consumes `WinterAlert` records
and produces `Advisory` value-objects with CAP-class severity
(extreme / severe / moderate / minor / unknown). The mapping is
strictly enum-to-enum with no profile-driven branching. No
`DriverProfile` axis exists at this package's API surface. CAP
severity is publisher-class assertion (NWS-authoritative);
downstream consumers compose with `navigation_safety_core`
profile-tuned thresholds at a later layer which preserves the
severity-not-profile-driven HMI-presentation invariant.
**Composition pattern**: NWS CAP severity → `WinterAlert.severity` →
`Advisory.severity` (this adapter) → `AdvisoryAggregator` typed merge
→ `driving_conditions` 0.5.0 + `navigation_safety_core` 0.6.0
→ integrator HMI.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**
**Concrete reasoning**: package outputs are typed `Advisory` records
carrying public-domain NWS CAP data; the package emits no control
signal, holds no actuator authority, exposes no API that closes a
control loop. The substrate flows via aggregator → integrator HMI to
the driver as advisory information; the driver decides response
(continue, slow down, detour, abort trip). The driver-decision
substrate uses NWS authoritative wording verbatim
(`Advisory.eventClass`, `headline`, `description`,
`areaDescription`); this adapter is the postman for the publisher's
letter, mapped into the source-neutral envelope.

## 8 — Driver-facing loom

**What the driver experiences when this package fires**: when NWS has
issued a winter alert for her current point inside the United States,
she sees a typed `Advisory` event surface through the integrator HMI
with severity / certainty / urgency / area / effective / expires
normalized at the boundary — and with NWS's exact wording for the
event class, headline, area description, and description. She does
not see "raw GeoJSON". She does not see app-class re-summarization
that paraphrases the publisher. When her route crosses into Japan
(future composition with the JMA-class adapter inside the same
aggregator), she sees JMA-published advisories surfacing through the
same `Advisory` shape — both publishers' authoritative wording
preserved verbatim through their respective adapters into the
source-neutral typed event.

**Sakichi reading**: this adapter is *the U.S. postman who carries
NWS's letter into a uniform envelope so the multi-postman aggregator
can stack it alongside other publishers' letters without rewriting
any of them.* The adapter's restraint (no retry, no cache, no
stream, no app-class re-summarization, no severity reassertion, no
profile-driven branching, `actualOnly: true` preserved) is the
Sakichi-loom-discipline applied to per-source mapping: the loom does
ONE thing well — direct typed re-projection — and does NOT add
layers the driver did not ask for and the publisher did not author.

**Audible-to-edge-developer**: integrators reading the package API
today see explicit `userAgent` requirement on the default
constructor + explicit `withClient` test-injection constructor +
explicit pass-through documentation of `actualOnly` + explicit
no-retry-no-cache discipline + explicit field-by-field mapping
table (README "Mapping detail"). The README's "Behaviours worth
knowing" section enumerates the disciplines so the integrator
knows what the adapter does AND what it deliberately does not do.
Nothing patronizes the developer.

**Driver-facing declaration**: this section is the canonical
driver-experience declaration for `condition_aggregator_nws`
(v0.0.6). It is re-audited on material changes to the driver-experience
surface in subsequent versions.
