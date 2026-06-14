# Changelog

## 0.1.3 — 2026-06-14 — add HapticCuePattern (accessibility / tactile hazard channel)

Adds a fifth pure-enum domain type plus its pure severity-mapping
function, for the tactile (haptic) hazard channel that carries a
hazard warning to a deaf / hard-of-hearing driver — or to HER in a
roaring-wind whiteout where speech cannot carry — off the SAME
severity gate the audio channel uses.

### Added

- **`HapticCuePattern`** (3 values: `none` / `warning` / `critical`)
  in `lib/src/haptic_cue_pattern.dart`. Declaration order is
  load-bearing and parallels `AlertSeverity`.
- **`hapticCueForSeverity(AlertSeverity)`** — pure (Flutter-free)
  function mapping a severity to its tactile cue. Mirrors the audio
  channel's gate exactly: it returns a tactile (non-`none`) cue for
  exactly the set `{warning, critical}` the audio channel announces
  (`severity.index >= AlertSeverity.warning.index`). The deaf
  driver's cue set therefore EQUALS the hearing driver's warning set
  — no reduced subset — with the two announced tiers rendered as
  **distinct** cues (`pulseCount` 2 vs 3) so they can be told apart.
  A single undifferentiated buzz is *worse than honest*.
- **`HapticCuePatternRendering`** extension: `pulseCount`
  (`none`→0 / `warning`→2 / `critical`→3) and `isTactile`. These are
  the pure *grammar*, not a platform call; a Flutter-side engine
  (in `voice_guidance`) renders them.

### Discipline

- **Severity-not-profile invariant**: `hapticCueForSeverity` is a
  pure function of `AlertSeverity` ONLY, taking no `DriverProfile`
  by construction. Severity decides whether/what; a profile only
  ever decides how.
- **Set-parity invariant** (load-bearing, locked by test): the set
  of severities producing a tactile cue equals the set the audio
  channel announces. Locked by `test/haptic_cue_pattern_test.dart`.
- **Stays pure-Dart**: `dependencies: {}` preserved. The new file
  imports only the in-package `alert_severity.dart`. No Flutter, no
  transitive deps. The package's accessibility-channel grammar is
  available to a non-Flutter consumer.

### Tests

- 6 new tests in `test/haptic_cue_pattern_test.dart`: cardinality;
  declaration order; `pulseCount` grammar; `isTactile`;
  severity-coupling lock (info→none / warning→warning /
  critical→critical); set-parity (tactile-cue set ==
  audio-announced set `{warning, critical}`, distinct cues).

### Grounded in

- `DRIVER_VOICES.md` deaf / hard-of-hearing entry (SafeDrive4Deaf
  n=25/100%, Bauman 2009, Gaffary & Lécuyer 2018): differentiated
  cues are both wanted and effective; a single static buzz is not.

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

## 0.1.0 — 2026-05-07

Initial release. Four pure-enum domain types extracted verbatim from
`navigation_safety_core` 0.10.0:

- `AlertSeverity` (3 values: info / warning / critical)
- `CircadianPhase` (6 values + `multiplier` extension + `circadianPhaseFromHour` helper)
- `DriverState` (4 values: alert / fatigued / distracted / impairedVisibility)
- `DriverProfile` (6 values incl. `foreignTouristSnowZone`)

Source files are byte-identical to the corresponding files in
`navigation_safety_core` 0.10.0 (zero diff verified at extraction
time). No Flutter dependency. No transitive dependencies beyond
`test` and `lints` for development.

License: BSD-3-Clause (mirrors `navigation_safety_core`).

This release ships the package standalone. A subsequent
`navigation_safety_core` 0.11.0 release will depend-on and re-export
from this package for ABI-compat; that is a separate next-cadence
spawn and not part of this 0.1.0 release.
