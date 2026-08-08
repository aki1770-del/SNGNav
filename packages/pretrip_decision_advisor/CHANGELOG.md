# Changelog

## 0.5.4

The affirmative all-clear must now be EARNED. **Your build will not break** — no
signature, type or member changed — **but what your users read WILL change, and
in some cases a briefing you used to get is now a typed stop.** Please read: the
second half of this note is about a recommendation that actively sent drivers
somewhere.

### What you already have, in the version you are running now

Every hazard test in `SnowAwarePretripAdvisor.hazardOf` is guarded
`field != null && ...`. So a forecast slot carrying a temperature and nothing
else does not fail any test — it falls THROUGH all of them and returns
`HourHazard.clear`, and the briefing prints:

> No winter hazard signals in your trip window.
> 出発時間帯に冬季の危険を示す兆候はありません。

That sentence is a claim about the WINDOW. It was being made from data in which
visibility, precipitation and the road surface had never been looked at.

0.5.2 fixed exactly this fabrication one level up — a window with NO forecast at
all — and said so plainly. This is the per-slot half it named and left open, and
0.5.3's own changelog listed it under "Still present — not fixed here".

**This is not a corner case; it is the normal shape of real data.**
`pretrip_source_met_norway` emits `visibilityMeters: null` and
`estimatedRoadCondition: null` on every slot — its own source comment reads
*"Compact product carries neither visibility nor surface state."* And this
package's own `example/main.dart` builds its forecast as
`HourlyForecast(hour: ..., tempCelsius: -6)`, commented *"temperature only, NO
visibility (exactly the shape a compact global forecast gives)"*.

Four ways an all-clear was reported over data nobody measured:

| what happened | what you were told |
|---|---|
| visibility + road surface never measured | "No winter hazard signals in your trip window." |
| caller passed `RoadConditionEstimate.unknown` — honestly saying *it could not look* | identical briefing to a caller reporting a **dry** road |
| a 3-hour trip with only the first hour forecast | "No winter hazard signals in your trip window." |
| `tempCelsius` is `NaN` (every `<=` is false, so nothing decides) | "No winter hazard signals in your trip window." |

### The one that put her on the road

`_findBetterWindow` accepted any later hour scoring at worst `caution` — and an
hour nobody measured scores `clear`. So the advisor offered, as the safer
window, the hour it knew least about.

Run `example/main.dart` on 0.5.2. A **measured 80 m whiteout** at 07:00, later
hours carrying temperature only:

```
Verdict : waitAdvised
Strength: advisoryStrong          ← the strongest this package can say
Delay   : 1:00:00
  - Visibility may drop to ~80 m around 07:00 — whiteout conditions.
  - Conditions improve by about 08:15.
```

It told her to wait out a whiteout and leave at 08:15 — into an hour whose
visibility and road surface were never reported. On 0.5.4 the same example
reads:

```
Verdict : hazardPersists
Delay   : 0:00:00
  - Visibility may drop to ~80 m around 07:00 — whiteout conditions.
  - No clearly better departure window within the next 6 h — consider whether
    this trip is needed today.
```

An unassessable hour is now SKIPPED, not offered. A later hour that IS fully
measured still wins, so the search is not muted — only made honest.

### What changed

- **`brief(...)` throws the new `PretripAssessmentIncompleteException`** when a
  forecast covers the window but the fields deciding the ladder were never
  measured. It extends `PretripDataAbsentException`, so the `catch` clause 0.5.2
  already asked you to write catches it with no edit. The message names the
  exact hour and the exact missing families.
- **`briefOrNull(...)` returns `null`** in that case. Its published contract is
  unchanged — `null` has always meant "we do not know" — it now covers one more
  way of not knowing.
- **`advise(...)` is unchanged**: still returns `null`, still never throws.
- **`evidenceGaps(slot)`** (new) returns the `HazardEvidenceGap`s a slot left
  undecided. Public on purpose: the advisor stops asserting what it did not
  measure, but it does not decide for you what an acceptable gap is. Read them
  and apply your own regional policy.
