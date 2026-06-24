# Changelog

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
