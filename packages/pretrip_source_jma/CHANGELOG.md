# Changelog

## 0.1.0 — 2026-06-14 — Initial scaffold

- Initial release of the Japan Meteorological Agency (AMeDAS)
  measured-visibility source for the
  [`pretrip_decision_advisor`](https://pub.dev/packages/pretrip_decision_advisor)
  pre-trip "Before you drive" briefing.
- `JmaVisibilityProvider` fetches the nearest fresh surface-visibility
  reading (metres) from the JMA AMeDAS open-data network around a requested
  point: it reads `latest_time.txt` for the snapshot timestamp, the
  `amedastable.json` station table for nearest-station geometry, and the map
  snapshot for the visibility sensor value — accepting a value only when its
  QC flag is 0 (normal) and the snapshot is newer than `maxObservationAge`.
- Emits the source-neutral `VisibilityObservation` (re-exported from
  `pretrip_decision_advisor`) — the same typed measurement the Finnish
  Digitraffic source emits — so the advisor's `mergeObservedVisibility`
  merge logic lives once, not per source.
- Honesty rules (binding): visibility is NEVER estimated; a warning NEVER
  produces a number; an observation is valid for the departure hour ONLY;
  any non-normal QC flag, no station in range, no fresh visibility, or any
  fetch failure → `null` (the driver's own judgement, never a fabricated
  hazard). HTTP/parse failures throw `JmaVisibilityException`.
- Extracted verbatim from the SNGNav app provider; the
  `VisibilityObservation` / `mergeObservedVisibility` measurement contract is
  owned by the published `pretrip_decision_advisor` 0.2.0 package, resolved
  from pub.dev (no app-relative imports).
- Measurement-vs-warning sibling: `condition_aggregator_jma` (same upstream
  JMA provider) emits a WARNING (`Advisory`); this package emits a
  MEASUREMENT (`VisibilityObservation`).
- License + attribution: package code BSD-3-Clause; the data is 気象庁 /
  Japan Meteorological Agency open data — the integrator surfaces the
  attribution at the consumer-facing HMI.
- Tests: 7 mocked-HTTP cases via `package:http/testing.dart` `MockClient`
  (nearest fresh QC-0 reading served; no-visibility-sensor station skipped;
  non-zero QC flag rejected; stale snapshot discarded; no-station-in-range →
  null; non-200 → `JmaVisibilityException`; plus an end-to-end case proving a
  measured 80 m Akita reading lights the advisor's whiteout/severe band the
  forecast alone never reaches).
