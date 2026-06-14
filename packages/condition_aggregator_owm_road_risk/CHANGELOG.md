# Changelog

## 0.1.3 — 2026-06-14 — Dependency hygiene

- Track latest `condition_aggregator` (`^0.0.4`→`^0.0.5`).
- No source or behaviour change.


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


## 0.1.0 — 2026-05-10 — Initial OpenWeatherMap Road Risk adapter

- `OwmRoadRiskClient`: lower-level HTTP client around the publisher's
  `POST /data/2.5/roadrisk` endpoint. Single-point or multi-waypoint
  track requests; returns the publisher's `alerts[]` array as
  typed [OwmRoadRiskAlert] records.
- `OwmRoadRiskProvider`: `AdvisoryProvider` implementation; one-shot
  point query mapped to source-neutral `Advisory` typed events.
  Composes through `AdvisoryAggregator` with sibling adapters
  (`condition_aggregator_jma`, `condition_aggregator_nws`).
- `OwmRoadRiskMapper`: caution-add-only severity bucketing from the
  publisher's `event_level` integer to CAP-class
  `AdvisorySeverity`; verbatim relay of `event` and `description`
  strings per Article 17 (β) discipline.
- Tests run against `MockClient` with a golden response fixture; CI
  does not burn publisher quota.
- Phase: explore. Operators supply their own publisher API key
  (`appid`) at `OwmRoadRiskProvider` construction time; this package
  does not bundle one.
- The umbrella `condition_aggregator` 0.0.3 does not yet name
  OpenWeatherMap as a dedicated `AdvisorySource`; 0.1.0 ships using
  `AdvisorySource.other`. A forward-additive enum bump in
  `condition_aggregator` 0.0.4+ will introduce a dedicated value;
  consumers consuming via `AdvisoryAggregator` see no breaking
  change.