- **`allClearEarned(forecast:commute:)`** (new) answers before you call, so you
  can branch instead of catch.
- **A non-finite field no longer crashes the advisor.** A `-Infinity`
  temperature or visibility reached `.round()` in `_describe` and threw
  `UnsupportedError: Infinity or NaN toInt` — an **untyped** error, so the
  `on PretripDataAbsentException` clause did NOT catch it and the app went down.
  Such a slot now falls through to the generic chip.
- **`hazardOf` is unchanged in logic** — token-for-token identical to 0.5.2
  (183 tokens, verified). Its only textual difference is one line-wrap applied
  by `dart format` under SDK 3.11, which reformatted this whole package;
  the published 0.5.2 archive is itself format-dirty under that SDK, so the
  reformat is pre-existing debt and lands in its own commit. Absence is
  reported BESIDE the ladder, never on it: a gap never raises a band and never
  lowers one.

### The rule, so the behaviour is predictable

> Positive evidence fires on partial knowledge. Negative conclusions require
> whole knowledge.

A measured hazard still reports from whatever data you have — a whiteout with
everything else absent is still `severe`. Only the affirmative all-clear, and
the affirmative "conditions improve at 08:15", need the whole picture. That is
the same asymmetry 0.5.3 applied to the official-warning line.

`HourHazard` gains **no** `unknown` member. Absence does not belong anywhere on
a measurement scale: at the benign end it invents safety, at the adverse end it
invents danger, and both are fabrications. It is reported in a separate type.

### If you now get a stop where you used to get a briefing

You are being told something true that you were not told before. Three ways
forward:

1. **Fill the gap.** `mergeObservedVisibility` (already exported) puts a
   measured `VisibilityObservation` into the departure hour;
   `estimatedRoadCondition` takes your own road-surface estimate.
2. **Branch.** `briefOrNull(...)` returns `null`; `allClearEarned(...)` tells
   you in advance.
3. **Catch.** `on PretripDataAbsentException` — the clause 0.5.2 asked for.

We would rather hand you a stop you must handle than a green card we did not
earn. Expect the stop to be common with a compact forecast product: that is not
the gate being noisy, it is the honest state of that data.

### Honest bounds — what 0.5.4 does NOT fix

- **`hazardPersists` still says "no clearly better window within 6 h"** after
  skipping hours it could not assess. That is a negative claim on partial
  knowledge, and saying it properly needs a new `PretripMessages` member —
  which is a compile break for anyone who `implements` that class, so it cannot
  ship inside `^0.5.0`. The direction is conservative (it never suggests a
  delay), so it ships as-is and is named rather than hidden.
- **`summarizeAreaConditions` / `AreaConditionRead` are untouched here.** The
  area read runs the same per-slot ladder and has the same gap; it is being
  worked on a separate line and is not changed by this patch.
- **A `-Infinity` temperature still reads as `caution`** (`-Infinity <= 0.0` is
  true). That is inventing a hazard from a non-value — the mirror of inventing
  safety. It is left alone deliberately: this patch never suppresses a band the
  ladder produced, because a gate that can delete a hazard is worse than the
  defect it fixes. Flagged for the safety owner, not silently changed.
- **Compiler-additive, with one bound stated plainly:** new methods were added
  to the concrete `SnowAwarePretripAdvisor`. Subclassing and instantiation are
  unaffected; only a class that `implements SnowAwarePretripAdvisor` (rather
  than the `PretripAdvisor` contract it exists for) would need the new members.

## 0.5.2

### Safety defect in 0.5.1 and earlier — please read

**Up to and including 0.5.1, a trip with NO forecast data reported its peak
hazard as `HourHazard.clear`.** A morning that nobody forecast was handed to the
driver as a clear morning. A UI that colours a card from `briefing.peakHazard`
(this catalog's own example does: `pretrip_source_met_norway` prints
`briefing.peakHazard.name` with no verdict check) painted **green on a total
data blackout** — in the package that speaks to the driver *before she leaves
the house*. `AreaConditionRead.areaHazard` had the same hole: an uncovered
window returned `HourHazard.clear` as a "non-asserted placeholder", invisible to
a caller colouring from the band.

