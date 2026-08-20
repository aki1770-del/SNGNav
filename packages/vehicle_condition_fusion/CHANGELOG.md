# Changelog

## 0.5.0

### Safety defect in 0.3.1 and earlier — please read

**Up to and including 0.3.1 — the version currently on pub.dev, and the one you
are almost certainly holding — a vehicle that did not publish an air temperature
was ASSUMED TO BE ABOVE FREEZING.**

```dart
// vehicle_signal_fusion.dart, 0.3.1 (verified in the published tarball)
const double kAssumedAboveFreezingCelsius = 5.0;
final temp = s.airTempC ?? kAssumedAboveFreezingCelsius;  // 5.0 °C
```

(0.4.0 appears below in this changelog but was **never published**; 0.3.1 is the
release every consumer actually has, and it carries the defect.)

The constant's own docstring defended this as safe, because "a missing signal
never fabricates ice". That is true, and it is beside the point: the missing
signal was instead fabricating the **absence** of ice. A vehicle with a silent
or absent temperature sensor reported `+5.0 °C`, which the downstream classifier
turned into `RoadSurfaceState.dry`, `gripFactor: 1.0`, and the advisory
**"Conditions normal"**.

This is the same defect class as `WeatherCondition.clear()` in `driving_weather`
0.4.4 — but it sits in the **offline path**, which makes it worse. This package
exists to keep working when the network feed is gone. That is the compound-failure
scenario, and it is exactly when a driver most needs to be told the truth.

Two smaller fabrications rode along:

- `windSpeedKmh: 0.0` was emitted immediately below a comment stating that the
  snow-safety signal set does not carry wind — declaring the absence and then
  filling it in anyway.
- A vehicle publishing **neither** wiper state **nor** rain sensor fell through
  to `PrecipitationType.none` — "it is not precipitating" — asserted from
  silence.

pub.dev versions are immutable. This note is the recall.

### Breaking

- **`kAssumedAboveFreezingCelsius` is REMOVED.** There is no longer an assumed
  temperature, because there is no longer an assumption.
- `vehicleSignalsToWeatherCondition` now returns a `WeatherCondition` whose
  unmeasured fields are `null` (requires `driving_weather: ^0.5.0`):
  - absent `airTempC` → `temperatureCelsius: null` (was `5.0`);
  - `windSpeedKmh: null`, always;
  - no wiper **and** no rain sensor → `precipType: null`, `intensity: null`,
    `visibilityMeters: null` (was `none` / `none` / `10000.0`);
  - **`iceRisk` is now tri-state (`bool?`)**: `true` only from a direct friction
    measurement below `kIcyFrictionThreshold` or an attributable traction-loss
    event; `false` only when friction was actually MEASURED and was fine;
    **`null` when there is no friction signal at all** (was `false` — a claim,
    not an absence).
  - the condition is tagged `ObservationSource.derived`, because its visibility
    is a proxy and its precipitation type is inferred from wiper + temperature.
- **`VehicleConditionFusion`'s `surfaceFilter` is now
  `HysteresisFilter<RoadSurfaceState?>`** (was `HysteresisFilter<RoadSurfaceState>`),
  since the surface may honestly be unknown. **Note:** Dart's covariant generics
  mean passing the old `HysteresisFilter<RoadSurfaceState>` still *compiles* —
  and then throws at runtime the first time an unknown surface arrives. Update
  the type argument.
- Requires `driving_conditions: ^0.6.0` (and thus `snow_rendering: ^0.3.0`),
  where `surfaceState` and `gripFactor` became nullable and
  `RecommendedResponse.conditionsUnknown` was added.

### Behavioural consequence, stated plainly

**A vehicle that publishes no precipitation signal at all no longer reports a
`dry` road.** It reports an unknown surface and
`RecommendedResponse.conditionsUnknown`.

