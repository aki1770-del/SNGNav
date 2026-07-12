/// KUKSA in-vehicle condition source — an EMBEDDED / IVI-target signal source.
///
/// ## What this path IS
///
/// An **opt-in** live condition source for a build running **on a vehicle
/// head-unit (IVI) or an embedded target that is already on the vehicle's own
/// network**, wired only when the edge developer passes
/// `--dart-define=KUKSA_HOST=<broker host>` (default port 55555). It subscribes
/// over gRPC to the COVESA VSS leaves the `vehicle_condition_fusion` package
/// reads (road friction, TCS/ABS/ESC engagement, wiper / rain-sensor intensity,
/// ambient temperature, humidity) and feeds them into that package's
/// deterministic, safety-calibrated fusion — producing the SAME
/// `DrivingConditionAssessment` that drives the 3D Snow Scene.
///
/// ## What this path IS NOT — read this before trusting it
///
/// **It is NOT the driver's compound-failure lifeline, and it is NOT the
/// offline safety path.**
///
///  * A KUKSA databroker is **another network hop** — a gRPC dial to a vehicle
///    bus. "No cloud" is not "no network". If the host is unreachable, this
///    source produces nothing.
///  * A **phone cannot touch that bus.** This stack ships **zero bytes onto the
///    driver's handset**; on the phone build `KUKSA_HOST` is unset and this
///    entire file is a no-op.
///  * Therefore it does **NOT** work in the no-network / phone-in-a-dead-zone
///    case. The offline safety path is the bundled, on-device one — not this.
///
/// Where this path DOES earn its keep is an IVI/embedded target wired to a real
/// vehicle bus: there the car's own ECUs are a genuine sensor the cloud cannot
/// replace. That is a real and different thing from the D3 worst case. Claiming
/// it as the D3 lifeline would be a fabrication about our own reach.
///
/// ## Thin KUKSA adapter — ONE adapter, and it lives in the package
///
/// The SDK-coupled responsibility kept here is exactly one step:
/// [vssLeavesFromDatapoints] decodes a raw `path → Datapoint` frame to the
/// `{leaf-path: scalar}` map shape that the package's
/// `VehicleConditionSignals.fromVss` consumes. **The VSS→typed-signals mapping
/// itself is NOT duplicated here** — `fromVss` owns it, including the
/// load-bearing unit conversion (`ESC.RoadFriction.MostProbable` is a VSS
/// **PERCENT, 0–100**, which `fromVss` divides by 100 and clamps into the
/// `VehicleConditionSignals` 0.0–1.0 contract).
///
/// This file previously carried a *second*, bespoke mapping
/// (`vehicleSignalsFromDatapoints`) that passed the raw percent straight
/// through. A real ESC reporting **18.0 %** (black ice) therefore arrived as
/// `roadFriction: 18.0`, which is not `< 0.3`, so the classifier did not
/// abstain — it positively asserted *"friction measured, road is fine"* and
/// returned **dry / grip 1.0 / "Conditions normal"**. Two adapters for one job
/// is HOW they diverged. There is now one.
///
/// The calibration, the carry-forward merge of partial frames, the
/// HysteresisFilter debounce, and the honest-degradation rail are likewise the
/// single source of truth in `package:vehicle_condition_fusion`.
///
/// ## Honest degradation (no fabrication)
///
/// If no databroker is reachable, or the stream errors / ends mid-session, no
/// condition is ever invented: the package emits a
/// `VehicleConditionUpdate.unavailable` marker (so the caller can keep its
/// last-good / offline-first default and stop claiming "live"). Reads only;
/// this provider never writes to or commands the vehicle.
library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart'
    show HysteresisFilter, RoadSurfaceState;
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

/// Back-compat alias: the app historically named the fused emission
/// `KuksaConditionUpdate`; it is now the package's transport-neutral
/// [VehicleConditionUpdate]. Kept so existing callers (e.g. `main.dart`) need no
/// change.
typedef KuksaConditionUpdate = VehicleConditionUpdate;

// ---------------------------------------------------------------------------
// KUKSA-SDK-coupled adapter: per-frame decode. The ONLY databroker-aware code.
// ---------------------------------------------------------------------------

