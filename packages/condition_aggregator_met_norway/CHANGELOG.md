# Changelog

## 0.0.7

⚑ **Released as `0.0.7`, not `0.1.0`, and the reason is reach.** `^0.0.6` resolves
to `>=0.0.6 <0.1.0` under Dart's caret rule, so `0.1.0` crosses the wall and a
caret-pinned consumer could **never** receive it. The minor bump was chosen to
signal that `0.0.x` understated a package implementing the full provider
contract — a signalling argument, whose price was that the fix could not arrive.
An in-range patch is the only vehicle that reaches an existing consumer.

**This adapter could not see black ice forming above 0 °C.** Its coldest gate was
`air_temperature <= 0` — the exact threshold `navigation_safety_calibration`
documents as missing this case: *"a 'warn below 0 °C ambient' threshold misses
this window."* Under clear-sky radiative cooling the road surface falls toward
the dew point and surface moisture freezes while the air still reads +1…+3 °C.
This adapter said **nothing at all** there.

**Three adversarial gate rounds ran against this change. None of the
intermediate forms was ever published.** The first found five defects; the
second found five, three of them created by the first round's fixes; the third
found five more, again mostly created by the second round's. What follows is
what the package does, and why the third round was the last.

### ⚑ The root was one thing, and re-ordering conditions was never going to fix it

Every one of those fifteen defects was the same defect: **`null` meant two
things.** "Assessed, and there is nothing to report" and "I could not assess
this" were the same return value, so a driver-facing surface could not tell them
apart — and neither, it turned out, could the author. A rain gate returning
`null` on freezing drizzle, a cloud gate turning a severe advisory into silence,
a ceiling silencing the band it was cited to cover: all one overloading.

Classification now returns a **sealed** verdict — `_Hazard`, `_AssessedBenign`,
or `_NotAssessed(missingInput)` — matched by an **exhaustive switch**. A path
that forgets to say which of the three it means **does not compile**; deleting a
case yields `non_exhaustive_switch_statement`. **`_AssessedBenign` is the only
verdict permitted to become silence.** A `_NotAssessed` becomes an advisory that
names the reading which stopped the assessment.

### Classes

- **`Radiative frost black ice`** — **`severe`**, `certainty: possible`. Requires
  a dry surface and a measured clear sky. `severe` places it above
  `Advisory.isHighImpact`; ambiguity on an invisible hazard routes toward
  caution, because **black ice is defined by the driver not being able to see
  it** and this catalogue's rule — *"a false alarm is contradicted by the
  windscreen; a false all-clear removes the prompt to look out of it"* — binds
  harder where the windscreen cannot contradict anything.
- **`Freezing fog risk - above zero, saturated, not assessed by this model`** —
  `unknown`. Fires on **`saturated && !frost`**: the model's own blind spot,
  defined by the predicate rather than by a chosen number, so it covers exactly
  the band the calibration calls uncovered. ⚑ Not gated on the sky — **radiation
  fog forms BECAUSE the sky is clear**, and `fog_area_fraction` is a publisher
  field distinct from `cloud_area_fraction`. ⚑ Not gated on rain — freezing
  drizzle in fog is the canonical glaze-ice generator.
- **`Radiative frost, inputs not measured`** — `unknown`, and the description
  names the missing reading (`relative_humidity` or `cloud_area_fraction`).

### Whose claim it is

These are **inferences this package draws**, not advisories MET Norway issued.
They carry `certainty: possible` — the publisher's `symbol_code` no longer lends
them confidence, since the classifier does not consult it — and the description
says so above the byline. That is dignity toward the institute, and what CC BY
4.0 asks of a modified source.

### ⚑ A change to EVERY existing advisory, declared

**`Advisory.description` now carries a `relative_humidity` segment on every
class, including the four from 0.0.6.** If you parse descriptions, they have
changed. `eventClass` and `severity` on the pre-existing classes are unchanged.

### Overridable, and this time actually

`clearSkyCloudPercentMax` is a constructor parameter, a mapper parameter, and
exported. It was documented as *"integrator-overridable"* in three places while
being a bare private const; a compile probe from an integrator's position proved
the absence, and the same probe now passes. ⚑ **50 % remains a chosen figure —
but it can no longer cause silence.** Above it, or with the sky unread, the
verdict is `_NotAssessed`, not `null`: a wrong threshold can downgrade a
finding, never hide one.

### Cost and verification

**No new network cost.** `relative_humidity` and `cloud_area_fraction` were both
already in the `compact` payload this adapter fetches (verified live at
api.met.no, 2026-09-03).

**43 tests**, analyzer clean. The exhaustive switch is proven by deleting a case
and observing the compile error. A live run over 1,260 slices from 15 Nordic
points produced no advisory from these classes — **stated with its control: 0 of
those 1,260 were in the (0, +3 °C] band at all** (range 4.1…20.2 °C), so it shows
non-regression and **cannot** show correct gating. The tests carry that.

**Why the minor bump.** `0.0.x` told an integrator "experimental" about a package
that already implemented the full provider contract.

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
