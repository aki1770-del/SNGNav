# Changelog

## 0.4.5

- Widen the `routing_engine` constraint to `>=0.4.0 <0.7.0`.

  Up to `routing_engine` 0.5.0, `RouteManeuver.position` silently substituted
  `const LatLng(0, 0)` — Null Island, a real coordinate in the Gulf of
  Guinea — for a maneuver whose location failed to parse. `routing_engine`
  0.5.1 fixes this in-range by skipping unlocatable maneuvers, and a future
  0.6.0 line makes the position nullable instead. **This package's `lib/`
  reads no maneuver position**, so either line is source-compatible and this
  is a PATCH release, not a breaking one.

  The widen is not cosmetic: for a 0.x package a caret does not admit the next
  minor, so without it this package and any future consumer of the
  `routing_engine` 0.6.x line would have an EMPTY intersection — a hard
  `version solving failed` for a consumer combining the two.

- The example app pins `routing_engine` to the published line
  (`>=0.4.0 <0.6.0`, resolving 0.5.x today) and is written against the 0.5.x
  API, so it resolves and compiles for anyone copying it as-is. On 0.5.1+
  the engine itself skips unlocatable maneuvers, so every maneuver the
  example receives carries a real position — no substitute coordinate is
  ever shown.

## 0.4.4

- Widen the `routing_engine` constraint to `>=0.4.0 <0.6.0` so consumers can
  take `routing_engine` 0.5.0 (language-honoring turn-by-turn narration)
  alongside `routing_bloc`. No library code change (lib/ is byte-identical
  to 0.4.3).


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

