# Changelog

## 0.0.3 — 2026-05-10 — Refresh stale dependency constraints

- `condition_aggregator: ^0.0.1` → `^0.0.3` (pre-existing 7-day-stale).
- `noaa_nws_adapter: ^0.0.1` → `^0.0.3` (pre-existing 7-day-stale).
- No source changes; pubspec dep-constraint refresh only.

## 0.0.2 — 2026-05-03

- Switch `condition_aggregator` and `noaa_nws_adapter` from path
  dependencies to hosted pub.dev dependencies (`^0.0.1` for each).
  No source change.

## 0.0.1 — 2026-05-03

Initial publish.

- `NwsAdvisoryProvider` implementation of
  `AdvisoryProvider` for the NOAA / NWS active-winter-alerts feed.
- `mapWinterAlertToAdvisory(WinterAlert) → Advisory` field-by-field
  mapping, exposed at top level for direct test invocation.
- 9 tests covering severity gradient, area + verbatim wording
  preservation, effective + expires window mapping (incl. nullable
  semantics), certainty + urgency direct enum mapping, construction
  + init-no-op.
- BSD-3-Clause license (matches the rest of SNGNav).
- Pure Dart, no Flutter dependency.
- Depends on `condition_aggregator` (interface) and
  `noaa_nws_adapter` (raw NWS HTTP+GeoJSON wrapper).