`HourHazard` has no `unknown` member and both fields are non-nullable, so on the
0.5.x line there was nowhere to put "we do not know". Adding an enum value or a
nullable field would break every consumer's build, so instead of fabricating a
value where an honest one does not exist, **this release STOPS**: it throws a
typed, catchable exception that names exactly what happened and how to proceed.

pub.dev releases are immutable and cannot be withdrawn; this note is the recall.

### Non-breaking (no signature changed; source-compatible on `^0.5.1`)

- **`SnowAwarePretripAdvisor.brief(...)` now throws
  `PretripForecastCoverageException`** when no forecast slot covers the trip
  window (previously it returned a briefing with `peakHazard: HourHazard.clear`).
  The exception message says what happened, why we refuse to guess, and the way
  forward. `PretripBriefing.peakHazard` on any briefing `brief` returns is now
  always derived from at least one real slot — safe to colour from.
- **`SnowAwarePretripAdvisor.briefOrNull(...)`** (new) returns `null` in exactly
  that case if you would rather branch than catch.
- **`AreaConditionRead.areaHazard` now throws `AreaForecastNotCoveredException`**
  when `forecastCovered` is false (previously it returned `HourHazard.clear`).
  Guard with `forecastCovered` first (as `areaConditionChips` always has), or
  read the new **`AreaConditionRead.areaHazardOrNull()`**, which returns `null`.
- **New exception types** `PretripDataAbsentException` (base),
  `PretripForecastCoverageException`, `AreaForecastNotCoveredException` — catch
  the base to handle every absence stop.
- `advise(...)` is **unchanged**: it still returns `null` when the window is not
  covered, exactly as before.

Migration in two lines:

```dart
// If you called brief() and rendered peakHazard directly:
try { render(advisor.brief(...)); }
on PretripDataAbsentException catch (e) { renderNoForecastCard(e.message); }
// or: final b = advisor.briefOrNull(...); if (b == null) renderNoForecastCard();
```

Absence is a first-class value on the 0.6.x line (`HourHazard.unknown`); this
patch delivers the honest stop inside the `^0.5.1` range that a 0.6.0 upgrade
would not reach.

## 0.5.1

- Internal: `radiativeFrostRisk` now delegates to
  `navigation_safety_calibration`'s `isRadiativeFrostBlackIce` — the SAME
  function the in-drive road-surface classifier calls — instead of holding its
  own inline copy of the ceiling + percent-guard + dew-point-threshold logic.
  Behaviour is identical (guarded by an equivalence test); the change removes
  the second independently-maintained copy that could have drifted from the
  in-drive path, so the pre-trip briefing and the live in-drive screen are now
  provably wired to one source of truth for black ice. Requires
  `navigation_safety_calibration ^0.1.3`. No public API change.

## 0.5.0

Humidity-aware black ice — the no-precipitation killer the ambient-only
frost check missed. Envelope-bounded after adversarial review.

