# Changelog

## 0.3.3

**Safety fix — a broken friction sensor no longer reports PERFECT GRIP.**

`fromVss` divided the VSS road-friction percent by 100 and then **clamped** the
result into `0.0..1.0`. A finite value *outside* the spec — most commonly the
classic `255` "no reading" sentinel a broken ESC or CAN bridge emits — therefore
became:

```
(255 / 100).clamp(0.0, 1.0) == 1.0
```

…and `roadFriction: 1.0` does not mean "no reading". It means **a measured,
perfect-grip road**. Every caller reading `VehicleConditionSignals.roadFriction`
— to display it, to log it, to feed its own logic — was handed a confident
measurement manufactured out of a dead sensor.

A finite reading outside `0..100` is now **absent** (`null`). The producer is
broken, and the honest answer is that we do not know the road's grip. It is never
clamped: clamping an out-of-range value to the maximum asserts perfect grip on a
road nobody measured, which is precisely the failure this seam exists to prevent.
This is the same rule `kuksa_dart_sdk`'s `RoadFriction` already enforces on the
producer side, where an out-of-spec value is `RoadGrip.unknown` and never coerced.

### Honest scope — what this does NOT change

On the `0.3.x` line `WeatherCondition.iceRisk` is a plain `bool`, so it could not
say "unknown" either before or after this patch: a `255` reading yielded
`iceRisk: false` before (via the fabricated `1.0`) and yields `iceRisk: false`
now (via absence). **The ice verdict on this line is unchanged.** What is fixed is
the *fabricated measurement itself* — the public `roadFriction` field. Modelling
"we did not measure the road" as a first-class value requires the tri-state
`bool? iceRisk`, which is a breaking change and lands on the next minor line.

### The test that certified the bug

`test/vss_adapter_test.dart` contained `test('friction clamp: 150% → 1.0, -5% →
0.0')` — a test that asserted the fabrication was **correct**, sitting fifteen
lines above another test refusing the identical harm for `NaN` ("would assert MAX
grip"). The suite was green because the defect had a test defending it. That test
is now inverted, and covers `255.0 / 150.0 / 100.5 / -5.0 / -0.1`.

### Compatibility

No API change. Source- and binary-compatible with `0.3.2`; a pure narrowing of
behaviour (values that were previously fabricated into a measurement now correctly
read as absent). `^0.3.x` consumers receive it on the next `pub get`.

## 0.3.2

**Safety fix — an absent ambient temperature no longer hides an ice hazard.**

Up to and including 0.3.1, a vehicle that published *no* ambient temperature
(`Vehicle.Exterior.AirTemperature` absent, `airTempC == null`) was treated as if
the temperature were **+5 °C** — above freezing. Because the cold-slip ice rule
required a temperature at or below +2 °C, a car that was **actively losing
traction** (TCS, ABS, or ESC engaged) on a road whose temperature it did not
publish was classified as **`iceRisk: false`** — reported as aquaplaning, not
ice.

What you may have been shown: on such a vehicle, a real traction-loss event with
no temperature signal produced a *non-icy* road-surface verdict (e.g. `wet`
instead of `blackIce`) and no black-ice advisory, while the car was skidding.

- An absent temperature is now treated as **unknown, not warm**. A present
  traction-loss event (TCS/ABS/ESC engaged) keeps the ice concern when the
  temperature is unknown — absence never downgrades a hazard (caution-add-only).
  When a real temperature *is* published, behaviour is unchanged: a genuine
  warm-road traction-loss (e.g. +12 °C) is still not classified as ice.
- The friction path is unchanged (it was always temperature-independent): a
  low-friction reading still asserts ice with or without a temperature.
- `kAssumedAboveFreezingCelsius` is now **`@Deprecated`**. It is still exported
  and still `5.0` (nothing removed, no signature changed), but it no longer
  decides ice risk. It is retained only to fill the non-nullable temperature
  field and disambiguate rain-vs-snow when no ice hazard is at stake.

Known residual (needs a breaking type change, tracked for the next `x.y` line):
the downstream `WeatherCondition.temperatureCelsius` field is non-nullable, so an
absent temperature is still back-filled for the rain-vs-snow split. A
freezing-rain road with a dead temperature sensor **and** no friction/traction
signal can still be classified `wet`. Modelling temperature-absence as a
first-class value resolves it but changes the type contract.

Migration: none required — this release is source-compatible. If your code reads
`kAssumedAboveFreezingCelsius`, expect a deprecation notice; the value is
unchanged.

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
