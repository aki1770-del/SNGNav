# Changelog

## 0.0.6 — 2026-06-26 — Docs: dev-first on-ramp

- README now LEADS with what-it-is, a `dart pub add` install line, and a
  run-verified copy-paste quickstart snippet under `## Quick start`, plus
  one line on what the developer gets back.
- All governance / mission / service-trace / status / mapping / license
  prose moved verbatim below a `## Background & provenance` heading.
- `example/main.dart` updated to match the quickstart snippet (prints the
  advisory count and severity-tagged event class + headline).
- No source or behaviour change.


## 0.0.5 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`).
- No source or behaviour change.


## 0.0.4 — 2026-05-30 — Defect fix: large live response no longer throws (graceful degradation)

- **Defect (shipped in v0.0.2/v0.0.3)**: `fetchActiveAdvisoriesAtPoint`
  applied a HARD 8 MB cap (`_kMaxResponseBytes = 8 * 1024 * 1024`) that
  THREW `DigitrafficHttpException` on any larger response body. The live
  all-Finland `/v2/traffic-announcements` payload is not stable — it
  tracks the active-announcement count and attached area geometries —
  and was measured above 8 MB (~16.4 MB at peak; ~3.5 MB at a 2026-05-30
  low) on a perfectly valid HTTP 200. At those times the adapter threw
  on a good response, breaking it for EVERY edge developer fetching live
  Finnish road data, not just our demo.
- **Fix — graceful degradation, robust to future growth**: the hard
  byte-cap throw is removed. A valid HTTP 200 is always parsed. The
  former cap is replaced by a *soft* 32 MB warn threshold
  (`_kSoftResponseWarnBytes`) that is well above observed volumes; when a
  body exceeds it the adapter invokes the optional new
  `onLargeResponse(int observedBytes)` diagnostic callback and parses the
  body anyway rather than discarding it. A fixed-larger hard cap was
  rejected because the payload grew 3.5 MB → 16.4 MB in days — a bigger
  number would only delay the next re-regression.
- **Server-side narrowing investigated and NOT available**: the live
  `/v2/traffic-announcements` endpoint accepts NO query parameters
  (no bbox / `situationType` / `includeAreaGeometry`) — confirmed
  against the Digitraffic OpenAPI spec and live HTTP 400 responses on
  2026-05-30 (the bbox params documented elsewhere apply to a different
  endpoint shape). The adapter therefore continues to fetch the
  all-Finland FeatureCollection and filter client-side via the existing
  bounding-box intersection. A smaller server-side query would have been
  the preferred bandwidth fix for embedded/edge consumers, but the v2
  endpoint does not support it.
- **New public API (additive; no breaking removals)**: optional
  `onLargeResponse` callback on both `DigitrafficAdvisoryProvider()` and
  `DigitrafficAdvisoryProvider.withClient()` constructors.
- Fintraffic CC-BY-4.0 attribution behavior and all existing public
  symbols / mappings are unchanged.
- Tests: 19 → 22. Added a >8 MB mocked body proving the adapter no
  longer throws and still parses + maps features; a >32 MB body proving
  the `onLargeResponse` diagnostic fires while the body still parses; and
  a small-body case proving the diagnostic does NOT fire on routine
  responses.

## 0.0.3 — 2026-05-27 — Documentation framing: HER-trace → "Service trace (driver in unexpected snow)"

- Documentation-only release. No code changes; no test changes; no behavior changes.
- README section heading "HER-trace (≤4 hops)" → "Service trace (driver in
  unexpected snow; ≤4 hops)". The new framing names the subject explicitly
  (driver in unexpected snow) rather than relying on a capitalized "HER"
  pronoun-trace convention that external readers may parse as an acronym.
  The substantive trace chain is unchanged (Fintraffic Digitraffic feed →
  `DigitrafficAdvisoryProvider` → `AdvisoryAggregator` typed merge →
  integrator HMI → driver in unexpected snow on Finnish roads).
- `lib/condition_aggregator_digitraffic.dart` barrel-file dartdoc: same
  framing revision ("HER-trace (≤4-hop)" → "Service trace (driver in
  unexpected snow; ≤4-hop)"); version banner bumped from stale "v0.0.1"
  to "v0.0.3" (was inconsistent across v0.0.2 cycle).
- Mission anchor: doc-class clarity revision serves drivers + their families
  by ensuring the README is parseable on first reading by an external
  Flutter developer encountering the package on pub.dev without prior
  context — substantive substrate (CAP heuristic mapping, license
  attribution, test coverage) was already substance-quality clean at v0.0.2
  per the 2026-05-27 retroactive audit; this release closes the one
  external-reader-clarity opportunity that audit surfaced.

## 0.0.2 — 2026-05-24 — CAP heuristic mapping + mocked-HTTP integration tests + license/attribution clarifications

- CAP-class heuristic mapping by `trafficAnnouncementType`. The
  v0.0.1 `unknown` placeholders for `severity` / `certainty` /
  `urgency` are replaced with an integrator-overridable mapping
  derived from the 2026-05-24 live API genchi-genbutsu against
  `https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`
  (1455 active features at 08:53 UTC; 5 distinct event-class values
  observed):
  - `accident report` (711 features) → `severe` / `observed` /
    `immediate`
  - `general` (442) → `minor` / `possible` / `expected`
  - `preliminary accident report` (158) → `moderate` / `likely` /
    `expected`
  - `ended` (143) → `minor` / `observed` / `past`
  - `retracted` (1) → `minor` / `unlikely` / `past`
