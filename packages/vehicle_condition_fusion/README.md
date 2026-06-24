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

## What it does

- `VehicleConditionSignals` — a typed, all-nullable snapshot of the snow-safety
  signals (`roadFriction`, `tcsEngaged`, `absEngaged`, `wiperIntensity`,
  `rainIntensity`, `airTempC`, `speedKmh`). A signal the vehicle has not
  published is `null`, never a fabricated default.
- `vehicleSignalsToWeatherCondition(...)` — a pure, total, deterministic mapping
  to a `WeatherCondition` (no LLM, no prose, no ad-hoc heuristic), with named
  calibration thresholds: `kIcyFrictionThreshold` (0.3), `kColdSlipCelsius`
  (2.0), `kAssumedAboveFreezingCelsius` (5.0).
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

## Calibration rules (preserved verbatim from the source pipeline)

- **temperature** = ambient air temp, or `kAssumedAboveFreezingCelsius` (5 °C)
  when absent — a *missing* temperature never fabricates ice.
- **precipitation** present iff wiper/rain-sensor say so; type is `snow` when
  temperature ≤ 0 °C else `rain` (temperature disambiguates what the wiper
  cannot).
- **ice risk** iff a *direct* road measurement says so — friction below
  `kIcyFrictionThreshold`, **or** TCS/ABS engaged at/below `kColdSlipCelsius`.

## Honest bounds — read this

- **The visibility value is a DOCUMENTED PROXY, not a measurement.** A vehicle
  has no meteorological visibility sensor; the visibility metres here are
  derived from precipitation intensity (wiper / rain-sensor) as an explicit,
  typed cue. Treat it as a glanceable hint, not a sensor reading.
- **Reads only — never commands.** This package only *interprets* signals; it
  never writes to or commands the vehicle.
- **Offline / vehicle-local.** No network, no GPS, no cloud weather — just the
  signals you feed it.
- **No fabrication.** A snapshot with no real signal is *not emitted*; a source
  error or end-of-stream surfaces a `VehicleConditionUpdate.unavailable` marker
  so the caller can keep its offline default and stop claiming "live".

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

> ⚠️ **SAFETY — partial-frame transports MUST carry forward; use the
> `fromPartialFrames` rail.** On the documented-primary KUKSA path, `subscribe`
> re-sends **only the signals that changed** after the first cycle. If those
> partial frames are fed to the **default** constructor (which treats every
> snapshot as complete), `roadFriction`, `tcsEngaged` / `absEngaged` (and the
> other ice-risk signals) drop to `null` the moment they rotate out of a frame —
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
