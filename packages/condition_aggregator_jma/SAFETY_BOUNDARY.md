# condition_aggregator_jma — Safety-Class Boundary Record

**Package**: `condition_aggregator_jma`
**Version**: 0.0.1 (explore-phase; `publish_to: none`)
**Boundary record version**: 1.0
**Authoring skill**: FDD (with AAA-class boundary template per sibling adapters)
**Date**: 2026-05-06

---

## 1 — SAE J3016 driver-task regime

**Level**: L0 / L1 supportive use only.
**Driver-task assignment**: the driver performs the dynamic driving
task at all times. `JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint(lat, lon)`
returns a list of typed `Advisory` records consumed by the
integrator's SNGNav weather/condition pipeline; integrator HMI
surfaces relevant JMA advisories to the driver; the driver decides
response.
**No L2+ claim.** The package is a stateless mapping wrapper
(stub today, real mapping at deploy-graduation); no automation,
no handover, no control authority anywhere in the dependency
chain ending at this adapter.

## 2 — ISO 26262 ASIL classification

**Package boundary**: **QM** (Quality Management; not
functional-safety scope).
**Reasoning**: package output is published-JMA-data-as-Dart-objects
mapped from the upstream parser's typed record shape to the
source-neutral `Advisory`. The substrate is JMA disaster-info XML
(JMA authority is the publisher; the feed is open public-data
class). At adapter boundary the package performs typed field
re-projection only; no safety-critical assertion is added beyond
what the publisher (and the upstream parser) carry. No ASIL
claim.
**Integrator responsibility**: any integration where JMA advisory
data gates a control loop requires the integrator to perform fresh
ASIL classification. This adapter does not pre-empt that
classification; it renders publisher-authoritative advisory data
in the source-neutral `Advisory` Dart-typed form.

## 3 — SOTIF (ISO 21448) posture

**Stance**: **advisory not control.**
**Reasoning**: SOTIF addresses Safety Of The Intended Functionality
at automated-driving-feature scope. This package delivers neither
feature nor control; it delivers consumable advisory data from
JMA via the upstream parser binding to the integrator pipeline.

**Honesty discipline at adapter boundary** (SOTIF-class operational
discipline):
- **No retry inside this adapter.** Transient failure handling
  belongs to the underlying parser/HTTP layer; the aggregator's
  warn-and-continue posture captures the error.
- **No cache, no stream, no polling at this layer.** Stateless
  beyond construction-time configuration; consumer owns refresh
  cadence.