This is a real reduction in what we claim, and it is correct: without any wiper
or rain-sensor reading, "dry" was never something the vehicle told us — it was
what the decision tree fell through to. If your integration relied on that
fall-through, publish `Vehicle.Body.Windshield.Front.Wiping.System.Mode` (or the
rain sensor) and `dry` returns, **earned** from a signal rather than assumed from
silence.

### Preserved: the Akita radiative-frost reach

The offline black-ice detection that matters most is **unchanged**: a car
reporting `+2 °C` and `70 % RH`, with the wheels not yet slipping and **no rain
sensor at all**, still classifies `RoadSurfaceState.blackIce` before the first
slip.

That reach would have been silently lost if the radiative-frost check had stayed
gated behind a *reported* precipitation type. It does not: black ice from
temperature + humidity is POSITIVE evidence and fires even when precipitation is
unreported. Absent data must never *suppress* a hazard that present data already
justifies. (Without humidity it still abstains — it does not fabricate the
hazard; it now abstains to `null` rather than to a fabricated `dry`.)

### Also

- Two pre-existing tests **certified the defect** and were inverted: one asserted
  `iceRisk == false` for a vehicle with no friction sensor; one asserted a `dry`
  road for a vehicle with no precipitation signal.

- **The shipped `example/` fell into the covariance trap this changelog warns
  you about.** `bridgeVssFramesToFusion` declared its parameter as
  `HysteresisFilter<RoadSurfaceState>`, and `example/test` constructed one. That
  compiles, and then throws `type 'Null' is not a subtype of type
  'RoadSurfaceState'` inside `HysteresisFilter.add` on the first frame with an
  absent signal — the exact case this release exists to handle. Both are now
  `RoadSurfaceState?`. It survived because `dart test` at the package root does
  not run `example/`, which is a separate package root with its own pubspec.

- A third example test **certified the defect**: it asserted
  `surfaceState == RoadSurfaceState.dry` for a frame whose only real signals
  were an above-freezing temperature and a speed. An unmeasured surface is now
  asserted as `null`, which is what `DrivingConditionAssessment.fromCondition`
  documents and returns.

- `example/pubspec.yaml` required `driving_conditions: ^0.5.2`, which selects
  0.5.7 and with it `driving_weather ^0.4.0` — the range this release exists to
  leave. It is now `^0.6.0`, matching the parent. pub.dev strips
  `dependency_overrides` from the published archive, so that constraint is what
  a reader who runs `dart pub get` in `example/` actually resolves; at `^0.5.2`
  it did not resolve against its own parent at all.

## 0.4.0

- **Map `Vehicle.Exterior.Humidity` → `VehicleConditionSignals.humidityRH`**
  (PERCENT) and pass it through `vehicleSignalsToWeatherCondition`. This is the
  offline-path reach for radiative-frost black ice: with a real air temperature
  AND a real humidity sensor the shared classifier
  (`isRadiativeFrostBlackIce` via `DrivingConditionAssessment.fromCondition`)
  can catch the clear-sky radiative-cooling window (surface below 0 °C while the
  air still reads +1…+3 °C) on the D3 compound-failure worst case — BEFORE the
  friction/TCS/ABS signals fire, which only reveal ice AFTER the wheels have
  already slipped. Honest fail-safe unchanged: a vehicle that does not publish
  humidity leaves `humidityRH` null and the classifier abstains — a missing
  sensor never fabricates a hazard. `fromVss` now reads nine leaves; carry-
  forward and equality include humidity. Requires `driving_weather ^0.4.4`.

## 0.3.1

