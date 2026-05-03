# Changelog

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
