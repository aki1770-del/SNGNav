# Changelog

## 0.5.3

**Safety fixes at two seams, plus a crash. Your build will not break — and that
is the problem this note exists to solve.** No signature, type, or member
changed, so nothing will stop you upgrading. But **sentences your users read will
change in both directions**, one recommendation that actively sent drivers
somewhere has been withdrawn, and **one path that took the whole app down no
longer does**. If you skim one section of this changelog, skim this table.

| where | up to 0.5.2 your users saw | on 0.5.3 they see |
|---|---|---|
| **destination-area warning line**, when you never passed `warningCheckAvailable` | "No active snow warning or advisory for this area."<br>「この地域に発表中の雪の警報・注意報はありません。」 | "Official-warning check unavailable — a warning may be in effect that is not shown here."<br>「警報・注意報の確認ができませんでした — 実際には発表されている可能性があります。」 |
| **destination-area warning line**, when you held a warning *and* honestly reported the check incomplete | "Official-warning check unavailable…" — **the 大雪警報 you held was dropped** | "Official winter warning or advisory in effect for this area: 大雪警報." |
| **destination-area read**, when a sensor reading arrived non-finite | **your app went down** — an untyped `UnsupportedError` your `catch` clause did not hold | the reading is reported absent; the hazard band is unchanged |
| **destination-area visibility line**, when the distance to the station was missing | "…(秋田, **~0 km away**)." — the station placed where she is standing | "No measured visibility available for this area." |
| **trip-window briefing**, when the forecast carried a temperature and nothing else | "No winter hazard signals in your trip window."<br>「出発時間帯に冬季の危険を示す兆候はありません。」 | `brief(...)` throws `PretripAssessmentIncompleteException`; `briefOrNull(...)` returns `null` |
| **suggested departure delay**, when the later hours were unmeasured | "Conditions improve by about 08:15." — **it sent her into the hour it knew least about** | that hour is skipped; a later, fully-measured hour can still win |

The two evidence fixes are one rule, applied at two seams:

> **Positive evidence fires on partial knowledge. Negative conclusions require
> whole knowledge.**

The crash fixes (1d, 1e) are a second rule, and it is the same one the type
system was already trying to tell us:

> **A value that is not a number is not a measurement.** `NaN` and `±Infinity`
> are absence wearing a number's clothes, and `0` is absence wearing a
> confident number's clothes. Neither may be reported as a reading.

A hazard you *saw* still reports from whatever you measured. Only the
affirmative claims — "no warning is in force", "no winter hazard in your
window", "conditions improve at 08:15" — need the whole picture, because each
is a claim about *completeness*, and each is a claim a driver acts on.

*There is no 0.5.4.* These two fixes were built on separate branches, were
reconciled into this single release, and neither is lost. Nothing was published
between 0.5.2 and this version.

### Fix 1 — the destination-AREA warning line

#### 1a. A warning you already held could be replaced by a shrug (safety fix)

`areaConditionChips` tested `warningCheckAvailable` **before** it tested whether
a warning was actually in hand:

```dart
if (!r.warningCheckAvailable) {        // ← ran first
  chips.add(m.areaWarningCheckUnavailable());
} else if (r.officialWarningVerbatim != null) {   // ← unreachable when the
  chips.add(m.areaOfficialWarning(...));          //   check was incomplete
}
```

So a caller who reached one publisher, got a real `大雪警報` (heavy-snow
warning), failed to reach a second publisher, and **honestly reported the check
as incomplete** — `warningEventVerbatim: '大雪警報', warningCheckAvailable:
false` — had the heavy-snow warning **dropped** and replaced by
「警報・注意報の確認ができませんでした」 / "Official-warning check unavailable".
Admitting the gap cost the driver the warning she had.

**0.5.3 renders a warning in hand first, whatever the check's completeness.** A
hazard seen is a hazard real, even on partial data. Only the *negative* claim
needs a complete check.

*If you relied on the old order to suppress a warning while a check was
incomplete, that warning now renders.* We believe that is what you wanted.

#### 1b. `warningCheckAvailable` now defaults to `false` (behaviour change)

`summarizeAreaConditions({... bool warningCheckAvailable = true})` defaulted to
the reassuring value. The zero-effort call — no warning passed, no flag passed —
rendered:

> No active snow warning or advisory for this area.
> この地域に発表中の雪の警報・注意報はありません。

**from a check that was never performed.** "No advisory is in force" is a claim
about *completeness*: you may only make it when you actually asked and the
publisher actually answered. Silence from a publisher you did not ask is not an
all-clear — it is a gap. We were making that claim for free, by default, on
behalf of callers who had never reached a publisher at all.

The default is now `false`, so an un-asserted check renders
「警報・注意報の確認ができませんでした — 実際には発表されている可能性があります。」
/ "Official-warning check unavailable — a warning may be in effect that is not
shown here."