- **Runnable KUKSA-databroker bridge example** —
  `example/kuksa_databroker.dart`. Shows the whole adapter as a four-line map
  chain: `client.subscribe(VehicleConditionSignals.recognizedVssPaths)` →
  decode each `Datapoint` to its scalar `.value` → `fromVss` per frame →
  `VehicleConditionFusion.fromPartialFrames` (carry-forward rail).
  - It imports the **real `kuksa_dart_sdk`** (an example-only dev-dependency —
    the published package stays completely SDK-free), so the live
    `client.subscribe(...)` bridge is compile-checked against the actual SDK
    types. `--live host:port` constructs a real `KuksaClient`.
  - The **default `dart run`** uses an in-process fake source shaped exactly
    like the decoded `subscribe` yield, so it runs end-to-end with **no
    databroker**. It demonstrates: an escalating black-ice verdict; partial-frame
    **carry-forward** (a speed-only frame still reports black ice); **garbage-frame
    honesty** (a non-finite friction degrades to `null`, never a fabricated max
    grip, and cannot erase a once-seen ice hazard); and **honest degradation**
    (a mid-drive disconnect yields an explicit `unavailable`, never the stale
    verdict).
  - Behavioural tests in `example/test/kuksa_databroker_test.dart` assert each of
    those properties.
- Docs-only / additive: the package `lib` and its public API are unchanged.

## 0.3.0

- **Zero-glue KUKSA on-ramp — `VehicleConditionSignals.fromVss(...)`.** A new
  factory that maps **standard COVESA VSS (v6.0)** leaf paths straight to the
  typed fields, so a KUKSA databroker user can hand the decoded `{path: value}`
  map (what a `get` / `subscribe` yields) in directly with no hand-written
  per-field glue.
  - The exact paths read are exposed as `VehicleConditionSignals.recognizedVssPaths`
    (and individually as `vssRoadFriction`, `vssTcsEngaged`, … constants) for
    building a `subscribe` request and for tests.
  - The wiper leaf is the **Front-instance** path
    `Vehicle.Body.Windshield.Front.Wiping.Intensity` — `Windshield` is an
    instanced branch (`["Front", "Rear"]`) in VSS, so this is the deployed
    databroker key. It is an actuator **setpoint** (uint8, no fixed max), a
    coarse precipitation cue; the measured precipitation channel is the separate
    `Raindetection.Intensity` sensor.
  - `ESC.RoadFriction.MostProbable` is a PERCENT in VSS, so it is divided by 100
    and clamped to `0.0..1.0`; `Raindetection.Intensity` is rounded/clamped to
    `0..100`; `Windshield.Front.Wiping.Intensity` (no fixed VSS max) is clamped
    `>= 0` only.
  - **Honest by construction:** an absent / `null` / non-coercible leaf leaves
    that field `null` (never a fabricated default), and a garbage frame degrades
    to `null` rather than throwing — a malformed leaf cannot crash the pipeline.
    A non-finite numeric (`NaN`/`Infinity`) is treated as garbage → `null`
    (notably, a `NaN` friction can no longer fabricate `1.0` max grip).
  - The VSS-typed **boolean** leaves (`TCS`/`ABS`/`ESC.IsEngaged`) accept a Dart
    `bool`, or an int `1`/`0` (faithful decoding of a `boolean` leaf from a CAN
    bridge / non-SDK source, so a traction-loss ice signal is not silently
    dropped); numeric leaves never accept a `bool`.
  - For KUKSA `subscribe` (partial frames), build a `fromVss` per frame and feed
    `VehicleConditionFusion.fromPartialFrames` (carry-forward rail).
- **New `escEngaged` field + ESC now contributes to cold-slip ice risk.** Added
  an additive (non-breaking) `bool? escEngaged` to `VehicleConditionSignals`
  (mapped from `Vehicle.ADAS.ESC.IsEngaged`). `Vehicle.ADAS.ESC.IsEngaged` is as
  strong an ice indicator as TCS/ABS, so — like them — an engaged ESC at/below
  `kColdSlipCelsius` now also contributes to ice risk in
  `vehicleSignalsToWeatherCondition`.
- Additive and non-breaking: the existing fields, the classifier semantics for
  prior signals, and every existing public API are unchanged; still pure Dart,
  no Flutter, no databroker SDK, no protobuf, no new dependency.

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
