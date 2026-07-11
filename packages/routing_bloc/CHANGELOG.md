# Changelog

## 0.4.5

- Widen the `routing_engine` constraint to `>=0.4.0 <0.7.0` so this package can
  resolve alongside `routing_engine` 0.6.0 and `route_condition_forecast` 0.2.0.

  `routing_engine` 0.6.0 fixes a safety defect: `RouteManeuver.position` was
  silently returning `const LatLng(0, 0)` — Null Island, a real coordinate in
  the Gulf of Guinea — for a maneuver whose location failed to parse. It is now
  nullable. **This package's `lib/` reads no maneuver position**, so 0.6.0 is
  source-compatible and this is a PATCH release, not a breaking one.

  The widen is not cosmetic: for a 0.x package a caret does not admit the next
  minor, so without it `route_condition_forecast` 0.2.0 (which pins
  `>=0.6.0`) and this package had an EMPTY intersection — a consumer combining
  a routing bloc with route condition forecasting would have hit a hard
  `version solving failed`.

- The example app now guards the nullable position: a maneuver with no location
  is not given a substitute coordinate.

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