**What to do:** if you *do* reach the publisher and it has nothing in force,
pass `warningCheckAvailable: true`. That case still renders exactly as before —
it is the one call that earns the sentence, and it is a one-word diff:

```dart
summarizeAreaConditions(
  forecast: f, now: n, areaLabel: 'Akita',
  warningEventVerbatim: publisherWarningOrNull,
  warningCheckAvailable: true,   // ← you reached the publisher; it answered
);
```

If you pass a warning verbatim, you need change nothing: 1a makes it render
regardless of this flag.

#### 1c. A doc that was still teaching a removed behaviour

`summarizeAreaConditions`' own doc comment said the band "is left non-asserted
([HourHazard.clear])" when no forecast covered the window — describing the
pre-0.5.2 placeholder that 0.5.2 had already removed. An integrator who read it
and coloured a card from `areaHazard` was told the no-forecast case paints
green; the code in fact throws `AreaForecastNotCoveredException`. Corrected.
This is a defect, not housekeeping: the doc ships in the archive, and it is what
a consumer reads before they read the code.

#### 1d. A non-finite sensor reading took the app down (safety fix)

This is the **same defect** as the non-finite crash listed under Fix 2c, on the
sibling path. Fix 2 closed it for the trip-window briefing and left the area read
open, so one release fixed half a defect. Both halves ship here.

`VisibilityObservation` is **public, exported and unvalidated** — `double meters`
and `double distanceKm`, no finiteness constraint — and `summarizeAreaConditions`
called `.round()` on both:

```dart
measuredVisibilityMeters: observed?.meters.round(),
visibilityDistanceKm:     observed?.distanceKm.round(),
```

Reproduce it yourself — this was run against the **published 0.5.2 archive**
(`dependencies: pretrip_decision_advisor: 0.5.2`), not a working tree, and the
output below is verbatim:

```dart
summarizeAreaConditions(
  forecast: f, now: n, areaLabel: 'Akita',
  observed: VisibilityObservation(
    meters: double.nan,           // or distanceKm: double.infinity
    stationId: 1, stationName: '秋田', measuredAt: n, distanceKm: 4.2,
  ),
);
// THREW: Unsupported operation: Infinity or NaN toInt
// is PretripDataAbsentException -> false
// #1  double.round (dart:core-patch/double.dart:196:34)
// #2  summarizeAreaConditions
//       (package:pretrip_decision_advisor/src/area_condition_read.dart:176:48)
```

`false` is the whole problem. It is an **untyped** error out of a pure, offline
function, so the `on PretripDataAbsentException` clause 0.5.2 asked you to write
did not catch it and the app went down — on the screen a driver reads *before she
leaves the house*.

**It is reachable from the network, not only by hand.** The source adapters build
`VisibilityObservation` straight from publisher JSON, and `pretrip_source_jma`
parses numbers with `double.tryParse`, which returns `Infinity` for the string
`"Infinity"` and for an overflowing literal such as `"1e400"`.

**0.5.3 treats a non-finite reading as ABSENT** — the same equivalence
`evidenceGaps` already makes (`vis == null || !vis.isFinite` is one condition,
not two). Absence on this read has one spelling, already published and already
documented on those fields: `null`, and the chip says so. **No new member, no new
type, no new vocabulary** — which is also why it fits inside `^0.5.0`.

