# Changelog

## 0.0.1 — 2026-05-24 — Initial scaffold

- Initial release of the Fintraffic Digitraffic adapter for the
  `condition_aggregator` interface.
- Implements `AdvisoryProvider` against the open Digitraffic
  traffic-announcements endpoint
  (`https://tie.digitraffic.fi/api/traffic-message/v2/traffic-announcements`;
  no authentication required per Digitraffic swagger v3 `security: []`).
- Fetches GeoJSON FeatureCollection of active traffic announcements;
  filters to features near a requested point via bounding-box
  intersection; maps each feature to a source-neutral `Advisory`
  record using publisher-verbatim `trafficAnnouncementType` as
  `eventClass`.
- Source attribution: uses `AdvisorySource.other` as a placeholder.
  Carry-forward: propose `AdvisorySource.fintrafficFinland` upstream
  in `condition_aggregator` interface when 2+ Finnish-source adapters
  warrant the enum extension.
- CAP severity / certainty / urgency: mapped to `unknown` for v0.0.1.
  Digitraffic announcements do not expose CAP-class fields directly;
  heuristic mapping by `trafficAnnouncementType` is a v0.0.2 candidate.
- English headline + description selected from the
  `announcements[]` list when a `language: 'en'` entry exists.
