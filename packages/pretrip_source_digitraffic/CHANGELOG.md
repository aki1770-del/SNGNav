# Changelog

## 0.1.0 — 2026-06-14 — Initial extraction

- Extracted `DigitrafficVisibilityProvider` from the SNGNav app
  (`lib/providers/digitraffic_visibility.dart`) into a standalone pure-Dart
  package under the new `pretrip_source_*` namespace.
- Fetches the nearest fresh measured road-network visibility (`NÄKYVYYS_M`,
  metres; falls back to `NÄKYVYYS_KM` × 1000) from Fintraffic's open
  Digitraffic road-weather network and emits a source-neutral
  `VisibilityObservation` (owned by `pretrip_decision_advisor` ^0.2.0).
- Runtime dependencies: `http` + `pretrip_decision_advisor` only. No Flutter.
- Safety contract preserved verbatim (see README.md): visibility is never
  estimated; an observation is valid for the departure hour only; `null` is the
  driver's own judgment, never a fabricated hazard.
- Sibling package: `condition_aggregator_digitraffic` (same upstream provider,
  emits a WARNING `Advisory`; this package emits a MEASUREMENT).