- **non-finite `meters`** ⇒ all three visibility fields are `null` (they are one
  composite claim, and their own docs already said "Null when there is no
  measurement").
- **non-finite `distanceKm`** ⇒ only the distance is withdrawn. The measurement
  is a real number and survives: positive evidence fires on partial knowledge.

**The hazard band is untouched.** `mergeObservedVisibility` still carries your
reading into the departure slot and `hazardOf` still judges it. A measured 80 m
whiteout whose station distance is missing still reports `severe` — you lose the
distance, never the hazard. This release does not delete bands.

#### 1e. A missing station distance was rendered as `~0 km away` (safety fix)

`areaConditionChips` filled a missing distance with `?? 0`:

```dart
m.areaMeasuredVisibility(
  r.measuredVisibilityMeters!,
  r.visibilityStationName ?? '',
  r.visibilityDistanceKm ?? 0,   // ← absence arriving as a value
)
```

`0` is not a neutral filler. It is the **nearest possible** station — maximum
relevance — in the one clause a driver reads to judge how much a reading is about
*her*. A reading from a station whose distance we never knew was presented as a
reading from her own position. Run against the **published 0.5.2 archive**, with
`visibilityDistanceKm: null`, verbatim:

```
Nearest measured visibility ~80 m (秋田, ~0 km away).
最寄りの計測視程: 約80m(秋田、約0km先)。
```

The measured-visibility chip is a composite of two numbers, so **it now renders
only when it holds both**; otherwise it degrades to the line that needs no
number, exactly as `_describe` degrades to its no-number fallback. The guard sits
in `areaConditionChips`, not only in `summarizeAreaConditions`, because
`AreaConditionRead`'s constructor is public and a directly-constructed read
reached the same `?? 0`.

*If you were reading `~0 km` as "distance unknown", it now reads as the honest
"none" line instead.*

### Fix 2 — the trip-window affirmative all-clear must be EARNED

#### 2a. What you already have, in the version you are running now

Every hazard test in `SnowAwarePretripAdvisor.hazardOf` is guarded
`field != null && ...`. So a forecast slot carrying a temperature and nothing
else does not fail any test — it falls THROUGH all of them and returns
`HourHazard.clear`, and the briefing prints:

> No winter hazard signals in your trip window.
> 出発時間帯に冬季の危険を示す兆候はありません。

That sentence is a claim about the WINDOW. It was being made from data in which
visibility, precipitation and the road surface had never been looked at.

0.5.2 fixed exactly this fabrication one level up — a window with NO forecast at
all — and said so plainly. This is the per-slot half it named and left open.

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

#### 2b. The one that put her on the road

`_findBetterWindow` accepted any later hour scoring at worst `caution` — and an
hour nobody measured scores `clear`. So the advisor offered, as the safer
window, the hour it knew least about.

`example/main.dart` builds a **measured 80 m whiteout** at 07:00 with later
hours carrying temperature only. Both outputs below were run, not recalled — the
first on the 0.5.2 tree, the second on this one:

```
0.5.2                                  0.5.3
Verdict : waitAdvised                  Verdict : hazardPersists
Strength: advisoryStrong               Strength: advisoryWeak
Delay   : 1:00:00                      Delay   : 0:00:00
  - Visibility may drop to ~80 m         - Visibility may drop to ~80 m
    around 07:00 — whiteout.               around 07:00 — whiteout.
  - Conditions improve by about        - No clearly better departure window
    08:15.                                 within the next 6 h — consider
                                           whether this trip is needed today.
```

It told her to wait out a whiteout and leave at 08:15 — into an hour whose
visibility and road surface were never reported. An unassessable hour is now
SKIPPED, not offered. A later hour that IS fully measured still wins, so the
search is not muted — only made honest.

#### 2c. What changed

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
  Such a slot now falls through to the generic chip. **The identical crash on the
  destination-area path is fixed in 1d above** — it is one defect with two doors,
  and shipping only this one would have been shipping half a fix.
- **`hazardOf` is unchanged in logic** — token-for-token identical to 0.5.2
  (183 tokens, verified). Its only textual difference is one line-wrap applied
  by `dart format` under SDK 3.11, which reformatted this whole package; the
  published 0.5.2 archive is itself format-dirty under that SDK, so the reformat
  is pre-existing debt and lands in its own commit. Absence is reported BESIDE
  the ladder, never on it: a gap never raises a band and never lowers one.

`HourHazard` gains **no** `unknown` member. Absence does not belong anywhere on
a measurement scale: at the benign end it invents safety, at the adverse end it
invents danger, and both are fabrications. It is reported in a separate type.

#### 2d. If you now get a stop where you used to get a briefing

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

### Compatibility

**Compiler-additive.** No signature, type, or member changed, and this is why
every fix here ships as a patch inside `^0.5.0` where a `0.6.0` could not reach a
caret-pinned consumer. This is not a guess about who is out there: the three
published packages that depend on this one — `pretrip_source_jma`,
`pretrip_source_met_norway`, `pretrip_source_digitraffic` — each pin
`pretrip_decision_advisor: '>=0.5.0 <0.7.0'` in their own published pubspecs, and
0.5.3 lands inside that. A consumer who wrote the ordinary `^0.5.0` gets
`>=0.5.0 <0.6.0` and receives 0.5.3 too; a `0.6.0` would have reached neither
them nor anyone else pinned that way. One bound stated plainly: new methods were added to the
concrete `SnowAwarePretripAdvisor`; subclassing and instantiation are
unaffected, and only a class that `implements SnowAwarePretripAdvisor` (rather
than the `PretripAdvisor` contract it exists for) would need the new members.

**Behaviourally it is NOT additive, and we are not going to hide that in a
version number.** A caller who never passed `warningCheckAvailable` sees one
*fewer* affirmative sentence; a caller who passed a warning alongside an
incomplete check sees one *more* warning; a caller feeding a compact forecast
product gets a typed stop where a briefing used to be. All three directions are
deliberate. The table at the top of this entry is the whole surface.

### Honest bounds — what 0.5.3 does NOT fix

- **The destination-AREA hazard chip still reports an unearned all-clear.**
  This is the sharpest bound in the release, because the two fixes above now
  answer the SAME input differently. Given a forecast whose slots carry a
  temperature and nothing else:

  ```dart
  advisor.brief(forecast: tempOnly, ...)         // throws PretripAssessmentIncompleteException
  areaConditionChips(summarizeAreaConditions(forecast: tempOnly, ...), m)[1]
  // -> "Forecast hazard for this area: no winter hazard signal."
  //    「この地域の予報ハザード: 危険の兆候なし。」
  ```

  The area read runs the same per-slot ladder and has the same gap. Fix 2 was
  not applied to it, and the reason is a hard one rather than a choice: closing
  it honestly needs a "could not assess" line, which is a **new
  `PretripMessages` member** — and `PretripMessages` is a published
  `abstract class`, so adding a member is a compile break for anyone who
  `implements` it. It cannot ship inside `^0.5.0`. Making `areaHazard` throw
  instead would make `areaConditionChips` throw out of a pure function, which is
  worse than the defect.

  **What you can do today, inside `^0.5.0`:** `evidenceGaps(slot)` is public, so
  an area-read consumer can ask the same question the briefing now asks —
  `forecast.hourly.any((s) => advisor.evidenceGaps(s).isNotEmpty)` — and render
  their own "could not assess" state beside the chips.

  Tracked for the 0.6.x line, where `HourHazard.unknown` makes absence a
  first-class value. Pinned by an executable test so it cannot go quiet:
  `test/reconciliation_test.dart`, group *"the gap this release does NOT close"*.

- **`hazardPersists` still says "no clearly better window within 6 h"** after
  skipping hours it could not assess. That is a negative claim on partial
  knowledge, and saying it properly needs the same new `PretripMessages` member.
  The direction is conservative (it never suggests a delay), so it ships as-is
  and is named rather than hidden.

- **A `-Infinity` temperature still reads as `caution`** (`-Infinity <= 0.0` is
  true). That is inventing a hazard from a non-value — the mirror of inventing
  safety. It is left alone deliberately: this release never suppresses a band
  the ladder produced, because a gate that can delete a hazard is worse than the
  defect it fixes. Flagged for the safety owner, not silently changed.

  **The same applies on the area path, and 1d does not change it.** A
  `-Infinity` *visibility* satisfies `vis < 50`, so it lights `severe`:

  ```dart
  final r = summarizeAreaConditions(
    forecast: f, now: n, areaLabel: 'Akita',
    observed: VisibilityObservation(
      meters: double.negativeInfinity,
      stationId: 1, stationName: '秋田', measuredAt: n, distanceKm: 4.2,
    ),
  );
  r.areaHazard;                 // HourHazard.severe   ← from a non-value
  r.measuredVisibilityMeters;   // null                ← 1d, correctly absent
  ```

  The two lines disagree on purpose: 1d governs the chip's arithmetic, never the
  ladder's judgement. Pinned by an executable test so it cannot drift —
  `test/area_non_finite_observation_test.dart`, group *"the ladder is untouched —
  the guard cannot delete a hazard"*.

- **`VisibilityObservation` itself is still unvalidated, and that is where this
  defect actually lives.** `meters` and `distanceKm` are plain `double`s with no
  finiteness constraint, so the type permits a value the domain does not:

  ```dart
  VisibilityObservation(         // analyzer: "No issues found!"
    meters: double.nan, stationId: 1, stationName: 's',
    measuredAt: DateTime(2026), distanceKm: double.infinity,
  );
  // meters.isFinite -> false   distanceKm.isFinite -> false
  ```

  1d and 1e stop that value being *reported* as a measurement. They do not stop
  it being *constructed*, and they cannot: a validating constructor is an
  `assert` or a throw at a call site that compiles today, which is a break for a
  consumer whose debug build currently passes such a value through. Every guard
  we can reach is a guard each consuming seam has to remember — which is the same
  shape as the defect. **The real fix is a type that cannot hold a non-number**,
  and it belongs on the 0.6.x line beside `HourHazard.unknown`. Named here rather
  than quietly guarded seam by seam.

  What you can do today, inside `^0.5.0`: check `meters.isFinite` before you
  construct one. `pretrip_source_jma` parses with `double.tryParse`, which
  returns `Infinity` for `"Infinity"` and for `"1e400"`, so a publisher can hand
  you one without malice.

- **The measured-visibility chip is now all-or-nothing.** When the distance is
  missing, 1e withholds the whole line rather than render "~80 m (秋田)" without
  it — because saying so needs a **new `PretripMessages` member**, and
  `PretripMessages` is a published `abstract class`, so adding one is a compile
  break for anyone who `implements` it. It cannot ship inside `^0.5.0`. The
  reading is not lost: it is still on `AreaConditionRead.measuredVisibilityMeters`
  and still in the hazard band. Only the sentence is withheld. Same bound, same
  cause, and same 0.6.x home as the two entries above.

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
