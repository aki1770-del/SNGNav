# Changelog

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
