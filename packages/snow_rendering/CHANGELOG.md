# Changelog

## 0.3.4

**Both black-ice lines told the driver that hard braking was strictly
forbidden. They now ask her to avoid abrupt braking and steering.** This
changes what two spoken lines say, in both languages. Nothing else in `lib/`
changes.

### The lines, before and after

| Line | Before (to 0.3.3) | From 0.3.4 |
|---|---|---|
| `invisibleBlackIceAnnouncement`, ja | ブラックアイスバーンに注意。路面は濡れて見えても、凍結しているおそれがあります。急ハンドル、急ブレーキは厳禁。速度を落としてください。 | ブラックアイスバーンに注意。路面は濡れて見えても、凍結しているおそれがあります。速度を落とし、急ブレーキ・急ハンドルは避けてください。 |
| `invisibleBlackIceAnnouncement`, en | Black ice warning. The road may look merely wet but may be frozen. No abrupt steering or braking. Reduce speed. | Black ice warning. The road may look merely wet but may be frozen. Reduce speed and avoid abrupt braking or steering. |
| `RoadSurfaceState.blackIce.announcement`, ja | ブラックアイスバーンに注意。路面が凍結しているおそれがあります。急ハンドル、急ブレーキは厳禁。速度を落としてください。 | ブラックアイスバーンに注意。路面が凍結しているおそれがあります。速度を落とし、急ブレーキ・急ハンドルは避けてください。 |
| `RoadSurfaceState.blackIce.announcement`, en | Black ice warning. The road surface may be frozen. No abrupt steering or braking. Reduce speed. | Black ice warning. The road surface may be frozen. Reduce speed and avoid abrupt braking or steering. |

### Why

- **急ブレーキ is also the everyday word for an emergency stop, and 厳禁
  ("strictly forbidden") admits no exception.** Read literally, the old
  Japanese line forbade the one act a driver may need on ice, and "No abrupt
  steering or braking." did the same in English. The line is spoken at a moment
  a data refresh chose, not one her traffic chose.
- **A spoken line may ask her to avoid abrupt inputs; it must not forbid
  braking or stopping.** The new lines ask, and put the request to slow down
  first.
- The general line still does not say the road "may look wet": it is also
  reached during visible snowfall, where that would be false.

### If you use the exact text

- **You receive this without changing your constraint.** A caret constraint
  such as `^0.3.0` admits 0.3.4, so your next `dart pub upgrade` changes what
  these two lines say.
- **If you ship audio recorded for each line** (clips looked up by their text),
  re-record these when you take this release. Until you do, the lookup misses
  and those lines fall to your fallback: silence, or a different voice.
- **The JAF advisory text carried on `invisibleBlackIceAnnouncement.vocabulary`
  is unchanged**, and its black-ice entry also forbids abrupt starts and stops
  in absolute terms. The new test below checks spoken lines only; it does not
  cover that text.

A new test (`test/models/no_braking_prohibition_test.dart`) fails if any spoken
line this package exports, in either language, forbids braking or stopping. It
proves itself first against sentences it must flag and sentences it must pass.

### A correction to 0.3.3

0.3.3 says a check in the repository fails the build if the `version:` in
`sngnav_coverage.yaml` drifts from the package version. That check is not yet
on the repository's main branch, so today nothing fails the build when they
drift. This release keeps them equal by hand.

## 0.3.3

**Documentation only. No code change.**

`sngnav_coverage.yaml` is corrected against this package's code.

- **S-044 said it "maps RoadSurface enum to shader params". There are no shader
  parameters here** — the word "shader" does not occur anywhere in `lib/`. What
  `RoadSurfaceState.fromCondition` returns is a classification carrying a grip
  factor; the mapping to anything drawn is the application's, as the package
  documentation has always said. There is also no type named `RoadRenderState`.
- **S-046 understated what is here.** The file said the render state is stateless
  and transition handling was open. Debouncing exists: `HysteresisFilter`
  requires a new value in at least 2 of the last 3 readings before it is
  adopted, and distinguishes "no readings yet" from "a reading whose value is
  null". What is still open is animated interpolation between states.
- **S-043 and S-045** named a `PrecipitationParams.fromWeather()` and a
  `VisibilityFactor.compute(weatherData)` that do not exist. They are
  `PrecipitationConfig.fromCondition(WeatherCondition)`, whose null return means
  the feed reported no precipitation at all rather than "none", and
  `VisibilityDegradation.compute(visibilityMeters)`.
