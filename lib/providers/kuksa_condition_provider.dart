/// KUKSA in-vehicle condition source — the compound-failure worst-case data path.
///
/// When the network and GPS are gone, the vehicle's *own* signals are still on
/// the local KUKSA databroker bus: road-friction estimate (ESC), TCS/ABS
/// engagement, wiper / rain-sensor intensity, and ambient temperature. This
/// provider subscribes to those VSS signals over gRPC via our published
/// `kuksa_dart_sdk` client and feeds them into the deterministic, safety-
/// calibrated fusion that now lives ONCE in the `vehicle_condition_fusion`
/// package — producing the SAME `driving_conditions` picture
/// (`DrivingConditionAssessment`) that already drives the 3D Snow Scene. No
/// network, no GPS, no cloud weather: just the bus the car already speaks.
///
/// ## Thin KUKSA adapter — fusion lives in the package
///
/// This file is intentionally a THIN adapter. The calibration (icy-friction /
/// cold-slip / assumed-temp thresholds), the deterministic VSS→condition
/// mapping, the carry-forward merge of partial frames, the HysteresisFilter
/// debounce, and the honest-degradation rail are NOT duplicated here — they are
/// the single source of truth in `package:vehicle_condition_fusion`. The only
/// KUKSA-SDK-coupled responsibility kept here is [vehicleSignalsFromDatapoints]:
/// decoding one raw `path → Datapoint` frame into the package's
/// transport-neutral `VehicleConditionSignals`. Decoded partial frames are fed
/// straight through to `VehicleConditionFusion.fromPartialFrames`, which does
/// the last-known-value carry-forward, fusion, debounce, and degradation.
///
/// ## Honest degradation (no fabrication)
///
/// If no databroker is reachable, or the stream errors / ends mid-session, no
/// condition is ever invented: the package emits a
/// `VehicleConditionUpdate.unavailable` marker (so the caller can keep its
/// last-good / offline-first default and stop claiming "live") — exactly the
/// honest-degradation contract the GPS-loss path already follows. Reads only;
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

/// Decodes one KUKSA subscribe/getValues snapshot (path → [Datapoint]) into the
/// package's transport-neutral [VehicleConditionSignals].
///
/// This is a per-frame decode only — it does NOT merge across frames. A signal
/// that is absent, value-less, or carries an unexpected wire type decodes to
/// `null` (never guessed). The carry-forward merge of partial KUKSA frames is
/// the package's job: decoded partial frames are fed straight into
/// `VehicleConditionFusion.fromPartialFrames`, so a `null` here means simply
/// "not present in THIS frame" and the package carries the last-known value
/// forward.
VehicleConditionSignals vehicleSignalsFromDatapoints(
  Map<String, Datapoint> datapoints,
) {
  final leaves = <String, Object?>{};
  for (final path in VehicleConditionSignals.recognizedVssPaths) {
    final dp = datapoints[path];
    if (dp == null || !dp.hasValue) continue;
    final Object? value = dp.floatValue ??
        dp.doubleValue ??
        dp.int32Value ??
        dp.uint32Value ??
        dp.int64Value ??
        dp.boolValue;
    if (value != null) {
      leaves[path] = value;
    }
  }
  return VehicleConditionSignals.fromVss(leaves);
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
/// [KuksaClient]. The raw frames are decoded ([vehicleSignalsFromDatapoints])
/// and handed to `VehicleConditionFusion.fromPartialFrames`, which owns the
/// carry-forward, fusion, debounce, and honest-degradation behaviour.
class KuksaConditionProvider {
  /// Primary, injectable constructor. [updates] is the raw KUKSA subscribe
  /// shape (`path → Datapoint`, partial after the first emission). Each frame is
  /// decoded to a package [VehicleConditionSignals] and the resulting stream
  /// drives `VehicleConditionFusion.fromPartialFrames` (which carries the
  /// last-known value of any field a partial frame did not re-send).
  KuksaConditionProvider({
    required Stream<Map<String, Datapoint>> updates,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
    DateTime Function()? clock,
  }) : _fusion = VehicleConditionFusion.fromPartialFrames(
          partialFrames: updates.map(vehicleSignalsFromDatapoints),
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

  /// Connects [client] and subscribes to [paths] (default
  /// [kSnowSafetySignals]), returning a wired provider.
  ///
  /// Connection failure rethrows — the caller owns the honest no-broker
  /// fallback (keep the offline default; never wire a fabricated source),
  /// matching the app's existing live-source opt-in pattern.
  static Future<KuksaConditionProvider> connect(
    KuksaClient client, {
    List<String> paths = kSnowSafetySignals,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
  }) async {
    await client.connect();
    return KuksaConditionProvider(
      updates: client.subscribe(paths),
      surfaceFilter: surfaceFilter,
    );
  }
}
