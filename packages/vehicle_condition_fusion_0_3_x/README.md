# vehicle_condition_fusion

Safety-calibrated fusion of a vehicle's **own** signals into a driving-condition
hazard verdict, with an **honest-degradation** rail. Pure Dart — **no Flutter,
no databroker SDK, no protobuf, no gRPC.**

When the network and GPS are gone (the compound-failure worst case), a car still
knows things about the road from its own sensors: the ESC's road-friction
estimate, whether TCS/ABS are engaging, wiper / rain-sensor intensity, and
ambient air temperature. This package fuses those signals — **deterministically
and typed** — into the same `DrivingConditionAssessment` (`driving_conditions`)
that drives road-surface classification, grip, and visibility, so an edge
developer can turn raw vehicle telemetry into a glanceable, safety-calibrated
hazard picture and **unit-test it with a one-line mock**.

## Try it in 2 minutes (no databroker, no vehicle)

You can drive the fusion through a full **Akita heavy-snow / low-visibility
drive** with just a laptop — the package ships an opt-in `scenarios.dart`
library of hand-authored **synthetic** winter traces and a one-line replay
helper. Two ways to run it:

### A. From your own project (`pub add`)

```console
$ dart pub add vehicle_condition_fusion
```

`pub add` installs the package as a dependency — it does **not** copy this
repo's `example/` into your project. So drop this self-contained snippet into
`bin/demo.dart` and run it with `dart run bin/demo.dart`:

```dart
import 'package:vehicle_condition_fusion/scenarios.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

Future<void> main() async {
  // Replay the bundled SYNTHETIC Akita whiteout through the published fusion.
  // Swap replayWinterDrive() for your own Stream<VehicleConditionSignals>
  // (a KUKSA adapter, a CAN reader, a test) — same fusion.
  final fusion = VehicleConditionFusion.fromPartialFrames(
    partialFrames: replayWinterDrive(akitaWhiteoutDrive),
  );
  await for (final update in fusion.conditions) {
    if (update.isAvailable) {
      final a = update.assessment!;
      print('${a.surfaceState.name.padRight(13)} ${a.advisoryMessage}');
    } else {
      print('— drive ended (${update.unavailableReason}) —');
      break;
    }
  }
  await fusion.dispose();
}
```

It replays the bundled synthetic drive, printing the surface verdict and
advisory as the hazard escalates and clears:

```text
dry           Conditions normal
dry           Conditions normal
dry           Conditions normal
compactedSnow Compacted snow — use winter tyres, reduce speed
compactedSnow Compacted snow — use winter tyres, reduce speed
blackIce      Black ice risk — reduce speed significantly
blackIce      Black ice risk — reduce speed significantly
blackIce      Black ice risk — reduce speed significantly
slush         Slushy conditions — maintain safe following distance
slush         Slushy conditions — maintain safe following distance
wet           Wet road — increased stopping distance
wet           Wet road — increased stopping distance
— drive ended (vehicle signal stream ended) —
```

### B. Run the shipped example (from a repo clone)

The richer example — per-step inputs, the debounced surface verdict, grip, a
visibility cue, and a `(held)` marker on debounce-held steps — runs from a
clone of this repository (it is also what appears on the pub.dev **Example**
tab). `pub add` does **not** install it, so:

```console
$ git clone https://github.com/aki1770-del/SNGNav
$ cd SNGNav/packages/vehicle_condition_fusion
$ dart pub get
$ dart run example/main.dart
```

You will see the hazard escalate and clear, step by step (the whole
assessment is debounced, so fresh inputs sit beside a `(held)` verdict while
the surface state has not yet persisted):

