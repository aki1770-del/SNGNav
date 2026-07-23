# Changelog

## 0.1.0

First release — the calibration-free position-integrity **floor**.

- `PositionIntegrityMonitor` — wrap a fused location stream; each `update` of a
  `PositionFix` returns an `IntegrityVerdict` (`status` trusted/suspect/failed +
  `recommendedSource` gps/deadReckoning/hold + a human-readable `reason` + a
  per-gate `gateResults` audit map + an `isClean` convenience + the
  `interFixInterval` since the previous fix — a post-blackout caution signal).
- Four calibration-free plausibility gates: `teleport`, `impossibleSpeed`,
  `impossibleAccel`, `stationaryJitter`. Hard faults fail immediately; soft
  faults debounce before escalating. The `impossibleAccel` gate divides the
  speed change by the MEAN of the two sampling intervals, so irregular sampling
  (a burst after a dropout — the winter-canyon reacquisition pattern) does not
  fabricate a fault on legitimate motion.
- Source handoff honours dead-reckoning freshness: a fault recommends
  `deadReckoning` only when the caller vouches the DR estimate is fresh,
  otherwise the conservative `hold`.
- Pure Dart, zero runtime dependencies, deterministic, offline. No motion model,
  road graph, network, or calibration required.
- Honesty bounds documented and permanent: `trusted` ≠ correct; this is
  multipath/teleport protection, not anti-spoofing; it never recommends a source
  it cannot vouch for. See `KNOWN_LIMITATIONS.md`.
