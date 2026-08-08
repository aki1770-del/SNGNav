# Changelog

## 0.0.6 — 2026-08-08 — An unmeasured precipitation figure no longer buys a severity downgrade

### If you are on 0.0.1 – 0.0.5, please read this — it describes what you already have

Every release of this package from **0.0.1 (2026-06-03) through 0.0.5** read a
**missing** precipitation figure as **0.0 mm**. One line, in
`lib/src/met_norway_advisory_provider.dart`:

```dart
// 0.0.5, line 323
final precipitation = _readNum(next1Details?['precipitation_amount']) ?? 0.0;
```

Two consequences, both of them fabrication:

1. **A severity downgrade on a freezing road.** With `air_temperature ≤ 0 °C`
   and **no** `precipitation_amount` in the slice, the classifier saw
   `precipitation == 0` and returned the benign **`'Subzero forecast'` →
   `AdvisorySeverity.moderate`** — "cold and dry". Had the figure actually been
   measured above zero it would have returned **`'Freezing precipitation'` →
   `severe`**, or **`extreme`** at ≥ 4 mm/h. Absence resolved onto the benign
   branch. `'Heavy precipitation'` could never fire from an absent figure
   either.
2. **A number in driver-facing text that nobody measured.** The advisory
   `description` unconditionally carried
   `next_1_hours precipitation_amount 0.0 mm` — a reading the publisher never
   sent, presented to a driver as though it had.

**Honest bound on how often this fired.** Measured against the live
`locationforecast/2.0/compact` product on 2026-08-08: **32 of 86** timeseries
slices for a Norwegian mountain point (Hardangervidda) carry **no
`next_1_hours` block at all** — every slice beyond about +54 h. This adapter
reads `timeseries[0]`, and slice 0 **did** carry the field at all three
coordinates sampled (Hardangervidda, Akita, Svalbard). So this is a **latent**
path on today's feed, not one observed firing in production. We are not able to
say it never fired: we have no telemetry, the publisher's schema is not a
promise, and `_readNum` also returns absence for any non-numeric value. A
latent fabrication in a safety verdict is still a fabrication, and the version
you are holding still contains it.

**We cannot un-publish 0.0.5.** Published versions are immutable and will be
served forever to anyone who requests them. 0.0.6 supersedes; it does not
recall.

### Changed (behaviour)

- `precipitation` is **nullable end-to-end**. A freezing temperature with an
  unmeasured precipitation figure now yields the event class
  **`'Freezing, precipitation not measured'`** at
  **`AdvisorySeverity.unknown`** — never `moderate`. This follows the
  contract's asymmetry: **positive hazard evidence may fire on partial data; a
  "nothing is wrong here" verdict requires complete data.** An unmeasured field
  may not buy a downgrade.
- **A measured zero is still a measurement.** `'Subzero forecast'` →
  `moderate` is unchanged for a real `0.0`, and the description still prints
  `0.0 mm` in that case.
- The description says **`next_1_hours precipitation_amount not reported`**
  when the field was absent, instead of printing a figure we do not have.

### Added

- Event-class constants exported from the library —
  `kEventFreezingPrecipitation`, `kEventFreezingPrecipNotMeasured`,
  `kEventHeavyPrecipitation`, `kEventSubzeroForecast` — so consumers can branch
  without matching literal strings. Additive; existing string matching still
  works.
- 10 regression tests (`test/honest_absence_met_norway_test.dart`), including
  the exact live shape measured above (whole `next_1_hours` block absent) and a
  non-numeric value. Each guard was verified by breaking it on purpose and
  watching the tests fail before being trusted.

### Upgrade impact

`0.0.6` is **in range of every `^0.0.x` constraint** in this family
(`^0.0.1` … `^0.0.5` all resolve to `>= … <0.1.0`; solver-verified with
`pub_semver`). No dependency constraint moved: `condition_aggregator: ^0.0.5`
is unchanged, and `AdvisorySeverity.unknown` already exists at the **floor** of
that range (verified by resolving and testing against `condition_aggregator`
0.0.5 exactly).

**If your code switches exhaustively on `eventClass`,** add a branch for
`'Freezing, precipitation not measured'`. **If your code ranks by
`AdvisorySeverity`,** confirm you treat `unknown` as "do not reassure the
driver" and not as "less than minor" — `unknown` is the first member of the
enum, so a naive `index`-based comparison will sort it *below* `minor`. That
ordering is inherited from `condition_aggregator` and is not changed here.

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