```text
step  1  fric= 0.95 temp= -1°C tcs=off wiper=0 → dry           grip=1.00
    vis: clear   (~10 km)  Conditions normal
step  2  fric= 0.95 temp= -1°C tcs=off wiper=0 → dry           grip=1.00
    vis: clear   (~10 km)  Conditions normal
step  3  fric= 0.45 temp= -3°C tcs=off wiper=3 → dry           grip=1.00 (held)
    vis: clear   (~10 km)  Conditions normal
step  4  fric= 0.45 temp= -3°C tcs=off wiper=4 → compactedSnow grip=0.30
    vis: reduced (~800 m)  Compacted snow — use winter tyres, reduce speed
step  5  fric= 0.18 temp= -6°C tcs=ON  wiper=5 → compactedSnow grip=0.30 (held)
    vis: reduced (~800 m)  Compacted snow — use winter tyres, reduce speed
step  6  fric= 0.18 temp= -6°C tcs=ON  wiper=5 → blackIce      grip=0.15
    vis: LOW     (~300 m)  Black ice risk — reduce speed significantly
step  7  fric= 0.18 temp= -6°C tcs=ON  wiper=5 → blackIce      grip=0.15
    vis: LOW     (~300 m)  Black ice risk — reduce speed significantly
step  8  fric= 0.55 temp= -2°C tcs=off wiper=2 → blackIce      grip=0.15 (held)
    vis: LOW     (~300 m)  Black ice risk — reduce speed significantly
step  9  fric= 0.55 temp= -1°C tcs=off wiper=1 → slush         grip=0.50
    vis: clear   (~5 km)   Slushy conditions — maintain safe following distance
step 10  fric= 0.85 temp=  3°C tcs=off wiper=2 → slush         grip=0.50 (held)
    vis: clear   (~5 km)   Slushy conditions — maintain safe following distance
step 11  fric= 0.85 temp=  4°C tcs=off wiper=2 → wet           grip=0.70
    vis: clear   (~5 km)   Wet road — increased stopping distance
step 12  fric= 0.85 temp=  4°C tcs=off wiper=2 → wet           grip=0.70
    vis: clear   (~5 km)   Wet road — increased stopping distance

— drive ended — fusion now reports: vehicle signal stream ended
  (no live signals → honest "unavailable", never a fabricated road)
```

Then swap in **your own** signal source. The fusion's input seam is a plain
`Stream<VehicleConditionSignals>`, so replace `replayWinterDrive(...)` with your
KUKSA databroker adapter, your CAN reader, or any source that produces
`VehicleConditionSignals`:

```dart
final fusion = VehicleConditionFusion.fromPartialFrames(
  partialFrames: myKuksaAdapter.signals, // your real source — same fusion
);
```

> ⚠️ **The bundled traces are ILLUSTRATIVE / SYNTHETIC** — hand-authored
> plausible values chosen to exercise the hazard rules, **not** recordings of any
> real vehicle, drive, or storm. They are a teaching fixture to lower the floor;
> they are not evidence about real roads. The `scenarios.dart` library is a
> separate, opt-in import and is intentionally **not** part of the main barrel, so
> the safety-calibrated fusion is untouched — the traces only *feed* it.

## What it does

- `VehicleConditionSignals` — a typed, all-nullable snapshot of the snow-safety
  signals (`roadFriction`, `tcsEngaged`, `absEngaged`, `escEngaged`,
  `wiperIntensity`, `rainIntensity`, `airTempC`, `speedKmh`). A signal the
  vehicle has not published is `null`, never a fabricated default.
- `vehicleSignalsToWeatherConditionOrNull(...)` — a pure, deterministic mapping
  to a `WeatherCondition` (no LLM, no prose, no ad-hoc heuristic), with named
  calibration thresholds: `kIcyFrictionThreshold` (0.3), `kColdSlipCelsius`
  (2.0). It returns **`null`** when no ice hazard is asserted *and* the ambient
  temperature was not measured — see "Calibration rules" below.
  (`vehicleSignalsToWeatherCondition(...)`, the non-nullable original, is
  `@Deprecated` since 0.3.4: it substitutes +5.0 °C for an unmeasured
  temperature. It is kept so `^0.3.x` builds do not break.)
- `VehicleConditionFusion` — a stream processor:
  `Stream<VehicleConditionSignals>` → `Stream<VehicleConditionUpdate>`. It fuses
  via `DrivingConditionAssessment.fromCondition`, debounces road-surface flicker
  with the existing `HysteresisFilter`, and degrades honestly. It has **two
  source rails**, differing only in how a `null` field on a later frame is read:
  the default constructor treats each snapshot as a **complete** picture (a
  `null` means "genuinely unknown now" — for a CAN reader / sensor fusion /
  tests), while `VehicleConditionFusion.fromPartialFrames` is for a
  **partial-frame** transport (KUKSA `subscribe`) and **carries forward** the
  last-known value per signal so a once-seen ice signal is not dropped (see the
  ⚠️ safety note below).

