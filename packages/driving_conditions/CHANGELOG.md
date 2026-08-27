# Changelog

## 0.6.1

### The 0.6.0 recall was handed back through three default constructor arguments

0.6.0 removed the fabricated fleet term from the MODEL. It did not remove it
from the CONSTRUCTORS. Three default arguments still read:

```dart
// 0.6.0 — cpu_safety_score_simulation_engine.dart:38
//         safety_score_simulator.dart:29
//         native_safety_score_simulation_engine.dart:29
FleetConfidenceProvider provider = const ConstantFleetConfidenceProvider(),
//                                                                    ^ value defaults to 0.8
```

So a consumer who wired **no fleet source at all** received
`fleetConfidenceScore == 0.8`, `hasFleetData == true`, and a `toString()`
printing `fleet: 0.80` where a real absence prints `fleet: not measured`. The
honest-absence flag this package introduced was made to report a fleet that had
never spoken. `FleetHazardConfidenceAdapter([]).confidence` was correctly
`null` the whole time — the defect was that nothing reached it unless you asked.

**Fixed**: those three defaults are now
`const ConstantFleetConfidenceProvider.unavailable()`. No signature changed, so
this ships in range for `^0.6.0`.

`ConstantFleetConfidenceProvider(0.8)` is unchanged and still means exactly what
it always honestly meant: a caller **asserting** a fleet confidence — a fixture,
a scenario, a simulator input. Only the DEFAULT changed. Asserting a scenario is
honest; laundering an absence into an assertion is not.

### What it cost the driver — measured, not asserted

Swept 22,932 input points (speed 0–130 km/h x gripFactor 0.00–1.00 x visibility
0–1000 m x 3 seeds, 48 Monte Carlo runs each), comparing the shipped default
against the honest absence at each of the six `DriverProfile` threshold sets.

The defaulted 0.8 **raised** the overall score at 97.48% of points and lowered
it at 2.52%; it was never identical.

| `DriverProfile` floors (safe/info/warn) | severity changed | -> LESS severe | -> MORE severe |
|---|---:|---:|---:|
| 0.80 / 0.50 / 0.30 (default; `snowZoneExperienced`, `professional`, `agriculturalForestry`) | 30.32% | 100.00% | 0.00% |
| 0.85 / 0.55 / 0.35 (`ageingRural`) | 28.76% | 99.12% | 0.88% |
| 0.85 / 0.55 / 0.32 (`noviceUrban`) | 27.83% | 99.09% | 0.91% |
| 0.90 / 0.60 / 0.40 (`foreignTouristSnowZone`) | 25.58% | 99.47% | 0.53% |

At the default floors, **15.38% of the whole grid moved `critical` to
`warning`** and 14.95% moved `warning` to `info`.

**The counter-direction cases are real and are named here rather than rounded
away.** In three of the six profiles a small share of points moved the other
way. Every one of them is the same shape — `none` -> `info`, in the region where
the honest score is already 0.85-0.92 — because an asserted 0.8 drags a
*better-than-0.8* score down. **In no profile, at any point in the grid, did the
defaulted term ever produce a `warning` or a `critical` that honesty would not.**
The defect only ever removed warnings; it never added one.

A worked case, black ice / 300 m visibility / 40 km/h, standard floors:

| | overall | severity | rendered |
|---|---:|---|---|
| honest (0.6.1) | 0.207 | `critical` | `fleet: not measured` |
| defaulted (0.6.0) | 0.326 | `warning` | `fleet: 0.80` |

She was told to reduce speed where the measured terms alone say turn back, on
the strength of a fleet that reported nothing.

### The default changed — three shipped tests changed with it

This was deliberate back-compatibility in 0.6.0, not an oversight, so the tests
that pinned it were **re-authored to assert the honest behaviour, not deleted**:

- `safety_score_simulator_test.dart` — `expect(score.fleetConfidenceScore, 0.8)`
  is now `isNull` + `hasFleetData` `isFalse`; a new case asserts that an
  explicitly asserted `0.8` is still honoured.
- `safety_score_simulator_test.dart` — `closeTo(0.8, 1e-9)` on the default run
  count is now `isNull`.
- `simulation_engine_test.dart` — the default simulator's
  `closeTo(0.8, 1e-9)` is now `isNull` + `hasFleetData` `isFalse`.

