## 0.4.7

- Widen `latlong2` from `^0.9.1` to `>=0.9.1 <0.11.0`.

  `latlong2 0.10.0` shipped 2026-04-25 and `flutter_map 8.x` resolves it, so the old
  ceiling made this package **uninstallable alongside current `flutter_map`** —
  `version solving failed` for every published version. No source change; the cap was
  gratuitous. Verified on `latlong2 0.10.1`: analyze clean, **78/78 tests pass**.

# Changelog

## 0.4.6

Makes the published example resolve. No API or behaviour change: every file
under `lib/` is byte-identical to 0.4.5.

`example/pubspec.yaml` in 0.4.5 and every earlier release carried a
`dependency_overrides:` block naming 28 sibling packages by local filesystem
path (`../../adaptive_reroute`, `../../condition_aggregator`, ...). Those paths
exist only inside our development monorepo. In a published archive they resolve
to nothing, so `dart pub get` in `example/` failed before it could start:

    Because map_viewport_bloc_example depends on voice_guidance from path
    which doesn't exist (could not find package voice_guidance at
    "../../voice_guidance"), version solving failed.

The example never used any of those 28 packages. Its only imports are
`flutter`, `flutter_bloc`, `latlong2` and this package. The block was
development scaffolding that should never have shipped.

The overrides now live in `example/pubspec_overrides.yaml`, which
`example/.pubignore` keeps out of the published archive. Monorepo development
resolves siblings locally exactly as before; the published example now resolves
against pub.dev.

## 0.4.5

Removes build artifacts that 0.4.4 published by mistake. No API or behaviour
change: every file under `lib/` is byte-identical to 0.4.4.

**What 0.4.4 contained, and what you already have.** The 0.4.4 archive was
15,921,716 bytes, of which about 99.9% was a `build/` directory that should
never have been in a published package. It held nine files, the largest a
Flutter kernel cache (`build/test_cache/build/*.cache.dill.track.dill`,
48,823,112 bytes uncompressed) that embedded 1,307 absolute filesystem paths
from the machine that published it, of the form
`/home/<user>/.pub-cache/hosted/pub.dev/<package>-<version>/...`, plus 12
references to the temporary directory the release was staged in.

If you pulled 0.4.4, those bytes are in your pub cache. They disclose the
publishing machine's account name, its pub-cache and staging-directory
locations, and the exact set and versions of the 42 packages resolved there at
build time. We checked for credentials and found none — no private keys, SSH
keys, or API tokens; the payload is a compiler cache and dependency source, not
configuration. Nothing about *consumers* of this package was included, and the
files were inert: no code under `lib/` reads anything in `build/`, so nothing
you ran was affected.

Upgrading to 0.4.5 (in range for any `^0.4.x` constraint) replaces the archive.
Removing `.pub-cache/hosted/pub.dev/map_viewport_bloc-0.4.4/` clears the old
copy. **0.4.4 remains downloadable from pub.dev — published versions are
immutable and cannot be withdrawn**; this release supersedes it, it does not
recall it.

**Cause, and why it should not recur.** `build/` has been ignored by the
repository's root `.gitignore` since 2026-03-04, and `pub publish` honours that
when run from inside the work tree. 0.4.4 was published from a staging copy
*outside* the work tree, where a repo-root `.gitignore` does not apply; pub then
included every file on disk and reported "0 warnings". This release adds a
`.pubignore` to the package itself, so the exclusion travels with the package
directory wherever it is copied or staged. Verified by reproducing the fault:
with `build/` present on disk, the publish dry-run produced 15 MB without the
`.pubignore` and 21 KB with it.

## 0.4.4

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

## 0.4.3
- docs: correct stale README install pin to current version (no API change).

## 0.4.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.1 — 2026-05-10 — Pana score recovery (Theme α P4)

- Trim pubspec `description` to within the pana 60–180 character target.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.4.0

- Add `ViewportRenderBudgetBloc` — composes `PerformanceBudget` (from
  `offline_tiles` 0.5.0) and `DataBudget` (from `snow_rendering`
  0.2.0) streams into a single `ViewportRenderState` with a
  `RenderFidelity` recommendation (`high` / `medium` / `low`).
- **Caution-add-direction-wins on conflict** (load-bearing): any
  `BudgetExhausted` on either stream → fidelity LOW; otherwise any
  `BudgetWarning` → fidelity MEDIUM; else HIGH. The bloc never RAISES
  fidelity in response to a stream event; reset returns to HIGH.
- Add `ViewportRenderConfig.forProfile(DriverProfile)` factory with
  per-cohort `RenderFidelityFloor` (UNVERIFIED-magnitude design-
  default-hypothesis). Cohorts `ageingRural` /
  `foreignTouristSnowZone` / `noviceUrban` get MEDIUM floor (bloc
  never drops to LOW; visual-cognitive-margin demands richer
  rendering). Cohorts `professional` / `snowZoneExperienced` /
  `agriculturalForestry` get LOW floor.
- Add `attachPerformanceBudgetStream` /
  `attachDataBudgetStream` — runtime-typed listener subscription.
- Add `ViewportBudgetReset` event — integrator-driven; returns
  fidelity to HIGH and clears observed-flags.
- Add `navigation_safety_core: ^0.10.0` dependency for `DriverProfile`
  consumption.
- Add `SAFETY_BOUNDARY.md` (viewport-class composition invariants;
  caution-add-direction-wins on conflict; ASIL-QM advisory;
  severity-not-profile + driver-always-drives preserved).
- Add `KNOWN_LIMITATIONS.md` (viewport-class composition strategy
  UNVERIFIED-magnitude; per-cohort `RenderFidelityFloor` design-
  default-hypothesis).
- Public API additions are non-breaking; existing `MapBloc` /
  `MapState` / `MapEvent` / model contracts unchanged.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