- **S-048** now says explicitly that `DataBudget` governs network fetches and is
  not the particle-density cap that row is about.
- **The total was 62 and the registry holds 66.** The seven `sngnav_coverage.yaml`
  files in the repository are the registry; counted on 2026-09-20 they enumerate
  66 unique ids, S-001 to S-066. 62 was never true of any population: all seven
  files were written in one commit on 2026-04-05 and the union was already 66
  that day.
- **`version:` said 0.1.0** for a package shipping 0.3.x. It now equals the
  package version, and a check in the repository fails the build if they drift
  apart again.

## 0.3.2

**Documentation only. No code change.**

Comments and documentation that used this project's internal shorthand now say
the same thing in plain words. Where earlier entries in this changelog used that
shorthand, they were reworded; no fact in them changed.

- `analysis_options.yaml`: the comment above the analyzer's strict modes now
  says what the modes do, instead of pointing at an internal review note.
- `SAFETY_BOUNDARY.md`: the safety-boundary record is reworded the same way. No
  boundary moved: the changed lines lost internal names and references, and
  nothing changed about what the package does, what it does not do, or what it
  leaves to you.
- `pubspec.yaml`: two comments (and the version).
- `KNOWN_LIMITATIONS.md`: five passages, reworded.
- `lib/snow_rendering.dart`, `lib/src/assessment/driving_condition_assessment.dart`,
  `lib/src/models/recommended_response.dart` and
  `lib/src/models/road_surface_announcement.dart`: comments only.
- Four test files: comments only.
- `CHANGELOG.md`: the 0.1.0 entry and the 0.2.1 and 0.2.2 headings.

Every changed Dart file was compared before and after with its comments removed:
the code is identical. No other file changed.

## 0.3.1

**`dart pub get` inside the published package now works. No code change.**

The published 0.3.0 `pubspec.yaml` still carried development-only
`dependency_overrides` pointing at `../driving_weather`, `../navigation_safety_calibration` and
`../japanese_snow_vocabulary` -- folders that exist only in this
package's source repository. Anyone who downloaded the package and ran
`dart pub get` inside it (to run its tests, or when an editor opened it) got exit
code 66: "depends on japanese_snow_vocabulary from path which doesn't exist". pub does not remove
`dependency_overrides` when a package is published.

Apps that depend on `snow_rendering` were not affected: a dependency's overrides never
apply to the app that uses it. Checked: an app depending on `snow_rendering: 0.3.0`
resolves normally.

The overrides now live in `pubspec_overrides.yaml`, which pub does not publish.
Apart from `pubspec.yaml` and this changelog, the published files are identical
to 0.3.0.

## 0.3.0

### Safety defect in 0.2.7 and earlier — please read

**Up to and including 0.2.7, this package told drivers "Conditions normal"
about roads it had no data for.**

`RoadSurfaceState.fromCondition()` could not say "I don't know". Its return type
was non-nullable, so a `WeatherCondition` carrying no real measurements fell
through the decision tree to `RoadSurfaceState.dry` — and `dry` carries
`gripFactor: 1.0`. The full chain was:

```
no data  ->  RoadSurfaceState.dry  ->  gripFactor 1.0  (MAXIMUM GRIP)
         ->  RecommendedResponse.proceed
         ->  advisoryMessage "Conditions normal"
```

This mattered because `driving_weather` up to 0.4.4 manufactured exactly such a
condition: `WeatherCondition.clear()` hardcoded `temperatureCelsius = 5.0`,
`visibilityMeters = 10000`, `windSpeedKmh = 0.0` and `iceRisk = false`, and
`DigitrafficWeatherProvider` returned it whenever the advisory feed came back
**empty**. An empty feed means "no advisory was published". It does not mean the
road is clear and +5 °C.

So: **if you shipped 0.2.7 or earlier on a Digitraffic-backed feed, a driver may
have been shown a green light — "Conditions normal", full grip — for a road that
was in fact freezing, at the exact moment the feed had nothing to say.** That is
the opposite of what this package exists to do.

pub.dev versions are immutable: we cannot withdraw the affected releases. This
note is the recall.

### Breaking: absence of data can no longer be mistaken for good conditions

- `RoadSurfaceState.fromCondition()` now returns **`RoadSurfaceState?`**. `null`
  means "cannot classify" — it is never `dry`. A benign classification now
  requires knowing BOTH the temperature and the precipitation type.
- `DrivingConditionAssessment.surfaceState` is now `RoadSurfaceState?` and
  **`gripFactor` is now `double?`**. An unknown surface has no grip coefficient;
  inventing one (0.2.7 returned `1.0`) is the same defect class as inventing a
  temperature.
