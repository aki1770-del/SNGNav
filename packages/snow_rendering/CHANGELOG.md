# Changelog

## 0.2.10

Additive only — two new public members (`RoadSurfaceState.isInvisibleIceWindow`
and `announcementFor`); no changes to any EXISTING member's API or behavior.
Consumers on `^0.2.x` receive this in range.

### The invisible-window predicate is now public: `RoadSurfaceState.isInvisibleIceWindow(condition)`

To decide between the general black-ice announcement and the invisible-ice
variant (`invisibleBlackIceAnnouncement` — the looks-wet surprise clause plus
the verbatim JAF vocabulary entry), a consumer previously had to re-implement
the radiative-frost gate around `fromCondition()`: pre-check temperature and
precipitation itself, then infer the classification path from the `blackIce`
result. Two independently maintained copies of that window logic are a drift
seam — if the decision tree gains a path or moves a threshold, every call-site
copy silently disagrees with the classifier. The predicate is now exported AND
`fromCondition()`'s radiative branch calls it — one copy of the window logic,
so consumer and classifier cannot drift; the alignment sweeps test-catch any
future decoupling in both directions.

Semantics, stated honestly: it describes the MEASURED radiative-frost window
(no precipitation falling, ambient in (−3, +3] °C — +3 °C is the calibration
ambient ceiling, inclusive — and the calibration dew-point test fires),
independent of the feed's `iceRisk` flag; cold-dry (≤ −3 °C) and freezing rain
return `false` (expected-frozen regime / precipitation falling); absent or
non-finite inputs abstain (`false`) — the window is never fabricated from
unmeasured fields. Tested alignment guarantee, both directions: predicate
`true` ⇒ `fromCondition()` classifies `blackIce` for the same condition, and a
radiative-branch `blackIce` classification (no `iceRisk` flag, no
precipitation, ambient > −3 °C) ⇒ predicate `true`.

### New `announcementFor(condition)` — announcement selection with provenance

**Why (the safety reason this release exists):** the two-step chain
`fromCondition(condition).announcement` loses provenance — an enum value
cannot carry HOW it was reached — so on the invisible radiative-frost morning
it yields the general (weaker) black-ice announcement: no
「路面は濡れて見えても」 looks-wet clause, no JAF vocabulary entry.
Under-warning on the invisible morning is the exact failure class this
package exists to prevent. `announcementFor(condition)` classifies and
selects in one step: when the invisible window holds it returns
`invisibleBlackIceAnnouncement`; every other classification returns that
state's general announcement (`null` for `dry`). The feed ice flag during
visible precipitation stays on the general variant — the looks-wet claim is
not established when snow is falling on the road. Freezing rain also stays
general, for a different, deliberate reason: freezing rain IS invisible-ice
phenomenology (glare ice looks merely wet), but the classifier's rain-at-≤0 °C
branch cannot distinguish a true freezing-rain event from a marginal or
erroneous temperature reading during cold rain, so the strong looks-wet claim
is withheld on that path.

Relative to the two-step chain this only ever UPGRADES a black-ice
announcement to the invisible-ice variant; it never changes which surface is
classified and never weakens any announcement.

Existing code keeps compiling and behaving identically; adopting the new
function (or the predicate) is opt-in.

## 0.2.9

### Safety notice for every 0.2.x consumer — please read

**`RoadSurfaceState.fromCondition()` in this line cannot say "I don't know" —
and a `WeatherCondition` built from filler values will classify as `dry`
(gripFactor 1.0, "Conditions normal").**

The 0.2.x line depends on `driving_weather` 0.4.x, whose `WeatherCondition`
has REQUIRED non-nullable fields (`temperatureCelsius`, `precipType`,
`visibilityMeters`). Absence of a measurement cannot be represented in the
type: if you have no reading, the constructor forces you to invent one, and
the classifier cannot tell an invented +5 degC from a measured one. The chain

```
no data -> filler values -> RoadSurfaceState.dry -> gripFactor 1.0
        -> "Conditions normal", shown for a road nobody measured
```

is exactly what a driver in unexpected snow must never see.

**What to do in this line (0.2.x):** never construct a `WeatherCondition`
from unmeasured fields. Gate at the call site — if any input you would pass
is absent, do not call `fromCondition()`; surface "unknown" to your user
yourself. (`driving_weather` 0.4.5 already stopped its provider
manufacturing a clear-sky condition on an empty feed; this notice covers
conditions YOUR code constructs.)

**The real fix is 0.3.0**: `fromCondition()` returns `RoadSurfaceState?`
where `null` means "cannot classify — and that is a thing the driver is
told", on `driving_weather` 0.5.0's nullable measurement fields. Upgrading
is a breaking change (nullable return; nullable condition fields) and worth
it: the compiler then forces every caller to handle the unknown case.

This release changes NO code — it is documentation only, so it arrives to
every `^0.2.0` consumer without altering behavior.

## 0.2.8

Widens the `navigation_safety_core` constraint to `>=0.10.0 <0.12.0`.

The previous `^0.10.0` constraint excluded core 0.11.x, so a project that asked
for the current core could not also take this package at its current version.
The resolver silently selected an older release of this package instead, with no
error and no warning. Core 0.11.0 and 0.11.1 are additive (a re-export, and a
percent-to-fraction humidity factory); this package compiles and its full test
suite passes against 0.11.1.

Also removes a `dependency_overrides` block that referenced sibling packages by
relative path. It was inert for consumers, but it prevented this package from
resolving standalone from its published archive.

No API or behaviour change.

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
