# Changelog

## 0.5.6

Makes the published example resolve. No API or behaviour change: every file
under `lib/` is byte-identical to 0.5.5.

`example/pubspec.yaml` in 0.5.5 and every earlier release carried a
`dependency_overrides:` block naming 28 sibling packages by local filesystem
path (`../../adaptive_reroute`, `../../condition_aggregator`, ...). Those paths
exist only inside our development monorepo. In a published archive they resolve
to nothing, so `dart pub get` in `example/` failed before it could start:

    Because offline_tiles_example depends on voice_guidance from path
    which doesn't exist (could not find package voice_guidance at
    "../../voice_guidance"), version solving failed.

The example never used any of those 28 packages. Its only imports are
`flutter`, `flutter_map`, `latlong2` and this package. The block was
development scaffolding that should never have shipped.

The overrides now live in `example/pubspec_overrides.yaml`, which
`example/.pubignore` keeps out of the published archive. Monorepo development
resolves siblings locally exactly as before; the published example now resolves
against pub.dev.

## Unreleased (rides the next republish — the core ^0.11 wave)
- docs: Android SQLite native-library trap section — `sqlite3_flutter_libs`
  0.6.0+eol is a no-op; pin 0.5.x until a hooks-delivered `.so` is
  device-verified; the failure mode is a silent blank offline map with green
  host tests (production-found 2026-07-10). Verification recipe: airplane
  mode BEFORE launch, SEE the bundled region paint.

## 0.5.5

Removes build artifacts that 0.5.4 published by mistake. No API or behaviour
change: every file under `lib/` is byte-identical to 0.5.4.

**What 0.5.4 contained, and what you already have.** The 0.5.4 archive was
17,460,090 bytes, of which about 99.9% was a `build/` directory that should
never have been in a published package. It held eleven files, the largest a
Flutter kernel cache (`build/test_cache/build/*.cache.dill.track.dill`,
50,460,280 bytes uncompressed) that embedded 1,440 absolute filesystem paths
from the machine that published it, of the form
`/home/<user>/.pub-cache/hosted/pub.dev/<package>-<version>/...`, plus 17
references to the temporary directory the release was staged in.

It also carried `build/native_assets/linux/libsqlite3.so` (1,801,600 bytes) —
host-built ELF x86-64 output from the Flutter native-assets step, referenced by
an absolute path inside that same temporary staging directory. **Removing it
breaks nothing**: nothing under `lib/` references any `.so`, and your platform's
sqlite3 native library comes from the declared `sqlite3` dependency, not from
this archive. A Linux-x64 binary was never usable by an Android or arm64
consumer in any case.

If you pulled 0.5.4, those bytes are in your pub cache. They disclose the
publishing machine's account name, its pub-cache and staging-directory
locations, and the exact set and versions of the 47 packages resolved there at
build time. We checked for credentials and found none — no private keys, SSH
keys, or API tokens; the payload is a compiler cache, a stock sqlite3 build, and
dependency source, not configuration. Nothing about *consumers* of this package
was included, and the files were inert: no code under `lib/` reads anything in
`build/`, so nothing you ran was affected.

Upgrading to 0.5.5 (in range for any `^0.5.x` constraint) replaces the archive.
Removing `.pub-cache/hosted/pub.dev/offline_tiles-0.5.4/` clears the old copy.
**0.5.4 remains downloadable from pub.dev — published versions are immutable and
cannot be withdrawn**; this release supersedes it, it does not recall it.

**Cause, and why it should not recur.** `build/` has been ignored by the
repository's root `.gitignore` since 2026-03-04, and `pub publish` honours that
when run from inside the work tree. 0.5.4 was published from a staging copy
*outside* the work tree, where a repo-root `.gitignore` does not apply; pub then
included every file on disk and reported "0 warnings". This release adds a
`.pubignore` to the package itself, so the exclusion travels with the package
directory wherever it is copied or staged. Verified by reproducing the fault:
with `build/` present on disk, the publish dry-run produced 16 MB without the
`.pubignore` and 25 KB with it.

## 0.5.4

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

## 0.5.3
- docs: correct stale README install pin to current version (no API change).

## 0.5.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.5.1 — 2026-05-10 — Pana score recovery (Theme α P4)

- Trim pubspec `description` to within the pana 60–180 character target.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.5.0

- Add `PerformanceBudget` — stateful frame-timing budget tracker for
  tile-render advisory cognitive-load management. Integrator-supplied
  `FrameTimingProvider` interface; per-frame budget checked against
  `PerformanceBudgetConfig`; broadcast `budgetEvents` stream emits
  `BudgetWarning` (75% sustained) / `BudgetExhausted` (100% sustained
  over `sustainedFrames` consecutive frames). Mirrors the
  `GlanceBudgetTracker` pattern from `navigation_safety` 0.9.0
  (caution-add-only / severity-not-profile / driver-always-drives
  invariants enforced via debug-mode runtime asserts).
- Add `PerformanceBudgetConfig.forProfile(DriverProfile)` factory — per-
  cohort lenient-direction defaults (16ms baseline / 18ms
  `noviceUrban` / 22ms `ageingRural` + `foreignTouristSnowZone` for
  visual-cognitive-margin). Per-cohort budgets are
  **UNVERIFIED-magnitude design-default-hypothesis** pending field-
  measurement validation; conservative-only (every cohort `>=` 16ms
  baseline). Per-population calibration deferred.
- Add `BudgetResetReason` enum — render-cycle / long-pause / explicit.
- Add `navigation_safety_core: ^0.10.0` dependency for `DriverProfile`
  consumption. Add `equatable: ^2.0.7` (used by sealed event classes).
- Add `SAFETY_BOUNDARY.md` (driving-automation-regime declaration;
  PerformanceBudget invariants; ASIL-QM advisory; severity-not-profile
  + driver-always-drives preserved).
- Add `KNOWN_LIMITATIONS.md` (per-cohort budget UNVERIFIED-magnitude
  flags + integrator-side FrameTimingProvider supply-chain caveats).
- Public API additions are non-breaking; existing
  `OfflineTileManager` / providers / resolvers contracts unchanged.

## 0.4.0

- Migrate to `mbtiles ^0.5.0` and `sqlite3 ^3.2.0` (native assets).
- Remove EOL `sqflite` dependency.
- Remove unused `flutter_map_mbtiles` phantom dependency.
- Internal API update: `MbTiles(path:)`, `MbTiles.create(path:)`, `close()` replacing `dispose()`.
- Public API unchanged: `OfflineTileManager(mbtilesPath:)` contract preserved.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