- `DrivingConditionAssessment.visibility` is now `VisibilityDegradation?` and
  `precipitation` is now `PrecipitationConfig?`. `null` is *not*
  `VisibilityDegradation.clear` and *not* `PrecipitationConfig.none` — rendering
  a clear sky over weather nobody measured is the same lie at the render seam.
- `PrecipitationConfig.fromCondition()` now returns `PrecipitationConfig?`
  (`null` when precipitation was not reported; `none` only when the feed
  actually said there is none).
- **New `RecommendedResponse.conditionsUnknown`.** This adds an enum value, so
  exhaustive `switch`es over `RecommendedResponse` will stop compiling. That is
  deliberate and it is disclosed, not hidden: you must decide what your app does
  when the road cannot be assessed.
- `DrivingConditionAssessment.recommendedResponse` **no longer defaults to
  `proceed`** — it is a required parameter. A default of `proceed` meant an
  assessment that said nothing about the road silently claimed the road was fine.
- New `DrivingConditionAssessment.isAssessed`.

The advisory for the unknown tier is:

> Conditions unavailable — no data received; drive to what you can see

That is the compound-failure answer. When the feed is gone, the app SAYS SO
instead of painting "Conditions normal" — her own eyes are the sensor that still
works.

### The asymmetry (why this does not cry wolf)

Absence is reported as **unknown**, never escalated to a hazard. Failing
"safe" by raising an alert on every offline moment would paint black ice
continuously; the driver would learn within one trip that the alert means
nothing, and would then ignore it on the night it was real. Crying wolf is not
honesty — it is a different lie with a safer-sounding name.

Instead:

- **POSITIVE evidence fires on partial data.** An asserted `iceRisk`, deep cold,
  heavy snow, a severe authority assertion, or sub-200 m visibility still warns
  even when every other field is absent. An absent field can never *suppress* a
  warning that a known field already justifies.
- **The NEGATIVE verdict ("proceed") requires complete data.**
- Everything else is `conditionsUnknown`, which the driver is *told* about.

### Migration

| 0.2.7 | 0.3.0 | On `null` / `conditionsUnknown` |
| --- | --- | --- |
| `RoadSurfaceState fromCondition(c)` | `RoadSurfaceState? fromCondition(c)` | Do not substitute `dry`. Surface the unknown state. |
| `assessment.gripFactor` (`double`) | `double?` | Do not substitute `1.0`. |
| `assessment.surfaceState` | `RoadSurfaceState?` | — |
| `assessment.visibility` | `VisibilityDegradation?` | Do not substitute `.clear`. |
| `assessment.precipitation` | `PrecipitationConfig?` | Do not substitute `.none`. |
| `switch (response) { proceed, reduceSpeed, considerTurningBack }` | `+ conditionsUnknown` | Tell the driver the road could not be assessed. |

If you find yourself writing `?? RoadSurfaceState.dry`, `?? 1.0`, or
`?? RecommendedResponse.proceed`, you are re-adding the defect this release
removes.

### What this release does NOT fix

Honesty about the boundary of a fix is part of the fix, and the heading above
("absence of data can no longer be mistaken for good conditions") is an absolute
statement that one path still escapes:

- **An absent HUMIDITY reading still falls through to `dry`.** On the
  radiative-frost path (`road_surface_state.dart`: `precip == none`, `temp >
  -3 °C`, humidity absent), `isRadiativeFrostBlackIce` abstains and the
  classifier reaches `return dry` — so on a humidity-blind feed, an unjudged
  frost morning still reads as confident safety, `gripFactor: 1.0`,
  "Conditions normal". This is the same defect class as the one this release
  removes, on the one input it does not cover.

  It is documented in `KNOWN_LIMITATIONS.md` §4 and recorded as a residual
  performance insufficiency in `SAFETY_BOUNDARY.md` §3. Feed `humidityRH` (the
  Open-Meteo provider supplies it) and the frost classifier will judge the
  morning rather than abstain.

### Also

- A road-authority advisory that carries NO measurements (the Digitraffic /
  CAP shape: an authority declares a situation but measures no temperature, no
  visibility, no wind) now reaches the driver as `reduceSpeed` with
  *"A road advisory is in force; the road itself is not measured — drive to what
  you can see"*, rather than being reported as "no data received". The
  authority's declaration is POSITIVE evidence and fires on partial data, per
  the asymmetry above.