```dart
import 'dart:async';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

final source = StreamController<VehicleConditionSignals>();
final fusion = VehicleConditionFusion(signals: source.stream);

fusion.conditions.listen((u) {
  if (u.isAvailable) {
    print(u.assessment!.surfaceState); // e.g. RoadSurfaceState.blackIce
  } else {
    print('no live vehicle signals: ${u.unavailableReason}');
  }
});

source.add(const VehicleConditionSignals(roadFriction: 0.2, airTempC: -5));
```

## Calibration rules

- **ice risk** iff a *direct* road measurement says so — friction below
  `kIcyFrictionThreshold`, **or** TCS/ABS/ESC engaged at/below
  `kColdSlipCelsius` **or with the temperature unmeasured**. A car losing grip
  on a road whose temperature it did not publish keeps the ice concern rather
  than being dismissed as aquaplaning (0.3.2; extended to non-finite readings
  in 0.3.4).
- **precipitation** present iff wiper/rain-sensor say so; type is `snow` when
  temperature ≤ 0 °C else `rain` (temperature disambiguates what the wiper
  cannot).
- **temperature** = the measured ambient air temp. When it is **not** measured
  (`null`, or a non-finite reading from a broken sensor) and no ice hazard is
  asserted, `vehicleSignalsToWeatherConditionOrNull` returns **`null`** and the
  fusion emits an abstention rather than a verdict — see below.

### Absence never buys a benign verdict (0.3.4)

The classifier's first line is `if (condition.iceRisk) return blackIce`, decided
without the temperature. **Every branch after it reads the temperature**:
residual ice (`temp <= -3`), the radiative-frost check, freezing rain
(`temp <= 0`), standing water (`temp > 3`), the snow splits (`temp > 2`,
`temp < -2`). So with no hazard asserted and no measurement there is no verdict
left that is not a claim about an unread number — including `dry` at
`gripFactor: 1.0` with the advisory "Conditions normal".

