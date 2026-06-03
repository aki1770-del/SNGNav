# Changelog

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
