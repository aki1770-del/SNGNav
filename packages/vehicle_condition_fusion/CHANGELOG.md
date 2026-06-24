# Changelog

## 0.2.0

- **Lower the floor — try it with just a laptop.** Added an opt-in
  `scenarios.dart` library (a SEPARATE import, intentionally NOT in the main
  barrel, so the safety-calibrated fusion is untouched) with:
  - `replayWinterDrive(frames, {step})` — replays a list of
    `VehicleConditionSignals` as a stream (partial-frame style, to pair with
    `VehicleConditionFusion.fromPartialFrames`); `step: Duration.zero` (default)
    is instant for tests, a non-zero step paces a live demo.
  - named **ILLUSTRATIVE / SYNTHETIC** traces — `akitaWhiteoutDrive`
    (dry → compacted snow → black-ice whiteout → slush → wet), `blackIcePatch`
    (cold-slip TCS ice path), and `clearRoad` (benign). These are hand-authored
    plausible values, **not** recorded sensor data.
- Added a runnable `example/main.dart` that replays `akitaWhiteoutDrive` through
  the published fusion and prints the evolving assessment (surface state, grip,
  visibility cue, advisory) per step — so a developer SEES the hazard escalate
  and clear with no databroker and no vehicle.
- Added `test/scenarios_test.dart` pinning that the replay emits its frames and
  that each synthetic trace actually yields the hazard progression it claims
  (including that carry-forward HOLDS the whiteout across a speed-only frame).
- README: a "Try it in 2 minutes" on-ramp.
- Additive and non-breaking: the core API and the safety-calibrated fusion are
  unchanged; still pure Dart, no Flutter, no vehicle-SDK dependency.

## 0.1.0

- Initial release. Deterministic, safety-calibrated fusion of vehicle signals
  (road friction, TCS/ABS engagement, wiper/rain intensity, ambient temperature)
  into a `DrivingConditionAssessment`. Ice-risk is asserted only from a direct
  road measurement, a missing temperature never fabricates ice, and the
  visibility value is a documented precipitation proxy (a vehicle has no
  meteorological visibility sensor).
- Honest degradation: a dead or absent source surfaces `unavailable` and never a
  fabricated condition; no emission while no signal is decodable.
- Two transport rails so the safe behavior is the default per source type: the
  default constructor for complete snapshots, and `VehicleConditionFusion.fromPartialFrames`
  for a partial-frame transport (e.g. KUKSA `subscribe`) that carries the
  last-known value forward, so a once-seen hazard is not under-warned on a later
  partial frame.
- Pure Dart — no Flutter and no vehicle-SDK dependency. The input seam is a plain
  `VehicleConditionSignals`, so it mocks with a single constructor (no protobuf,
  no databroker).