- `"Conditions normal"` is now **unreachable** unless the response tier is
  `proceed`. It was previously the fall-through string for ANY condition no
  branch described — including a severe authority assertion and heavy snow with
  no temperature, both of which correctly produced `reduceSpeed` and then
  printed "Conditions normal" underneath it.
- The `conditionsUnknown` tier has a **Japanese** voice:
  `RecommendedResponse.conditionsUnknown.announcement` →
  「路面状況を取得できていません。見える範囲で運転してください。」 The moment the
  feed dies is exactly the moment an English-only sentence becomes silence, and
  silence on a safety surface reads as "nothing is wrong".
- Requires `driving_weather: ^0.5.0` (the Measured-or-Absent contract).
- Behaviour on **fully measured** data is unchanged — every pre-existing test
  still passes. The break only reaches code paths where data was absent, which
  is precisely where the old behaviour was wrong.

## 0.2.7

- **Precise surface vocabulary on the announcement seam.** New
  `RoadSurfaceAnnouncement` + `RoadSurfaceState.announcement` extension: every
  surface except `dry` (which yields `null` — nothing to announce) provides a
  short spoken-style line (JA + EN) that leads with the precise JP-domestic
  surface term — ブラックアイスバーン for `blackIce`, 圧雪 for
  `compactedSnow`, シャーベット for `slush` — plus, for the snow-vocabulary
  surfaces, the authoritative JAF entry from `japanese_snow_vocabulary`
  (verbatim `safeDrivingResponseJa` for display surfaces; verbatim-relay
  binding). This is package-level capability for consumers composing warning
  surfaces; it does not itself speak or render anything.
- **Certainty is graded, never asserted.** The classifier's black-ice
  determinations are inferences (a feed flag or a dew-point heuristic), so
  composed lines say 凍結しているおそれ ("may be frozen"), mirroring JAF's
  own 可能性 phrasing — never flat certainty.
- **Two black-ice variants, honest about visibility.** The general
  `RoadSurfaceState.blackIce.announcement` is provenance-neutral: it is
  reachable from a feed ice flag during visible snowfall, where claiming the
  road "looks wet" would be false — so it carries neither a looks-wet spoken
  line NOR the JAF vocabulary entry (whose verbatim advisory itself opens
  with the looks-wet description). The separate top-level
  `invisibleBlackIceAnnouncement` carries both — the looks-merely-wet spoken
  fact and the verbatim JAF entry — and is intended ONLY for detection paths
  that imply invisibility (radiative frost, freezing rain). Additive, no
  breaking changes.

## 0.2.6

- **Radiative-frost black ice on the in-drive surface classifier.**
  `RoadSurfaceState.fromCondition` now recognises the no-precipitation,
  above-zero-ambient black-ice window (clear-sky radiative cooling freezing the
  road while the air still reads +1…+3 °C — the Akita pre-dawn bridge-deck
  hazard). Previously this case classified as `dry` / full grip, directly
  contradicting the pre-trip briefing's black-ice warning on the same morning.
  The classifier now calls `navigation_safety_calibration`'s
  `isRadiativeFrostBlackIce` — the SAME function the pre-trip advisor uses, so
  **the two surfaces cannot disagree about the radiative-frost black-ice
  determination when both are given the same temperature + humidity.** (This is
  a scoped guarantee, not an absolute one: the surfaces can still differ on
  other hazard classes, and on any feed that omits humidity the in-drive branch
  abstains — see `KNOWN_LIMITATIONS.md`.) Humidity-gated and caution-add-only:
  needs the new `WeatherCondition.humidityRH`; absent humidity abstains
  (returns `dry`), so this never fabricates a hazard and never downgrades a
  colder classification. Backward-compatible — the new behaviour only activates
  when a `driving_weather ^0.4.4` feed supplies humidity, so consumers on
  `^0.2.x` adopt this with no change. Adds a direct dependency on
  `navigation_safety_calibration ^0.1.3`.
- Known scope (see `KNOWN_LIMITATIONS.md`): the in-drive classifier runs
  all-hours with no wind/time gate, and the primary live feeds (digitraffic,
  KUKSA) do not yet supply humidity — so this fix does not yet change the live
  in-drive screen for those feeds. It is a correct classifier that awaits a
  humidity-bearing live feed + a cry-wolf (wind/time) calibration pass.

## 0.2.5