- **`init()` is no-op (JMA's public XML feed requires no init).**
  Documented explicitly so integrators do not assume hidden
  warm-up.
- **Verbatim field passthrough (Article 17 (β) verbatim-relay
  discipline).** `eventClass` (JMA report family code), `headline`,
  `areaDescription`, `description` pass through unchanged. No
  app-class re-summarization that could alter authoritative
  meaning. No translation away from Japanese unless an explicit
  separate translation-layer adapter is composed downstream.
- **Severity / certainty / urgency map to CAP-class enums at
  deploy-graduation per a per-report-family table.** No
  re-classification authority is asserted — the table is
  publisher-class normalization for cross-publisher merge, not
  authoritative reclassification. Original JMA term preserved in
  `eventClass`.
- **Region resolution from WGS84 lat/lon → JMA region code lands
  at deploy-graduation.** Today (stub) the lat/lon are accepted
  but the stub returns empty; at graduation, the region resolution
  is the load-bearing privacy-respecting boundary (no precision
  beyond region-of-record needed; driver location is not
  exfiltrated to the publisher).

These six disciplines form the package's SOTIF-class
advisory-honesty posture: the integrator (and the driver through
them) sees what JMA actually published, mapped into the
source-neutral typed shape for multi-source aggregation, with
explicit error surfaces preserved through the upstream parser
binding.

## 4 — WP.29 cybersecurity touchpoint

**Touchpoint location**: **delegated to the upstream parser binding
boundary at deploy-graduation.**

This package performs no network I/O directly today (stub). At
deploy-graduation, the upstream parser binding is the audit
surface for: TLS to the JMA XML feed endpoint; rate-limit
accounting; XML parse hardening (XXE / billion-laughs class
defenses live at the parser binding, not here); CAP-class field
mapping.

**Concrete WP.29 surface at this layer (today + deploy-state)**:
- Input validation: at deploy-state, this package consumes typed
  records from the upstream parser binding (already validated at
  parse-time); no string parse here. Today, the stub accepts
  WGS84 lat/lon double values; out-of-range values are not
  rejected at this layer (graduation will add rejection).
- Output integrity: `Advisory` is Equatable value-object; no
  executable content; no deserialization-class RCE surface.
- Privacy: zero PII handled at this adapter; substrate is
  geographic-public-alert class. Driver lat/lon is consumed at
  this layer ONLY to resolve regional JMA-feed segments; no
  precision beyond region-of-record is exfiltrated to the
  publisher. Region-resolution scheme lands at deploy-graduation.
- Supply-chain: depends on `condition_aggregator` (path) +
  `xml: ^6.5.0` (well-known Dart XML parser). At deploy-state,
  upstream parser binding is added (engagement-shape election
  pending); the chosen shape determines whether transitive deps
  include WASM runtime (WASM bridge path) or pure-Dart codegen
  output (Dart-native port path).

**WP.29-class operational discipline**: integrators deploying this
adapter perform WP.29 audit at their app boundary. This adapter's
audit surface is small and boundary-clean today (stub) and stays
small at deploy-graduation (the parser binding is the network
edge, not this adapter).

## 5 — JIS / JASO conformance

**Conformance status**: **applies in scope at deploy-graduation;
conformance audit fires before graduation.**

**Reasoning**: JMA data is Japanese-region (the JMA's authority is
Japan Meteorological Agency by Japanese law). Japanese-domain
adapters are the natural seat of JIS / JASO conformance audit; this
adapter is the seat for the meteorological-advisory leg.

**JIS / JASO touchpoints at deploy-graduation**:
- JIS character encoding (UTF-8 / Shift_JIS) handling at the
  upstream parser binding boundary; XML-declared encoding is
  honored.
- JASO automotive-driving-relevant standards do not currently
  govern JMA advisory feed consumption (JASO scope is hardware /
  vehicle dynamics, not weather-data-feed consumption); however,
  the AAA monthly cron tracks JIS / JASO publication deltas in
  case a relevant new standard publishes.

**AAA monthly cron** (`aaa-jis-jaso-conformance-watcher-monthly`):
tracks JIS / JASO standard updates relevant to weather-data-adapter
packages globally; surfaces relevant publication deltas to AAA at
next monthly cycle. This package's JIS / JASO scope is
Japan-region-class and audit fires before deploy-graduation.

## 6 — Severity-not-profile invariant

**Status**: **applies in scope by design — profile-agnostic by
construction.**

**Concrete reasoning**: this package consumes typed JMA forecast
records at the upstream parser binding boundary and produces
`Advisory` value-objects with CAP-class severity (extreme / severe
/ moderate / minor / unknown — at deploy-graduation; today all are
unknown via stub). The mapping is publisher-class normalization
(JMA's 警報 / 注意報 / 特別警報 → CAP scale) and is enum-to-enum
with no profile-driven branching. No `DriverProfile` axis exists
at this package's API surface. CAP severity is publisher-class
assertion (JMA-authoritative); downstream consumers compose with
`navigation_safety_core` profile-tuned thresholds at a later layer
which preserves the severity-not-profile-driven HMI-presentation
invariant.

**Composition pattern (deploy-state)**: JMA report family +
publisher term → JMA forecast record → `Advisory.severity`
(CAP-normalized via per-report-family table) → `AdvisoryAggregator`
typed merge → `driving_conditions` + `navigation_safety_core` →
integrator HMI.

## 7 — Driver-always-drives invariant

**Status**: **applies in scope by design.**

**Concrete reasoning**: package outputs are typed `Advisory`
records carrying public-domain JMA advisory data; the package
emits no control signal, holds no actuator authority, exposes no
API that closes a control loop. The substrate flows via aggregator
→ integrator HMI to the driver as advisory information; the driver
decides response (continue, slow down, detour, abort trip). The
driver-decision substrate uses JMA authoritative wording verbatim
(`Advisory.eventClass`, `headline`, `description`,
`areaDescription`); this adapter is the postman for the
publisher's letter, mapped into the source-neutral envelope.

## 8 — Driver-facing loom

**What the driver experiences when this package fires** (deploy-state):
when JMA has issued a winter advisory for her current point inside
Japan, she sees a typed `Advisory` event surface through the
integrator HMI with severity / certainty / urgency / area /
effective / expires normalized at the boundary — and with JMA's
exact wording for the report family code, headline, area
description, and multi-paragraph description. She does not see
"raw XML". She does not see app-class re-summarization that
paraphrases the publisher. When her route crosses into the United
States (composition with the NWS-class adapter inside the same
aggregator), she sees NWS-published advisories surfacing through
the same `Advisory` shape — both publishers' authoritative wording
preserved verbatim through their respective adapters into the
source-neutral typed event.

**Sakichi reading**: this adapter is *the Japanese postman who
carries JMA's letter into a uniform envelope so the multi-postman
aggregator can stack it alongside other publishers' letters
without rewriting any of them.* The adapter's restraint (no retry,
no cache, no stream, no app-class re-summarization, no severity
reassertion, no profile-driven branching, verbatim field
passthrough) is the Sakichi-loom-discipline applied to per-source
mapping: the loom does ONE thing well — direct typed re-projection
— and does NOT add layers the driver did not ask for and the
publisher did not author.

**Audible-to-edge-developer**: integrators reading the package API
today see explicit `endpointBaseUrl` constructor parameter +
explicit `init` lifecycle contract + explicit stub-state
declaration in README + explicit deploy-graduation gate
enumeration in CHANGELOG. Nothing patronizes the developer.

**Driver-facing-loom field**: this section is the canonical
driver-facing-loom declaration for `condition_aggregator_jma`
0.0.1 explore-phase. At deploy graduation (post-engagement-shape
election + parser binding integration + per-report-family CAP
mapping table validation), this field is re-audited; subsequent
versions update on material changes to the driver-experience
surface.

## 9 — Cross-references

- `condition_aggregator` interface package: defines the
  `AdvisoryProvider` contract this adapter satisfies.
- `condition_aggregator_nws`: sibling adapter for the NOAA / NWS
  publisher leg of the same `Advisory` envelope.
- `noaa_nws_adapter`: the lower-level NWS HTTP wrapper composing
  with the sibling adapter; there is no equivalent lower-level
  package on the JMA side today (substrate-state: no Dart binding
  for the upstream parser; engagement-shape election pending).
- Package SAFETY_BOUNDARY.md siblings: `voice_guidance`,
  `driving_consent`, `driving_weather`, `kalman_dr`,
  `condition_aggregator_nws`, `noaa_nws_adapter`,
  `navigation_safety_core`, `navigation_safety` —
  per-package boundary-record discipline at the data-fusion class.