Through 0.3.3 this package substituted **+5.0 °C** there. Falling snow was typed
`rain` (a −5 °C snowfall classified `wet`, grip 0.70, instead of
`slush`/`compactedSnow`; heavy precipitation reached "Standing water — risk of
aquaplaning at speed"), and an ordinary no-precipitation frame from a vehicle
with no temperature sensor reported **"Conditions normal"** at full grip.

Since 0.3.4 the fusion emits an **abstention** in that case:
`assessment: null`, `live: false`, `signals` retained, and
`unavailableReason: kUnmeasuredTemperatureReason` naming the missing VSS leaf.
A caller that already branches on `isAvailable` — as the snippet above does —
needs no change. The abstention is not an alarm: it asserts no hazard and
cannot cry wolf. **Positive evidence of a hazard still classifies on partial
data; only the benign verdict has to be earned.**

## Honest bounds — read this

- **The visibility value is a DOCUMENTED PROXY, not a measurement.** A vehicle
  has no meteorological visibility sensor; the visibility metres here are
  derived from precipitation intensity (wiper / rain-sensor) as an explicit,
  typed cue. Treat it as a glanceable hint, not a sensor reading. Because it is
  a **precipitation-intensity proxy only** — there is no wind signal in the set,
  so `windSpeedKmh` is hard-set to `0.0` — it **cannot** represent a wind-driven
  whiteout (地吹雪 / ground blizzard), where blowing snow collapses visibility
  with little or no falling precipitation. The bundled severe phase is therefore
  a heavy-snow, low-visibility drive (~300 m proxy), **not** a true whiteout.
- **Reads only — never commands.** This package only *interprets* signals; it
  never writes to or commands the vehicle.
- **Offline / vehicle-local.** No network, no GPS, no cloud weather — just the
  signals you feed it.
- **No fabrication.** A snapshot with no real signal is *not emitted*; a source
  error or end-of-stream surfaces a `VehicleConditionUpdate.unavailable` marker
  so the caller can keep its offline default and stop claiming "live". Since
  0.3.4 the same honesty covers the *partially*-signalled snapshot: real signals
  that cannot support a verdict (no hazard, no measured temperature) produce an
  abstention, not an all-clear.
- **`temperatureCelsius` is still filled on a HAZARD emission.** The
  `driving_weather` `0.4.x` `WeatherCondition` this line depends on has a
  non-nullable `double` there, so when a hazard *is* asserted and the
  temperature is unmeasured the emitted condition still carries `5.0` in that
  field. The verdict (`blackIce`) does not depend on it, but do not print that
  number as a reading. Modelling temperature-absence inside the type is the
  `0.5.x` line, and it is a breaking change.

## The input seam — bring any source

The input is `VehicleConditionSignals`, decoupled from any transport. Produce it
from:

- a **KUKSA databroker adapter** — your adapter decodes each raw frame to a
  `VehicleConditionSignals` (keeping the SDK / protobuf in *your* adapter, this
  package SDK-free) and drives `VehicleConditionFusion.fromPartialFrames`, which
  does the partial-frame carry-forward for you (see the ⚠️ safety note below),
- your **own CAN reader** (complete snapshots → the default constructor), or
- a **test** — `const VehicleConditionSignals(roadFriction: 0.2, airTempC: -5)`.

That is the whole point: you can unit-test the full hazard fusion with a plain
`StreamController<VehicleConditionSignals>` and direct construction — **no
`kuksa_dart_sdk` import, no protobuf, no running databroker.**

### From a KUKSA databroker (VSS paths)

If your source speaks **standard COVESA VSS** (Vehicle Signal Specification,
v6.0) — as a KUKSA databroker does — you do not even write the per-field
mapping. A KUKSA `get` / `subscribe` yields a map of `{VSS-leaf-path: value}`;
hand it straight to `VehicleConditionSignals.fromVss(...)`:

```dart
final signals = VehicleConditionSignals.fromVss({
  'Vehicle.ADAS.ESC.RoadFriction.MostProbable': 18.0, // percent → 0.18
  'Vehicle.ADAS.TCS.IsEngaged': true,
  'Vehicle.ADAS.ABS.IsEngaged': false,
  'Vehicle.ADAS.ESC.IsEngaged': true,
  'Vehicle.Exterior.AirTemperature': -6.0, // °C
  'Vehicle.Speed': 35.0, // km/h
  'Vehicle.Body.Windshield.Front.Wiping.Intensity': 4, // setpoint, no fixed max
  'Vehicle.Body.Raindetection.Intensity': 70, // percent
});
```

The map values are the **decoded scalars** your KUKSA client yields — a live
client returns typed `Datapoint`s, so you pass `datapoint.value` (a `bool` /
`int` / `double`), not the wrapper.

- The leaves it reads are exactly `VehicleConditionSignals.recognizedVssPaths`
  (use it to build your `subscribe` request); unknown / extra keys are ignored.
- `Windshield` is an **instanced** branch (`["Front", "Rear"]`) in VSS, so the
  deployed databroker key is the **Front**-instance path
  (`Vehicle.Body.Windshield.Front.Wiping.Intensity`).
- `ESC.RoadFriction.MostProbable` is a **percent** in VSS, so it is divided by
  100 and clamped to `0.0..1.0`; `Raindetection.Intensity` (a SENSOR, percent)
  is clamped `0..100`; `Windshield.Front.Wiping.Intensity` is an actuator
  **setpoint** with no fixed VSS max, so it is clamped `>= 0` only (a coarse
  precipitation cue, not a measured value).
- The VSS-typed **boolean** leaves (`TCS`/`ABS`/`ESC.IsEngaged`) accept a Dart
  `bool`, or an int `1`/`0` (faithful decoding of a `boolean` leaf from a CAN
  bridge / non-SDK source, so a traction-loss ice signal is not silently
  dropped); numeric leaves never accept a `bool`.
- **No fabrication:** a path that is absent, `null`, or holds a non-coercible
  value (including a non-finite `NaN`/`Infinity`) leaves that field `null` — a
  missing or garbage leaf is never a default, and a malformed frame degrades to
  `null` instead of throwing.
- **`Vehicle.ADAS.ESC.IsEngaged` is mapped** to `escEngaged` and, like TCS/ABS,
  contributes to cold-slip ice risk.
- **Intentionally not mapped:** the `Vehicle.Exterior.RoadSurfaceCondition`
  family (VSS `master` / unreleased v7, not in any released spec).

For a KUKSA `subscribe` (a **partial-frame** transport — only changed leaves are
re-sent), build a `fromVss` snapshot **per frame** and feed
`VehicleConditionFusion.fromPartialFrames`, which carries the last-known value
forward so a once-seen ice signal is not under-warned (see the ⚠️ safety note
below):

```dart
final fusion = VehicleConditionFusion.fromPartialFrames(
  partialFrames: kuksaFrames.map(VehicleConditionSignals.fromVss),
);
```

**Runnable end-to-end bridge:** [`example/kuksa_databroker.dart`](example/kuksa_databroker.dart)
wires a real `KuksaClient.subscribe(...)` into this fusion and ships an
in-process fake source so it runs on a laptop with **no databroker** —
`dart run example/kuksa_databroker.dart` prints an escalating black-ice verdict,
shows partial-frame carry-forward and garbage-frame honesty, then an honest
`unavailable` on disconnect. Go live with
`dart run example/kuksa_databroker.dart --live localhost:55555`.

> ⚠️ **SAFETY — partial-frame transports MUST carry forward; use the
> `fromPartialFrames` rail.** On the documented-primary KUKSA path, `subscribe`
> re-sends **only the signals that changed** after the first cycle. If those
> partial frames are fed to the **default** constructor (which treats every
> snapshot as complete), `roadFriction`, `tcsEngaged` / `absEngaged` /
> `escEngaged` (and the other ice-risk signals) drop to `null` the moment they
> rotate out of a frame —
> even while the real ice hazard on the road **persists unchanged**. Because this
> processor honestly refuses to fabricate from a missing signal, that would
> **fail toward NO ice warning while a real ice hazard persists** —
> intermittently as signals flicker, or sustainedly if an ice signal stops
> re-firing. That is the driver-dangerous direction: the snapshot looks safe
> exactly when the road is not.
>
> The rail that closes this gap is **`VehicleConditionFusion.fromPartialFrames`**:
> it maintains a running merged snapshot, carrying forward the last-known value
> per signal (via `VehicleConditionSignals.carriedForwardOnto`) before running
> the identical fusion pipeline — so a once-seen ice signal is held across later
> partial frames.
>
> ```dart
> // KUKSA / partial-frame transport: the rail carries forward for you.
> final fusion = VehicleConditionFusion.fromPartialFrames(
>   partialFrames: adapter.signals, // each event may re-send only what changed
> );
> ```
>
> Pick the rail by your transport's framing semantics: use `fromPartialFrames`
> for KUKSA `subscribe` (a `null` means "unchanged / not re-sent"); use the
> default constructor for **complete** snapshots — a CAN reader or sensor fusion
> where a `null` genuinely means "no longer valid" — which does **not** carry
> forward and so never over-warns on retracted data (see *What it does NOT do*).

> **Attribution / no affiliation.** VSS (Vehicle Signal Specification) is a
> [COVESA](https://github.com/COVESA/vehicle_signal_specification) standard and
> KUKSA is an [Eclipse Foundation](https://github.com/eclipse-kuksa) project.
> This package is an independent, SDK-free consumer of those open standards — it
> is **not affiliated with, nor endorsed by,** COVESA, the Eclipse Foundation, or
> the KUKSA project.

## What it does NOT do

- It is **not a transport.** It does not connect to or subscribe from a
  databroker — that is an adapter's job (and keeps this package SDK-free). Your
  adapter decodes raw frames to `VehicleConditionSignals`; the partial-frame
  **carry-forward** that KUKSA `subscribe` requires is then provided for you by
  the `VehicleConditionFusion.fromPartialFrames` rail (it is a **safety
  obligation**, not a stylistic split — see the ⚠️ note above). The carry-forward
  is rail-selected rather than always-on for a reason: the default
  complete-snapshot rail treats every snapshot as a *complete* picture, so a
  non-KUKSA source can null a field to mean "no longer valid"; carrying that
  forward would make such a source **over-warn** on stale data — the opposite
  divergence. The carry-forward is correct only when the source's framing
  semantics are known, which is why you pick the rail.
- It is **not a substitute for real sensors or real weather.** It interprets the
  signals you give it; garbage in, garbage out. It asserts ice only from a
  direct friction/traction measurement, never from a missing signal.
- It does **not** classify road surfaces itself — it reuses
  `driving_conditions`' existing classifier rather than duplicating it.

## License / safety

Display and advisory only (ASIL-QM) — no vehicle control.
