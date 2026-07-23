# Changelog

## 0.1.0

First release — the calibration-free position-integrity **floor**.

- `PositionIntegrityMonitor` — wrap a fused location stream; each `update` of a
  `PositionFix` returns an `IntegrityVerdict` (`status` trusted/suspect/failed +
  `recommendedSource` gps/deadReckoning/hold + a human-readable `reason` + a
  per-gate `gateResults` audit map).
- Four calibration-free plausibility gates: `teleport`, `impossibleSpeed`,
  `impossibleAccel`, `stationaryJitter`. Hard faults fail immediately; soft
  faults debounce before escalating.
- Source handoff honours dead-reckoning freshness: a fault recommends
  `deadReckoning` only when the caller vouches the DR estimate is fresh,
  otherwise the conservative `hold`.
- Pure Dart, zero runtime dependencies, deterministic, offline. No motion model,
  road graph, network, or calibration required.
- Honesty bounds documented and permanent: `trusted` ≠ correct; this is
  multipath/teleport protection, not anti-spoofing; it never recommends a source
  it cannot vouch for. See `KNOWN_LIMITATIONS.md`.