- Non-breaking restore + honest correction of a mislabeled release. The 0.2.4
  entry below was labeled "(no API change)", but 0.2.4 had in fact shipped a
  **breaking public-API change** relative to 0.2.3: it added the
  `RecommendedResponse` enum, exported it from the package, and added a
  **`required`** `recommendedResponse` parameter to the public const constructor
  of `DrivingConditionAssessment`. The `required` parameter broke any edge
  developer who constructs `DrivingConditionAssessment` directly (the 0.2.3
  call sites no longer compiled).
- This release makes the `recommendedResponse` constructor parameter
  **optional**, defaulting to `RecommendedResponse.proceed` (the neutral,
  lowest-severity "conditions within normal driving tolerance" tier). Direct
  0.2.3-style construction that omits `recommendedResponse` compiles again;
  0.2.4 callers that pass `recommendedResponse` are unaffected. The field stays
  non-nullable, so consumers can always read a concrete tier.
- Documents the public API as it now stands: the `RecommendedResponse` enum,
  the `recommendedResponse` field on `DrivingConditionAssessment` (still part of
  equality/`props`), and the package export of `recommended_response.dart` are
  all supported public API. The `DrivingConditionAssessment.fromCondition`
  factory continues to classify and set `recommendedResponse` explicitly.

## 0.2.4
- docs: correct stale README install pin to current version (no API change).
  NOTE (see 0.2.5): this release was mislabeled — it also shipped a breaking
  API change (a `required` `recommendedResponse` ctor parameter + the
  `RecommendedResponse` enum + its export). 0.2.5 restores source compatibility.

## 0.2.3

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.2.2 — 2026-05-10 — Pana score recovery

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.

## 0.2.1 — 2026-05-10 — Refresh dependency constraint left stale by a sibling release

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- No source changes; pubspec dep-constraint refresh only.

## 0.2.0

- Add `DataBudget` — stateful data-fetch budget tracker for snow-
  overlay render bandwidth management. Integrator-supplied
  `DataMeterProvider` interface; per-cycle bytes budget checked against
  `DataBudgetConfig`; broadcast `budgetEvents` stream emits
  `BudgetWarning` (75%) / `BudgetExhausted` (100%) /
  `RenderFidelityDrop` (in lock-step with Exhausted). Mirrors the
  `GlanceBudgetTracker` pattern from `navigation_safety` 0.9.0
  (caution-add-only / severity-not-profile / driver-always-drives
  invariants enforced via debug-mode runtime asserts).
- Add `DataBudgetConfig.forProfile(DriverProfile)` factory — per-
  cohort tighter-direction defaults (4MB baseline / 3MB `noviceUrban`
  / 2MB `ageingRural` + `foreignTouristSnowZone` for bandwidth-margin).
  Per-cohort budgets are **UNVERIFIED-magnitude design-default-
  hypothesis** pending field-measurement validation; conservative-only
  (every cohort `<=` 4MB baseline). Per-population calibration
  deferred.
- Add `tighten(int)` — auto-tightening allowed at runtime; new budget
  must be `<=` active budget per caution-add-only invariant.
- Add `relax(int, BudgetRelaxConfirmation)` — auto-relax FORBIDDEN;
  loosening requires integrator-supplied affirmative confirmation
  token. Mirrors the cap-override-with-confirmation pattern from
  `navigation_safety_core` 0.10.0 #30 (driver-always-drives).
- Add `BudgetResetReason` enum + `DataFetchEvent` value object +
  sealed `DataBudgetEvent` hierarchy.
- Add `navigation_safety_core: ^0.10.0` dependency for `DriverProfile`
  consumption.
- Add `SAFETY_BOUNDARY.md` (DataBudget invariants; cohort-tighter
  direction caveat; auto-relax-with-confirmation pattern; ASIL-QM
  advisory; severity-not-profile + driver-always-drives preserved).
- Add `KNOWN_LIMITATIONS.md` (per-cohort data-budget UNVERIFIED-
  magnitude flags + bandwidth-class assumptions).
- Public API additions are non-breaking; existing
  `DrivingConditionAssessment` / `RoadSurfaceState` /
  `PrecipitationConfig` / `VisibilityDegradation` contracts unchanged.

## 0.1.0

- Initial extraction from `driving_conditions`.
- `RoadSurfaceState` — six-state road surface classification with grip factors.
- `PrecipitationConfig` — particle configuration derived from weather conditions.
- `VisibilityDegradation` — opacity and blur parameters from visibility distance.
- `DrivingConditionAssessment` — combined assessment with advisory message.
- `HysteresisFilter<T>` — debounce filter for state oscillation at boundary conditions.
