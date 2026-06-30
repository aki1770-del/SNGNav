# Changelog

## 0.0.7 — 2026-06-30 — Doc honesty

- Docs: library dartdoc no longer claims `Phase: explore` /
  `publish_to: none`; corrected to reflect the published-to-pub.dev state.
  No code change.

## 0.0.6 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`) + `noaa_nws_adapter` (`^0.0.3`→`^0.0.5`).
- No source or behaviour change.


## 0.0.5

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.0.4 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


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