- **`SnowAwarePretripAdvisor.hazardOf` gains a radiative-frost condition**:
  when a forecast slot carries relative humidity, the advisor computes the
  Magnus effective road-surface estimate (via `navigation_safety_calibration`
  — the family's single source of truth; the package's FIRST runtime
  dependency, per the depend-don't-copy discipline) and flags **caution**
  when the estimate is at/below freezing while ambient is above zero —
  freezing fog / hoar frost / clear-sky radiative cooling, no precipitation
  required. Caution-add-only (the estimate never exceeds ambient).
- **Bounded to the calibration's documented envelope**: the condition
  requires ambient ≤ `radiativeFrostAmbientCeilingCelsius` (+3.0 °C,
  "several degrees above 0 °C"). The unbounded dew-point test alone fires
  on benign dry days (probe-measured: 20 °C at 25% RH) — adversarial review
  caught the cry-wolf class and the ceiling is the fix, pinned by tests.
- New reason chip `blackIceRadiativeRisk` (EN + JA:
  「放射冷却で路面だけが凍ることがあります(ブラックアイス)」), emitted only for
  the above-zero-ambient window; at/below zero the existing freezing-air
  chip keeps precedence (brief()-level tests pin both the emission and the
  precedence).
- Unit seam, stated precisely: `HourlyForecast.humidityRH` is PERCENT; the
  calibration takes a FRACTION. The guard ADAPTS (does NOT mirror) the
  boundary classes of `navigation_safety_core`'s percent door: core throws
  on implausible input; a briefing must never crash on one dirty forecast
  slot, so here every rejected class — `<= 0` sentinels, everything below a
  5% physical-plausibility floor (which kills the mis-wired-fraction class
  INCLUDING exactly `1.0`, saturated air, its most common value), `> 105`,
  non-finite, and subnormal underflow — simply adds nothing. Absence (or corruption) of data is never presence of hazard,
  and never an exception out of `hazardOf`.
- Honest bound: the calibration's surface-cooling magnitude is documented
  UNVERIFIED-conservative (early-warning direction); see
  KNOWN_LIMITATIONS.md, updated with the full envelope statement.

## 0.4.0

Add the destination-AREA condition read (the FAMILY-THREAD section) — a
PUBLIC-WEATHER-AT-A-PLACE read that watches no person and claims no road.

**BREAKING (source-incompatible for downstream language subclasses):**
`PretripMessages` gained eight required members — `areaOfficialWarning`,
`areaNoOfficialWarning`, `areaWarningCheckUnavailable`, `areaHazardChip`,
`areaHazardBand`, `areaForecastNotCovered`, `areaMeasuredVisibility`,
`areaNoMeasuredVisibility`. Any downstream `class _Xx extends PretripMessages`
(e.g. a Korean locale) must add these eight `area*` overrides to compile.
`PretripMessages.en` / `.ja` carry them; `forLanguage` is unchanged.

Honesty hardening on the area chips:

- `areaOfficialWarning` (en) now frames the verbatim event as "winter warning
  or advisory" so a JMA 注意報 (advisory) is never upgraded to a "warning" in
  English. The verbatim event name still carries the precise class.
- `areaNoOfficialWarning` is scoped to "snow" (en + ja) — it states only the
  negative actually checked (snow-class), never a wider all-winter negative it
  did not verify.

## 0.3.0

Add a localization seam for the reason chips and an offline daylight clock —
**non-breaking**. English stays the default and existing output is byte-for-byte
unchanged; the daylight clock is silent unless a trip opts in via `geo`.

Localization seam:

- Add `PretripMessages` — a hand-rolled, pure-Dart locale table for the
  advisor's reason chips. `PretripMessages.en` (default + fallback) and
  `PretripMessages.ja`; `PretripMessages.forLanguage(code)` resolves one and
  falls back to English for any language not carried (never throws).
- `SnowAwarePretripAdvisor` gains an optional `messages` parameter
  (defaults to `PretripMessages.en`), so every existing caller is unchanged.
  Pass `PretripMessages.ja` to emit the same deterministic logic in Japanese.
- Add abstract `PretripMessages.daylightChip(TripDaylight)`, overridden in
  `en`/`ja`, for the daylight-clock note (below).
- Measured safety numbers (visibility, temperature, minutes, hours) pass
  through every locale verbatim — a translation reorders words, never a value.

Offline daylight clock:

- Add `TripGeo` (latitude/longitude/utcOffset value type), `TripDaylight` +
  `DaylightPhase` (the solar facts for one trip instant — phase, sunrise/sunset
  HH:MM, reference event, minutes-to-event, deep-dark flag; value-equality DTO),
  and the top-level `evaluateDaylight(instant, geo)` — pure Dart, no network and
  no clock, so the answer survives the compound-failure (no GPS / no maps) path.
  It states only light and time and never infers a road hazard from the clock.
- `CommuteShape` gains an optional `geo` field (**defaults `null`** = feature
  absent, fully backward compatible). When set, `brief(...)` adds one daylight
  note for the darkest of departure/arrival/worst-hazard instant; when `null`,
  output is unchanged.
- No behaviour change for existing callers: verdicts, thresholds, and the
  honesty rule are identical across locales and with no `geo`; only the chip
  wording differs by locale, and the daylight note is opt-in via `geo`.

## 0.2.1

Documentation + example only — no API or behaviour change.

- Replace the example with a runnable end-to-end snippet: a measured
  `VisibilityObservation` + `WeatherForecast` → `mergeObservedVisibility` →
  `SnowAwarePretripAdvisor.brief(...)` → the typed verdict/chips an edge
  developer renders in their own UI (the real captured output is shown in the
  README, not hand-written).
- README: add an "End-to-end: measured source → briefing" section, and a
  "Pair with a measured source" table linking `pretrip_source_jma` /
  `pretrip_source_digitraffic` / `pretrip_source_met_norway` (all emit the same
  `VisibilityObservation` / `WeatherForecast`, so you swap region without
  changing UI code). Point to the standalone Flutter reference integration that
  assembles and renders the briefing from the published packages alone.
- Honesty rules unchanged and preserved verbatim: visibility is never
  estimated; a warning never produces a number; an observation is valid for the
  departure hour only; null = the driver's own judgment.

## 0.2.0

The package is no longer interface-only. It now ships a working reference
advisor and the visibility-merge logic, so `pub add`-ing the package gives a
consumer a usable advisor — not just types.

- Add `SnowAwarePretripAdvisor` — a deterministic, pure-Dart reference
  implementation of `PretripAdvisor`. No LLM, no network, no clock: the same
  typed inputs always produce the same recommendation, so the worst-case path
  stays offline. Null forecast fields contribute nothing to hazard scoring;
  the advisor returns `null` when the forecast does not cover the departure
  window, and honours the contract's honesty rule (required/unknown commutes
  are never urged to delay — `honestyMode`).
