# Changelog

## 0.4.3
- docs: correct stale README install pin to current version (no API change).

## 0.4.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.4.1 — 2026-05-10 — Refresh stale dependency constraints

- Bump `navigation_safety: ^0.5.0` → `^0.9.0` (was 7-day-stale).
- Bump `routing_engine: ^0.3.0` → `^0.4.0` (consumer-side refresh
  matching the routing_engine 0.4.0 release earlier the same day).
- No source changes; pubspec dep-constraint refresh only. The
  monorepo `dependency_overrides:` block was masking the staleness
  locally; pana resolves against pub.dev (no overrides) and was
  penalizing the 0.4.0 release accordingly.

## 0.4.0 — 2026-05-10 — Pana score recovery + dart format alignment

- Trim pubspec `description` to ≤180 characters so search-engine
  snippets surface the package's purpose cleanly.
- Apply `dart format` across `lib/` and `test/` (15 files reformatted)
  to clear pana static-analysis formatter findings.
- No SDK source changes; metadata + formatter pass only.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