- Integrators MAY override the per-event-class mapping at adapter
  construction time via the new `capMapping` parameter on both
  `DigitrafficAdvisoryProvider()` constructors and on the top-level
  `mapTrafficAnnouncementFeatureToAdvisory()` function. A
  conservative `fallbackMapping` (default
  `minor` / `possible` / `unknown`) covers unobserved future
  event-class values; integrators MAY override it too.
- Mocked-HTTP integration tests via `package:http/testing.dart`
  `MockClient` covering: features inside bounding box → CAP-mapped
  advisory; features outside bounding box → filtered out; empty
  `features` array → empty advisory list; malformed JSON →
  `DigitrafficParseException`; HTTP 503 →
  `DigitrafficHttpException(statusCode: 503)`; missing `features`
  key → `DigitrafficParseException`. Test count: 6 (v0.0.1) → 19
  (v0.0.2).
- License + attribution honesty (per CT upstream-ecosystem
  consultation 2026-05-24 P2 verdict; CC-BY-4.0 §3(a) family-
  coherence with the MET Norway sibling adapter):
  - **Fintraffic CC-BY-4.0 verified**: Digitraffic open data is
    licensed under Creative Commons 4.0 By per Fintraffic Terms of
    Service (`https://www.digitraffic.fi/en/terms-of-service/`,
    verified 2026-05-24); attribution is REQUIRED at the consumer-
    facing surface, not optional.
  - Verbatim Fintraffic-required attribution string
    (`Source: Fintraffic / digitraffic.fi, license CC 4.0 BY.`) is
    now appended to every emitted `Advisory.description` field via
    the new `kDigitrafficAttributionString` public constant so the
    credit reaches the driver-facing HMI surface per CC-BY-4.0
    §3(a)(1)(a)-(c).
  - Modification-disclosure line added to the README "License +
    attribution (binding)" section per CC-BY-4.0 §3(a)(1)(b):
    Digitraffic data is consumed unmodified; bounding-box filtering
    + CAP heuristic mapping are derivations of representation, not
    of underlying data.
- `pubspec.yaml`: added explicit `license: BSD-3-Clause` field
  (pub.dev license-detection bookend per `kuksa_dart_sdk` 0.2.1
  lesson).
- Operational hardening (carried into the v0.0.2 cycle for pub.dev
  publish-readiness): 30 s wall-clock fetch budget; 8 MB hard cap
  on the response body (2026-05-24 live response measured ~3.5 MB);
  `endpointUrl` + `boundingBoxHalfDegrees` + `capMapping` +
  `fallbackMapping` all integrator-overridable at construction time.
- Public symbols exported via barrel: `DigitrafficCapMapping`,
  `defaultDigitrafficCapMapping`,
  `defaultDigitrafficFallbackMapping`,
  `kDefaultDigitrafficTrafficAnnouncementsUrl`,
  `kDefaultDigitrafficBoundingBoxHalfDegrees`,
  `kDigitrafficAttributionString` (additive to v0.0.1; no breaking
  removals).

### What v0.0.2 still defers (carry-forward to v0.0.3+)

- `AdvisorySource.fintrafficFinland` enum-extension upstream
  proposal — fires when a second Finnish-publisher adapter (e.g.
  `condition_aggregator_fmi`) warrants the enum surface change per
  NDI bylaws Rule 1(c). v0.0.2 still uses `AdvisorySource.other`
  placeholder.
- Symbol-class refinement via
  `properties.announcements[].features[]` (granular tags like
  `wildlife`, `road works`, `weather`) for sub-event-class CAP
  derivation.
- `If-Modified-Since` cache-friendly polling.
- `package:http` `RetryClient` wrapper.
- Integrator-facing pana score baseline + publish-readiness
  summary at `outputs/research/ndi_digitraffic_publish_readiness_*.md`
  per NDI bylaws Rule 6.

## 0.0.1 — 2026-05-24 — Initial scaffold

- Initial release of the Fintraffic Digitraffic adapter for the
  `condition_aggregator` interface.
- Implements `AdvisoryProvider` against the open Digitraffic
  traffic-announcements endpoint
  (`https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`;
  no authentication required per Digitraffic swagger v3 `security: []`).
- Fetches GeoJSON FeatureCollection of active traffic announcements;
  filters to features near a requested point via bounding-box
  intersection; maps each feature to a source-neutral `Advisory`
  record using publisher-verbatim `trafficAnnouncementType` as
  `eventClass`.
- Source attribution: uses `AdvisorySource.other` as a placeholder.
  Carry-forward: propose `AdvisorySource.fintrafficFinland` upstream
  in `condition_aggregator` interface when 2+ Finnish-source adapters
  warrant the enum extension.
- CAP severity / certainty / urgency: mapped to `unknown` for v0.0.1.
  Digitraffic announcements do not expose CAP-class fields directly;
  heuristic mapping by `trafficAnnouncementType` is a v0.0.2 candidate.
- English headline + description selected from the
  `announcements[]` list when a `language: 'en'` entry exists.
