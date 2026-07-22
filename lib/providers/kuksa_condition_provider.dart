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
    Set<String> unsubscribedPaths = const {},
  })  : _fusion = VehicleConditionFusion.fromPartialFrames(
          partialFrames: updates
              .map(vssLeavesFromDatapoints)
              .map(VehicleConditionSignals.fromVss),
          surfaceFilter: surfaceFilter,
          clock: clock,
        ),
        unsubscribedPaths = Set.unmodifiable(unsubscribedPaths);

  final VehicleConditionFusion _fusion;

  /// VSS leaves the fusion reads that this broker does **not** expose, so the
  /// subscription deliberately omitted them ([connect]'s per-signal degradation).
  ///
  /// **Empty is the only state that means "the fusion is seeing everything it
  /// reads".** A non-empty set means the live picture is INCOMPLETE, and the
  /// caller MUST NOT present it as an unqualified live reading.
  ///
  /// Use this to NAME the absent leaves to an edge developer. Do **not** derive
  /// a detection-capability claim from it — derive that from the signals that
  /// actually arrived (see the note below).
  final Set<String> unsubscribedPaths;

  // NOTE — deliberately NO static "which paths are load-bearing" set lives here.
  //
  // A first cut of this change carried `preSlipVssPaths = {humidity,
  // airTemperature}` and let it drive the on-screen capability sentence. That
  // was WRONG, and wrong in the dangerous direction: `_iceRisk`
  // (`vehicle_signal_fusion.dart:108-126`) needs the ambient temperature for the
  // POST-slip path too — `if (tractionLoss && temp != null && temp <=
  // kColdSlipCelsius) return true` — and with no friction signal it returns
  // `null`. So a vehicle missing temperature cannot attribute ice EITHER side of
  // a slip, while the caption promised detection "AFTER traction is lost". An
  // explicit on-screen false assurance is worse than the silence this change was
  // written to fix.
  //
  // A hand-maintained path classification must be kept in sync with `_iceRisk`
  // by hand, and that is exactly what broke. Capability is therefore derived by
  // the CALLER from the signals that actually ARRIVED
  // ([VehicleConditionUpdate.signals] — on the partial-frame rail that is the
  // carried-forward merged snapshot). Reading capability from data rather than
  // from the subscription set also covers the leaf that is exposed but never
  // valued, and the value `fromVss` rejected as out-of-spec — neither of which a
  // path set can see.

  /// Whether the fusion can attribute black ice **at all** from the signals that
  /// actually arrived in [s].
  ///
  /// Mirrors `_iceRisk` (`vehicle_signal_fusion.dart:108-126`): a positive ice
  /// verdict needs EITHER a friction reading, OR an ambient temperature together
  /// with at least one traction-loss signal to attribute a slip to. With neither,
  /// `_iceRisk` returns `null` — the honest "we do not know" — and no ice warning
  /// can ever be raised from vehicle sensors, before OR after the wheels slip.
  ///
  /// `null` signals (an unavailable update) return `true`: absence of data is not
  /// evidence of incapability, and we never caption a capability claim we have
  /// not measured.
  static bool iceAttributableFrom(VehicleConditionSignals? s) =>
      s == null ||
      s.roadFriction != null ||
      (s.airTempC != null &&
          (s.tcsEngaged != null || s.absEngaged != null || s.escEngaged != null));

  /// Whether black ice can be seen **before** traction is lost.
  ///
  /// The radiative-frost pair: humidity WITH the ambient temperature is what lets
  /// the classifier flag the frost morning that friction and traction only reveal
  /// once the wheels have already slipped.
  static bool preSlipCapableFrom(VehicleConditionSignals? s) =>
      s == null || (s.humidityRH != null && s.airTempC != null);

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
  ///
  /// ## Per-signal degradation — why a whole-stream failure was wrong
  ///
  /// `kuksa.val.v2` `Subscribe` is **all-or-nothing**: if ANY requested path is
  /// unknown to the broker it rejects the entire stream with a trailers-only
  /// error, and the caller's `onError` sees one opaque failure. Measured
  /// 2026-07-21 against a real databroker: two absent leaves out of nine
  /// (`Vehicle.Exterior.Humidity`, `Vehicle.ADAS.ESC.IsEngaged`) produced **zero
  /// emissions, silently, forever**, while the scene kept showing a confident
  /// simulated default. A vehicle whose VSS tree simply does not publish humidity
  /// — the least universally-implemented of the nine — lost the *entire* live
  /// in-vehicle path, with no error, no log, and no visible symptom.
  ///
  /// So we ask the broker what it actually has ([KuksaClient.listMetadata]) and
  /// subscribe to the intersection, recording the remainder in
  /// [unsubscribedPaths].
  ///
  /// ## …and why degrading quietly would have been worse
  ///
  /// Degradation trades a LOUD total failure for a QUIET partial one, and the
  /// quiet direction is the dangerous one: the fusion refuses to fabricate from a
  /// missing signal, so a signal it never receives makes it **fail toward NO ice
  /// warning while the ice is real**. Losing the ambient temperature does not
  /// merely dim a feature — per `_iceRisk` it removes the ability to attribute
  /// ice on EITHER side of a slip whenever no friction signal exists.
  /// Therefore this method never degrades silently:
  ///
  ///  * every omitted leaf is published on [unsubscribedPaths] for the caller to
  ///    NAME (the caller derives detection CAPABILITY from arrived signals, not
  ///    from this set — see the note on the class);
  ///  * if the intersection is **empty** there is no live source at all and we
  ///    [StateError] rather than hand back a provider that can never emit —
  ///    the caller's existing no-broker fallback is the honest outcome;
  ///  * if `listMetadata` itself is unavailable (older broker, restricted
  ///    permissions) we fall back to subscribing the full set — identical to the
  ///    previous behaviour, never worse, and [unsubscribedPaths] stays empty
  ///    because in that case we genuinely do not know.
  static Future<KuksaConditionProvider> connect(
    KuksaClient client, {
    List<String> paths = VehicleConditionSignals.recognizedVssPaths,
    HysteresisFilter<RoadSurfaceState>? surfaceFilter,
  }) async {
    await client.connect();

    Set<String>? exposed;
    try {
      final metadata = await client.listMetadata();
      exposed = {for (final m in metadata.metadata) m.path};
    } catch (_) {
      // Discovery unsupported/denied — subscribe the full set exactly as before.
      // We do NOT claim knowledge of what is missing when we could not look.
      exposed = null;
    }

    if (exposed == null) {
      return KuksaConditionProvider(
        updates: client.subscribe(paths),
        surfaceFilter: surfaceFilter,
      );
    }

    final available = paths.where(exposed.contains).toList(growable: false);
    final missing = paths.where((p) => !exposed!.contains(p)).toSet();

    if (available.isEmpty) {
      throw StateError(
        'KUKSA broker exposes none of the ${paths.length} VSS leaves the '
        'condition fusion reads; there is no live in-vehicle source to '
        'subscribe to. Missing: ${paths.join(', ')}',
      );
    }

    return KuksaConditionProvider(
      updates: client.subscribe(available),
      surfaceFilter: surfaceFilter,
      unsubscribedPaths: missing,
    );
  }
}