/// Decodes one KUKSA subscribe/getValues snapshot (`path → `[Datapoint]`) to the
/// `{leaf-path: scalar}` frame shape that `VehicleConditionSignals.fromVss`
/// consumes — a `Datapoint`'s scalar `.value` is a `bool` / `int` / `double`, or
/// `null` when the leaf is absent / None.
///
/// **This is the ONLY KUKSA-SDK-coupled code in the app, and it does NOT map
/// units, fields, or paths.** That is deliberate: the VSS→signals mapping (and
/// with it the `RoadFriction.MostProbable` **percent → 0.0–1.0** conversion)
/// belongs to `VehicleConditionSignals.fromVss` and must exist exactly once. It
/// is the same four-line decode the package's own runnable bridge uses
/// (`packages/vehicle_condition_fusion/example/kuksa_databroker.dart`).
///
/// Per-frame decode only — it does NOT merge across frames. A leaf absent from
/// THIS frame simply does not appear in the map; `fromVss` leaves that field
/// `null` and `VehicleConditionFusion.fromPartialFrames` carries the last-known
/// value forward. Nothing is ever guessed.
Map<String, Object?> vssLeavesFromDatapoints(
  Map<String, Datapoint> datapoints,
) {
  return {
    for (final entry in datapoints.entries) entry.key: entry.value.value,
  };
}

// ---------------------------------------------------------------------------
// The provider — a thin KUKSA wrapper around the package fusion.
// ---------------------------------------------------------------------------

/// Subscribes to KUKSA snow-safety VSS signals and emits a deterministically
/// fused [KuksaConditionUpdate] stream for the Snow Scene.
///
/// Construct directly from any `Stream<Map<String, Datapoint>>` — including a
/// test stream of mock [Datapoint]s — for full testability without a running
/// databroker; or use [KuksaConditionProvider.connect] to wire a real
/// [KuksaClient]. Raw frames are decoded to VSS leaves
/// ([vssLeavesFromDatapoints]), typed by the package's
/// `VehicleConditionSignals.fromVss` — which owns the friction percent→0.0–1.0
/// conversion — and handed to `VehicleConditionFusion.fromPartialFrames`, which
/// owns carry-forward, fusion, debounce, and honest degradation.
class KuksaConditionProvider {
  /// Primary, injectable constructor. [updates] is the raw KUKSA subscribe
  /// shape (`path → Datapoint`, partial after the first emission). Each frame is
  /// decoded to VSS leaves, typed by `VehicleConditionSignals.fromVss`, and the
  /// resulting stream drives `VehicleConditionFusion.fromPartialFrames` (which
  /// carries the last-known value of any field a partial frame did not re-send).
  KuksaConditionProvider({
    required Stream<Map<String, Datapoint>> updates,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
    DateTime Function()? clock,
  }) : _fusion = VehicleConditionFusion.fromPartialFrames(
          partialFrames: updates
              .map(vssLeavesFromDatapoints)
              .map(VehicleConditionSignals.fromVss),
          surfaceFilter: surfaceFilter,
          clock: clock,
        );

  final VehicleConditionFusion _fusion;

  /// The fused condition stream driving the Snow Scene.
  Stream<KuksaConditionUpdate> get conditions => _fusion.conditions;

  /// Whether the most recent activity indicates live signals are flowing.
  bool get available => _fusion.available;

  /// Releases the source subscription and closes the output stream.
  Future<void> dispose() => _fusion.dispose();

  /// Connects [client] and subscribes to [paths], returning a wired provider.
  ///
  /// The default is `VehicleConditionSignals.recognizedVssPaths` — **exactly the
  /// leaves the fusion actually reads**, so the subscription cannot drift from
  /// the consumer. This deliberately replaces the SDK's `kSnowSafetySignals`,
  /// which omits `Vehicle.ADAS.ESC.IsEngaged` and `Vehicle.Exterior.Humidity`
  /// (the fusion reads both) and carries leaves the fusion ignores
  /// (`RoadFriction.LowerBound`, tire pressures). Humidity is load-bearing: with
  /// the ambient temperature it is what lets the classifier catch radiative-frost
  /// black ice BEFORE friction/traction fire — those only reveal ice once the
  /// wheels have already slipped.
  ///
  /// Connection failure rethrows — the caller owns the honest no-broker
  /// fallback (keep the offline default; never wire a fabricated source),
  /// matching the app's existing live-source opt-in pattern.
  static Future<KuksaConditionProvider> connect(
    KuksaClient client, {
    List<String> paths = VehicleConditionSignals.recognizedVssPaths,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
  }) async {
    await client.connect();
    return KuksaConditionProvider(
      updates: client.subscribe(paths),
      surfaceFilter: surfaceFilter,
    );
  }
}