- Add `PretripBriefing`, `PretripVerdict`, and `HourHazard` — the richer typed
  verdict the reference advisor exposes via `brief(...)` for UIs that want the
  structured result alongside the contract-shaped `PretripRecommendation`.
- Add `VisibilityObservation` + `mergeObservedVisibility(...)` — a
  source-neutral measured-visibility observation and its departure-hour merge
  (the measured value overrides forecast visibility for the departure hour
  only; it is never projected into later hours). Pure Dart; a source-specific
  fetcher that owns the HTTP dependency stays outside this package.
- The package remains pure Dart (no `http`, no Flutter dependency). The
  numerical thresholds the reference advisor uses are documented at their
  declaration site; consumers may still implement `PretripAdvisor` themselves.

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.0 — 2026-05-08 — Graduation: interface-only contract

The package transitions from internal-only scaffold to a published
interface-only contract on pub.dev. The interface, DTOs, commute shape,
weather forecast inputs, and decoupled driver profile spec are stable
enough to commit to a public surface; reference implementations remain
out of scope at this version.

Founding motivation: the pre-trip departure-timing decision ("should I
leave now or wait an hour?") is often a larger pain point than in-drive
alerts. Apps focused on alerts during driving address a smaller window
than apps that address departure timing. This package defines the shape
of an advisor that could help with that question, so other packages and
applications can experiment against a common interface.

Reference advisor implementations compose this contract with their own
weather data source, route data, and driver-profile bridge. Concrete
advisors must justify their own numerical thresholds; this package
declares none.

KNOWN_LIMITATIONS.md preserves honesty disclosures: API may evolve;
no numerical thresholds; no taxonomy claims; no driver-profile coupling.

## 0.0.1 — 2026-04-30 — Initial scaffold (not published)

Initial scaffold of the abstract advisor contract, recommendation DTO,
commute shape, weather forecast inputs, and decoupled driver profile
spec. Not published to pub.dev.
