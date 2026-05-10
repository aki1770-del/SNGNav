# Changelog

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