A **fourth** test also depended on the default and was not in the original
finding: `fleet_confidence_provider_test.dart`'s *"simulator with icy adapter
produces lower score than constant 0.8"* used a bare `const
SafetyScoreSimulator()` as its "constant 0.8" comparand. It now passes
`ConstantFleetConfidenceProvider(0.8)` explicitly, which is what the test's own
name always claimed it was doing.

New guard: `test/simulation/default_provider_absence_test.dart`. Five of its
seven cases fail against 0.6.0's defaults (verified by reverting the fix); the
two that pass are the ones asserting behaviour that correctly did not change.

### Behaviour change worth knowing: the native engine's default path

`NativeSafetyScoreSimulationEngine()` **constructed with no provider now takes
the CPU path and never enters the FFI kernel**, so `SimulationResult.executionMs`
is `null`. The native kernel's weighted mean takes a non-nullable fleet term and
cannot express an absent one, so it is skipped rather than fed a number nobody
measured. Correctness before throughput. Pass a provider that returns a value to
reach the kernel; the FFI parity test now does exactly that.

### Documentation that taught the defect

- `constant_fleet_confidence_provider.dart` said *"Use it when no fleet data is
  available"* — the precise wrong instruction, and it contradicted the same
  file's own constructor doc. It now says: use it to ASSERT a value; use
  `.unavailable()` for no fleet data.
- `fleet_confidence_provider.dart` documented the default as
  `ConstantFleetConfidenceProvider` (0.8).
- `fleet_hazard_confidence_adapter.dart` still documented `unknown -> 0.8` and
  *"returns 0.8 — the neutral baseline"* **against its own corrected code**,
  which has returned `null` on all three absence paths since 0.6.0.
- `README.md` shipped the pre-0.6.0 non-renormalised `overall` formula and an
  API table describing the 0.8 default.
- `SAFETY_BOUNDARY.md` claimed *"a consumer cannot render a fleet number that
  does not exist"*, which was false while the defaults stood. The residual
  insufficiency is now recorded there and marked closed in 0.6.1.
- `example/main.dart` framed a bare `const SafetyScoreSimulator()` as
  *"constant 0.8 — an ASSERTED value"*. It was not asserted; it was defaulted.

### Also fixed, found while correcting the above

- **`example/main.dart` did not compile.** `fleet_hazard` 0.6.0 made
  `FleetReport.confidence` **required** — removing its own defaulted `0.8` for
  exactly the reason this package removed its — and this package's constraint
  (`fleet_hazard: '>=0.5.0 <0.8.0'`) admits it. The shipped example therefore
  failed to analyze against any in-range `fleet_hazard >= 0.6.0`, and
  `dart analyze` was red on 0.6.0 with 2 errors. Both call sites now state
  `confidence` explicitly. `dart analyze` is clean.
- **`NativeSimulationBindings.runBatch` had `double fleetConfidence = 0.8`** —
  the same laundering one level lower. It is unreachable today (the class is not
  exported, and its only call site always passes the value), so this changes no
  behaviour; the parameter is now `required` so the defect cannot re-enter
  through it.

### Reach — this fix does not arrive on its own

`vehicle_condition_fusion` 0.3.4, the only published dependent, pins
`driving_conditions: ^0.5.2` and cannot resolve 0.6.x at all. Publishing 0.6.1
does not deliver it to that consumer. Reach is tracked separately; this entry
does not claim delivery.

## 0.6.0

### Safety defect in 0.5.4 and earlier — please read

This package **re-exports** `RoadSurfaceState`, `HysteresisFilter` and
`DrivingConditionAssessment` from `snow_rendering`. It therefore carried
`snow_rendering`'s fabrication defect verbatim to its own consumers:

**up to 0.5.4, a road with no weather data classified as `RoadSurfaceState.dry`,
with `gripFactor: 1.0` and the advisory "Conditions normal".** Absence of data
became maximum grip and a green light. See `snow_rendering` 0.3.0 and
`driving_weather` 0.5.0 for the full account.

pub.dev versions are immutable. This note is the recall.

### Second safety defect in 0.5.4 and earlier — fleet SILENCE raised the score

`FleetHazardConfidenceAdapter.confidence` returned **`0.8`** — called a "neutral
baseline" — in three different absence cases:

```dart
// fleet_hazard_confidence_adapter.dart, 0.5.4
static const double _neutralBaseline = 0.8;
if (recent.isEmpty) return _neutralBaseline;      // no recent report at all
if (totalWeight == 0.0) return _neutralBaseline;  // no usable report
RoadCondition.unknown => _neutralBaseline,        // a driver reporting "I don't know"
```

`0.8` is **not neutral**. On the same scale `dry` scores 1.0 and `snowy` 0.4 — so
0.8 is an OPTIMISTIC report from a fleet that reported nothing. And it was not a
display value: it was folded into the overall safety score with weight 0.2

```dart
final overall = gripScore * 0.4 + visibilityScore * 0.4 + fleetConfidenceScore * 0.2;
```

**so silence from the fleet RAISED the computed safety score.** A driver on an
icy road with no fleet data got a *higher* score than the measured terms
justified. The boundary record even certified the default as "honest (0.8
explicit baseline; not hidden)" — the number was explicit; what it MEANT was not.

**0.6.0**: `FleetConfidenceProvider.confidence` is `double?` (`null` = no fleet
data). An explicitly-`unknown` road report carries **no weight** rather than a
grip-like 0.8. And the overall score RE-NORMALISES its weights over the terms
that were actually measured, so an absent term is not folded in at any value —
fleet silence now neither raises nor lowers the score.

`ConstantFleetConfidenceProvider(0.8)` survives as what it always honestly was: a
caller ASSERTING a scenario (a test, a simulator) — the exact counterpart of
`WeatherCondition.simulatedClear()`. To say "no fleet data", use
`ConstantFleetConfidenceProvider.unavailable()`.

### Breaking

- Requires `snow_rendering: ^0.3.0` and `driving_weather: ^0.5.0`.
  The re-exported types changed, so **this package's own public API changed**:
  - `RoadSurfaceState.fromCondition()` now returns `RoadSurfaceState?`
    (`null` = cannot classify; it is never `dry`).
  - `DrivingConditionAssessment.surfaceState` is `RoadSurfaceState?`,
    `gripFactor` is `double?`, `visibility` is `VisibilityDegradation?`,
    `precipitation` is `PrecipitationConfig?`.
  - `RecommendedResponse` gains `conditionsUnknown`, breaking exhaustive
    switches.
  - `DrivingConditionAssessment.recommendedResponse` no longer defaults to
    `proceed`.

  Note that the old `driving_weather: ^0.4.0` constraint could not simply be
  left alone: `snow_rendering` 0.3.0 requires `driving_weather` `^0.5.0`, and
  for a `0.x` package `^0.4.0` does not admit `0.5.0`. Left unbumped, this
  package would have made resolution **impossible** for everyone downstream.

- **`SafetyScoreSimulator.simulate()` still takes a non-nullable
  `double gripFactor` and a non-nullable `RoadSurfaceState surface`** — so an
  unknown road can no longer be scored at all, and the compiler will stop you at
  the call site. This is deliberate. A Monte Carlo safety score computed on a
  fabricated grip of 1.0 is worse than no score: it is a confident number about
  a road nobody looked at. Guard, and tell the driver the road is unassessed:

  ```dart
  final surface = assessment.surfaceState;
  final grip = assessment.gripFactor;
  if (surface == null || grip == null) {
    // Do NOT write `?? RoadSurfaceState.dry` or `?? 1.0` — that is the defect.
    show(assessment.advisoryMessage); // "Conditions unavailable — ..."
    return;
  }
  final result = const SafetyScoreSimulator()
      .simulate(speed: 50, gripFactor: grip, surface: surface, /* ... */);
  ```

### Breaking: the simulation score is now `SimulatedSafetyScore`

`SimulationResult.score` and `SafetyScoreSimulator.runOnce` return
**`SimulatedSafetyScore`** (this package) instead of `SafetyScore`
(`navigation_safety_core`).

Why: `SafetyScore.fleetConfidenceScore` is a non-nullable `double`, so it
**cannot say "no fleet reported anything"** — which is exactly how the `0.8`
fabrication got in. `SimulatedSafetyScore.fleetConfidenceScore` is `double?`, and
its `overall` is re-normalised over the measured terms. `toAlertSeverity(config)`
is unchanged and applies the same thresholds to `overall`. `hasFleetData` tells
you which case you are in.

`navigation_safety_core` is **not** bumped: nothing outside this package
constructs or reads that type, and forcing a core release would strand
`nav2_safety_layer`, whose constraint was only just widened. The honest fix is
contained here, where the defect is.

### Fixed: `RecommendedResponse` was never re-exported

Up to 0.5.4 this package re-exported `DrivingConditionAssessment` but **not the
type of its `recommendedResponse` field**. A consumer importing only
`package:driving_conditions` could hold the value but could not name the type,
and so could not `switch` on it.

That was a latent facade gap; 0.6.0 makes it load-bearing, because
`RecommendedResponse.conditionsUnknown` is precisely the tier a consumer must
handle in order not to treat an unassessed road as a clear one. A contract the
consumer cannot name is a contract that does not reach them. Now exported.

### Also

- **`navigation_safety_core` is `>=0.10.0 <0.12.0`, not `^0.10.0`.** The
  published 0.5.5 (2026-07-12) already widened this to admit the 0.11.x line;
  that widening lived only in the published artifact and never came back to this
  repository, so the tree still carried the pre-0.5.5 `^0.10.0`. Shipped as-is,
  0.6.0 would have been the only package in this catalog to *exclude*
  `navigation_safety_core` 0.11.0–0.11.4 — narrower than the 0.5.7 it replaces,
  and narrower than the six siblings (`snow_rendering`, `offline_tiles`,
  `map_viewport_bloc`, `voice_guidance`, `navigation_safety`,
  `nav2_safety_layer`) that all declare `>=0.10.0 <0.12.0`. An upgrade that
  *removes* resolvable versions is a downgrade for the integrator holding both.
  Nothing in 0.11.x required the narrowing: 0.11.0 and 0.11.1 record themselves
  as additive (0.11.0 *adds* re-exports; no existing symbol changed or was
  removed) and 0.11.2, 0.11.3 and 0.11.4 each record "no API changes". Read as
  a claim that needed checking rather than a promise: this package's suite is
  green on both ends of the range — 0.10.5 and 0.11.4 — from a hosted,
  override-free resolution carrying no path dependency.

- Behaviour on **fully measured** data is unchanged — all pre-existing tests
  still pass. The break reaches only the code paths where data was absent, which
  is exactly where the old behaviour was wrong.

## 0.5.7

Fixes a fleet report whose own confidence is NaN or infinite being reported as
`1.0` — "fleet reports consistently safe conditions". Behaviour change on that
one path only. Every finite path is byte-for-byte the same answer as 0.5.6.

**What you already have, if you pulled any release from 0.5.0 to 0.5.6.**
`FleetHazardConfidenceAdapter.confidence` ended with
`(total / totalWeight).clamp(0.0, 1.0)`. Dart's `num.clamp` maps NaN to the
*upper* bound: measured on the Dart VM, `double.nan.clamp(0.0, 1.0)` is `1.0`,
and that result's `.isFinite` is `true`. `FleetReport.confidence` is a plain
`double` with no finiteness constraint, so a single report carrying NaN or
`Infinity` — from a division by zero upstream, a bad parse, an uninitialised
sensor — poisons the weighted average, and the adapter answered `1.0`.

Measured, on the published 0.5.6 archive:

| Recent reports | 0.5.6 answered | 0.5.7 answers |
|---|---|---|
| one ICY report, `confidence: NaN` | `1.0` | `NaN` |
| one ICY report, `confidence: Infinity` | `1.0` | `NaN` |
| one ICY report, `confidence: -Infinity` | `1.0` | `NaN` |
| four honest ICY reports plus one NaN | `1.0` | `NaN` |
| anything finite | unchanged | unchanged |

The last row of that table is the one worth pausing on: four vehicles reporting
ice, and one malformed report, produced maximum confidence that the road was
safe.

**Why it also mattered downstream.** `navigation_safety_core` deliberately maps
a non-finite score to `0` — the worst case — so that an uncertain score
*alerts* rather than passing silently (`safety_score.dart`, the
conservative-on-uncertain invariant). That guard can only fire on a value that
is still non-finite when it arrives. By clamping first, this package converted
the non-finite value into a finite, maximal one and the guard never ran. A
sanitiser here was disarming a safety guard there. Verified end to end: with
the 0.5.6 adapter, a NaN-confidence ICY report yields
`SafetyScore.fleetConfidenceScore == 1.0`; with 0.5.7 the same input yields
`0.0`, and a 50-run `CpuSafetyScoreSimulationEngine` simulation goes from 0
incidents and an overall of 0.877 to 50 incidents and an overall of 0.0.

**What changed in the code.** One branch, before the clamp:

```dart
final average = total / totalWeight;
if (!average.isFinite) return average; // do not clamp; see below
return average.clamp(0.0, 1.0);
```

A non-finite return asserts nothing in either direction — every comparison
against NaN is false — so a consumer that does not handle it makes no claim
about the road either way. Only a consumer that has opted into
conservative-on-uncertain turns it into an alert. That decision belongs to the
consumer, not to this adapter.

**What did NOT change.** The `0.8` neutral baseline for absent, stale or
zero-weight fleet data is untouched, and so is every condition factor. No
public API signature changed. If your fleet data has always been finite, this
release is a no-op for you.

**What to check if you display the value directly.** `confidence` may now be
`NaN` where 0.5.6 gave you `1.0`. `NaN.toStringAsFixed(2)` renders `"NaN"`, and
every `<` or `>` comparison against it is false. If you format or threshold
this value for a driver, handle `!value.isFinite` explicitly and decide what it
should mean in your UI — it means "we could not read the fleet evidence", not
"safe" and not "dangerous". Guarding it is a two-line change; leaving it
unguarded is safer than 0.5.6 was, because a naive comparison now makes no
claim instead of the wrong one.

## 0.5.6

Removes build artifacts that 0.5.5 published by mistake. No API or behaviour
change: every file under `lib/` is byte-identical to 0.5.5.

**What 0.5.5 contained, and what you already have.** The 0.5.5 archive was
2,133,126 bytes, of which about 99% was a `build/` directory that should never
have been in a published package. It held eight files, the largest a Flutter
kernel cache (`build/test_cache/build/*.cache.dill.track.dill`, 5.7 MB
uncompressed) that embedded 465 absolute filesystem paths from the machine that
published it, all of the form
`/home/<user>/.pub-cache/hosted/pub.dev/<package>-<version>/...`.

If you pulled 0.5.5, those bytes are in your pub cache. They disclose the
publishing machine's account name and pub-cache location, and the exact set and
versions of the 37 packages resolved there at build time. We checked for
credentials and found none — no private keys, SSH keys, or API tokens; the
payload is a compiler cache and dependency source, not configuration. Nothing
about *consumers* of this package was included, and the files were inert: no
code under `lib/` reads anything in `build/`, so nothing you ran was affected.

Upgrading to 0.5.6 (in range for any `^0.5.x` constraint) replaces the archive.
Removing `.pub-cache/hosted/pub.dev/driving_conditions-0.5.5/` clears the old
copy.

**Cause, and why it should not recur.** `build/` has been ignored by the
repository's root `.gitignore` since 2026-03-04, and `dart pub publish` honours
that when run from inside the work tree. 0.5.5 was published from a staging copy
*outside* the work tree, where a repo-root `.gitignore` does not apply; pub then
included every file on disk and reported "0 warnings". This release adds a
`.pubignore` to the package itself, so the exclusion travels with the package
directory wherever it is copied or staged. Verified by reproducing the fault:
with `build/` present on disk, the publish dry-run produced 2 MB without the
`.pubignore` and 24 KB with it.

## 0.5.5

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

# Changelog

## 0.5.4

- deps: allow `fleet_hazard: ^0.4.0` → `^0.5.0` (the anonymized-`HazardZone`
  dignity fix). `driving_conditions` consumes only the `FleetReport` input atom
  and the `RoadCondition` enum via `FleetHazardConfidenceAdapter` — neither
  changed in fleet_hazard 0.5.0 (only the *retained* `HazardZone.reports` type
  was anonymized from `List<FleetReport>` to `List<ZoneObservation>`, which this
  package never reads). Source-compatible; no `lib/` code change. Unblocks
  integrators that pull both packages from pub.dev.

## 0.5.3

- Docs: de-promote the optional native (C FFI) `NativeSafetyScoreSimulationEngine`. The README now states the pure-Dart `CpuSafetyScoreSimulationEngine` is the default, and that the native path requires compiling the C library (`native/build/lib...`) first — it throws (`DynamicLibrary.open` / `UnsupportedError`) otherwise, with no silent fallback. Updated the README install snippet pin to `^0.5.3`. No code change.

## 0.5.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.5.1 — 2026-05-10 — Refresh cascade-stale dependency constraints

- `driving_weather: ^0.3.0` → `^0.4.0` (consumer-side refresh after
  driving_weather 0.4.0 release earlier the same day).
- `fleet_hazard: ^0.3.0` → `^0.4.0`.
- No source changes; pubspec dep-constraint refresh only.

## 0.5.0

- **Dep modernization** (republish cascade): bump `navigation_safety_core: ^0.1.0 → ^0.10.0` (closes 9-version stale dep) + `snow_rendering: ^0.1.0 → ^0.2.0` (closes 1-version stale dep). NSC dep update consumes additive surface only (no breaking changes per NSC CHANGELOG 0.2.0–0.10.0). Closes 2-month publish-debt (pub.dev last at 0.3.0 from 2026-03-15).
- **New**: `FleetConfidenceProvider` abstract interface — pluggable fleet confidence for safety simulation.
- **New**: `ConstantFleetConfidenceProvider` — explicit named replacement for the `0.8` literal.
- **New**: `FleetHazardConfidenceAdapter` — derives confidence from `List<FleetReport>` using road condition safety factors (dry 1.0, wet 0.7, snowy 0.4, icy 0.1).
- `CpuSafetyScoreSimulationEngine`, `NativeSafetyScoreSimulationEngine`, and `SafetyScoreSimulator` now accept an optional `FleetConfidenceProvider`. Default behaviour is unchanged (0.8 constant).
- Native `simulation_run_batch` C function now accepts `fleet_confidence` as a parameter. Shared library rebuilt.
- Adds `fleet_hazard: ^0.3.0` as a dependency.

## 0.4.0

> ⚑ **NEVER PUBLISHED.** Measured against the pub.dev API on 2026-08-28: the
> published version list is `0.1.0, 0.1.1, 0.2.0, 0.3.0, 0.5.0 … 0.5.7, 0.6.0`.
> `0.4.0` is not on it and never was. The entry is kept rather than deleted
> because the work below is real; a reader looking for `0.4.0` on pub.dev will
> not find it, and should read this section as part of `0.5.0`.

- **Refactor**: drop direct `navigation_safety` package dependency; consume `navigation_safety_core` (pure-Dart core) only. Tracks the NSC pure-Dart core extraction (commit `86632c4`); driving_conditions only uses the core safety vocabulary types and never required the Flutter+BLoC surface.
- **Breaking**: `SafetyScoreSimulator.simulate()` and `SafetyScoreSimulationEngine.simulate()` now return `SimulationResult` instead of `SafetyScore`.
- **New type**: `SimulationResult` — wraps the mean `SafetyScore` with statistical measures: `variance`, `incidentCount`, and (native engine only) `executionMs`.
- **Promoted**: `NativeSafetyScoreSimulationEngine` is now part of the public API. Edge developers can instantiate it directly to access native-engine execution timing.
- `CpuSafetyScoreSimulationEngine.simulate()` now computes and exposes `variance` and `incidentCount` from the Monte Carlo runs.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

## 0.2.0

- Added comprehensive dartdoc coverage for native simulation APIs and model quality fields.
- Fixed `dart doc` warnings so documentation builds cleanly.
- Added edge-case coverage for road-surface thresholds, hysteresis behavior, and visibility degradation.

## 0.1.1

- Add explicit Install section and API Overview table to README.
- Refresh README validation and license metadata for republish.

## 0.1.0

- Initial release.
- `RoadSurfaceState` — 6 road surface classifications with decision tree and hysteresis filter.
- `PrecipitationConfig` — particle visual parameters derived from weather conditions.
- `VisibilityDegradation` — opacity and blur sigma from visibility distance.
- `DrivingConditionAssessment` — composite assessment from weather conditions.
- `SafetyScoreSimulator` — Monte Carlo safety score simulation scaffold.
