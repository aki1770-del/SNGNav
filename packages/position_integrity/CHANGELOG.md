# Changelog

## Unreleased

**Configuration is now validated in release builds, not only in tests.**

The constructor previously validated its nine parameters with five `assert`s.
Dart strips `assert` from AOT builds (`dart compile exe`,
`flutter build --release`) and from plain `dart run`, keeping them only under
`dart test` / `flutter test` / Flutter debug. So every one of those guards was
present in every test run and in no shipped build, and no test had ever
constructed an invalid monitor in any mode.

The guards are now real `ArgumentError` / `RangeError` throws and fire in every
mode. They land on the edge developer at construction, on their first run,
never on a driver mid-drive: these are configuration values fixed at
construction, and runtime fix data is still handled the opposite way — `update`
rejects a non-finite fix with a `failed` verdict and never throws.

- **BEHAVIOUR CHANGE.** An invalid configuration that a release build silently
  accepted in 0.1.0 now throws. `RangeError` extends `ArgumentError`, so one
  `on ArgumentError` catch covers every guard.
- Four parameters gained guards they never had, in any mode:
  `stationaryRadiusMetres` (at `<= 0` the stationary-jitter gate can never
  fire), `minSpeedDelta` (at `<= 0` the teleport gate is never evaluated and
  never appears in `gateResults`, which a caller auditing that map cannot
  distinguish from a gate that passed), `jitterAccuracyMultiplier`, and
  `deadReckoningMaxAge`.
- `double.infinity` is now rejected for every threshold. It passed
  `assert(x > 0)` — and then `impliedSpeed > double.infinity` is always false,
  so the gate using it was silently disabled. The original asserts never caught
  this. NaN is rejected for the same reason; note that a rewrite to a bare
  `value <= 0` would have LOST the NaN rejection, because `double.nan <= 0` is
  false.
- New: `tool/release_guard_probe.dart` and
  `test/release_mode_guard_test.dart` — the release-mode test-matrix cell.
  The probe is compiled to a native executable and run, so the guards are
  exercised in the mode that ships. It reports its own assert mode and exits
  non-zero rather than returning a verdict it cannot vouch for, and the test
  builds it a second time with `--enable-asserts` to prove the cell can tell
  the two modes apart.

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
