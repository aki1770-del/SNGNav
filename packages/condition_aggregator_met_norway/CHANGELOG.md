# Changelog

## 0.0.6

### Safety defect in 0.0.5 and earlier — please read

**An UNMEASURED precipitation figure was read as 0.0 mm**, and that bought a
severity downgrade on a freezing road.

```dart
// met_norway_advisory_provider.dart, 0.0.5
final precipitation = _readNum(next1Details?['precipitation_amount']) ?? 0.0;
```

Two consequences, both fabrication:

1. **Severity downgrade.** With a freezing temperature and an ABSENT
   precipitation figure, `_classify` saw `precipitation == 0` and returned
   `'Subzero forecast'` → `AdvisorySeverity.moderate`, instead of the
   `'Freezing precipitation'` → `severe` it would have returned had the value
   actually been measured above zero. Absence resolved to the benign branch.
   `'Heavy precipitation'` could never fire from an absent figure either.
2. **A fabricated number in driver-facing text.** `_composeDescription`
   unconditionally emitted `next_1_hours precipitation_amount 0.0 mm` into the
   advisory description — for a value the feed never sent.

This is the same assertion-laundered-as-measurement defect that
`driving_weather` 0.5.0 removed from the Digitraffic adapter.

### Changed (behaviour)

- `precipitation` is nullable end-to-end. A freezing temperature with an
  unmeasured precipitation figure now yields the event class
  **`'Freezing, precipitation not measured'`** at **`AdvisorySeverity.unknown`**
  — never `moderate`. Per the contract's asymmetry: positive evidence fires on
  partial data; only the BENIGN verdict requires complete data, so an unmeasured
  field may not buy a downgrade.
- A **measured** zero is still a measurement: `'Subzero forecast'` → `moderate`
  is unchanged, and the description still prints `0.0 mm`.
- The description omits the precipitation line entirely when the field was
  absent (`"not reported"`), rather than printing a figure we do not have.

## 0.0.5 — Docs: restore dual NLOD 2.0 + CC-BY-4.0 license statement

- Docs: restore the **NLOD 2.0** (Norwegian Licence for Open Government Data) statement alongside **CC BY 4.0** in the README "License + attribution" section, matching the Chair-ratified record and the sibling `pretrip_source_met_norway`. MET Norway data is dual-licensed under both; an integrator may rely on either. Consistency-only — CC-BY-4.0 alone was already legally sufficient; no behavior or attribution-string change.

## 0.0.4 — 2026-06-26 — Docs: dev-first on-ramp (0.0.3 was already taken by the prior license-fix release; attribution preserved)

- Docs: dev-first on-ramp — install (`dart pub add`) + a run-verified
  quickstart snippet now lead the README; governance / mission /
  HER-trace / status / mapping prose moved verbatim to a
  `## Background & provenance` section below.
- No source or behaviour change.


## 0.0.2 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`).
- No source or behaviour change.


## 0.0.1 — 2026-05-24 — Initial scaffold

- Initial release of the MET Norway (Meteorologisk institutt) adapter
  for the `condition_aggregator` interface.
- Implements `AdvisoryProvider` against the public locationforecast
  endpoint
  (`https://api.met.no/weatherapi/locationforecast/2.0/compact`).
- Endpoint selection: the road-surface forecast product
  `roadforecast/2.0` documented at
  `https://api.met.no/weatherapi/roadforecast/2.0/documentation`
  returns HTTP 404 at curl on 2026-05-24 — the product is not
  publicly reachable; v0.0.1 ships against `locationforecast/2.0/compact`
  (HTTP 200, ~37 KB GeoJSON Point) as the canonical MET Norway weather
  endpoint. Direct road-surface mapping is queued for v0.0.2+ if a
  public road-product endpoint becomes available.
- Source attribution: `AdvisorySource.metNorway`. The parent
  `condition_aggregator` interface enum already carries the Norway
  member + the verbatim CC-BY-4.0 attribution string via
  `AdvisorySourceAttribution.attributionString`. No placeholder.
- License: MET Norway data is licensed CC-BY-4.0. Attribution is
  REQUIRED at the consumer-facing surface, not optional. The adapter
  emits the parent interface's verbatim attribution string in the
  `Advisory.description` field; integrators MUST surface that line at
  the HMI layer where the advisory is rendered.
- User-Agent: MET Norway terms require an identifying User-Agent
  naming the application/domain plus a contact email or website link.
  The adapter ships a default (`condition_aggregator_met_norway/0.0.1
  github.com/aki1770-del/sngnav`) and validates non-emptiness at
  `init()`. Integrators publishing under their own identity SHOULD
  override.
- Coordinates: truncated to 4 decimal places before the request per
  MET Norway terms ("Truncate coordinates to max 4 decimals").
- CAP severity / certainty / urgency: heuristic mapping at v0.0.1.
  - `extreme`: freezing temperature AND precipitation ≥ heavy floor.
  - `severe`: freezing-precipitation OR heavy-precipitation alone.
  - `moderate`: subzero forecast without precipitation.
  - `certainty`: `likely` when publisher `symbol_code` is present;
    else `possible`.
  - `urgency`: `expected` (next-1-hour horizon).
  - Thresholds (4 mm/h heavy precipitation floor, 0 °C freezing
    floor) are integrator-overridable at construction time.
- 7 mapping + 8 provider tests; all green. `dart analyze` clean with
  strict-casts + strict-inference + strict-raw-types.
- Carry-forward: `roadforecast` product if publicly accessible later;
  nowcast/2.0 short-horizon overlay; additional symbol_code →
  eventClass refinement.

## Open questions surfaced for strategic + ecosystem consultation

- Strategic sequencing: with Norway shipping second after Finland,
  does this commit the project to a Nordic-wide catalog (Sweden /
  Iceland / Denmark next), or is the right Q1 ramp pattern depth-first
  within a single country until first integrator pull arrives?
- Strategic cross-region commitment shape: shipping 2 Nordic adapters
  at the same first-slice maturity carries a coherence-maintenance
  cost across publishers — is the right v0.0.2 cycle "lift digitraffic
  and met_norway in lockstep" or "let each adapter mature against its
  own publisher cadence"?
- Ecosystem MET Norway warm-tie engagement: the right next move
  toward github.com/metno appears to be an introduction-class issue
  (ack-only) — NOT a PR drop. Ecosystem-consultation requested on
  issue body shape + which repo under github.com/metno is the right
  venue.
- Ecosystem CC-BY-4.0 attribution at HMI binding: the license's
  "attribution at consumer surface" requirement is binding on the
  integrator, not only on the adapter package. Ecosystem-consultation
  requested on whether the attribution-string surfacing belongs in
  the adapter README, the integrator-developer onboarding doc, or
  both — and whether `condition_aggregator` interface should ship a
  `requiresAttribution` boolean on AdvisorySource for downstream
  compile-time enforcement.
- Ecosystem family-coherence with nws + jma + digitraffic:
  met_norway uses `AdvisorySource.metNorway` (parent enum already
  carries it) while digitraffic uses `AdvisorySource.other`
  placeholder. The asymmetry surfaces the fintrafficFinland
  enum-extension upstream proposal NDI carries forward —
  ecosystem-consultation requested on whether the right path is one
  consolidated `nordic*` enum extension or per-publisher enum
  members.
