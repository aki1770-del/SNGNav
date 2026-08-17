# Changelog

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

## 0.2.2 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.

## 0.2.1 — 2026-05-10 — Refresh cascade-stale dependency constraint

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

- Initial extraction from `driving_conditions` (SNGNav P1, D-SC22-2).
- `RoadSurfaceState` — six-state road surface classification with grip factors.
- `PrecipitationConfig` — particle configuration derived from weather conditions.
- `VisibilityDegradation` — opacity and blur parameters from visibility distance.
- `DrivingConditionAssessment` — combined assessment with advisory message.
- `HysteresisFilter<T>` — debounce filter for state oscillation at boundary conditions.
