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
    show DrivingConditionAssessment, HysteresisFilter, RoadSurfaceState;
import 'package:driving_weather/driving_weather.dart' show WeatherCondition;
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

/// Back-compat alias: the app historically named the fused emission
/// `KuksaConditionUpdate`; it is now the package's transport-neutral
/// [VehicleConditionUpdate]. Kept so existing callers (e.g. `main.dart`) need no
/// change.
typedef KuksaConditionUpdate = VehicleConditionUpdate;

// ---------------------------------------------------------------------------
// What we ask the vehicle for — and why it is this list and not the SDK's.
// ---------------------------------------------------------------------------

/// The VSS leaves SNGNav subscribes to, **derived from the decoder's own list**
/// so the request and the decode cannot drift apart.
///
/// This used to be the SDK's `kSnowSafetySignals`, and the two lists had
/// silently diverged. Measured 2026-09-11: 10 subscribed, 9 decodable, **7
/// actually flowing**. Three leaves were requested and never decoded
/// (`RoadFriction.LowerBound` and both Row-1 tyre pressures); two the fusion
/// needs were never requested at all (`Vehicle.Exterior.Humidity`, the
/// radiative-frost witness that fires ABOVE freezing, and
/// `Vehicle.ADAS.ESC.IsEngaged`, a third slip witness).
///
/// That is not cosmetic. `kuksa.val.v2` Subscribe is **all-or-nothing**: one
/// leaf this vehicle lacks and NOTHING is delivered. Measured against
/// `kuksa-databroker:0.7.1` on a trim without TPMS, the two unused tyre-pressure
/// leaves killed the whole subscription — friction, TCS, ABS, temperature,
/// wiper, rain and speed all lost, for two signals we never read. Every path in
/// the request is a liability, so the request contains exactly the paths we can
/// use, and `kuksa_live_road_condition_test.dart` fails if that stops being true.
const List<String> kSngnavVehicleConditionSignals =
    VehicleConditionSignals.recognizedVssPaths;

// ---------------------------------------------------------------------------
// The honest floor, and the caption that must not out-claim it.
// ---------------------------------------------------------------------------

/// The assessment to hold when the vehicle has not told us about the road.
///
/// `isAssessed` is false and `recommendedResponse` is
/// `RecommendedResponse.conditionsUnknown` — an admission, never a claim. Use
/// this anywhere a live in-vehicle read has failed or has not yet arrived.
///
/// Before 2026-09-11 the scene simply KEPT its simulated getting-started
/// default when the live read failed. Measured on screen with zero live
/// signals: `RoadSurfaceState.blackIce`, advisory *"Black ice risk — reduce
/// speed significantly"*. A hazard nobody measured, presented exactly like one
/// that was — and the cry-wolf that costs us the warning that matters.
///
/// This is NOT "treat unknown as hazardous". The governing doctrine is already
/// written at `snow_rendering/lib/src/models/road_surface_state.dart:58-63`:
/// positive evidence classifies on partial data, a benign classification needs
/// complete data, and *"Being offline does not mean 'ice'; it means 'unknown',
/// and unknown is a thing the driver is TOLD."* Cited, not re-authored.
DrivingConditionAssessment unmeasuredVehicleAssessment({DateTime? now}) =>
    DrivingConditionAssessment.fromCondition(
      WeatherCondition.unknown(timestamp: now ?? DateTime.now()),
    );

/// The forward-view caption, which must never claim a source that is not live.
///
/// The old else-branch read *"simulated default (live Digitraffic when
/// WEATHER_PROVIDER=digitraffic; live in-vehicle when KUKSA_HOST set)"* — and
/// it is shown ONLY when `KUKSA_HOST` IS set, so its parenthetical asserted a
/// conditional whose antecedent was true and whose consequent was false.
///
/// [absentSignals] are leaves this databroker holds **no metadata** for — the
/// vehicle does not have that sensor. It is deliberately NOT the set of leaves
/// that are merely quiet: `onUnknownPaths` cannot see those. Measured
/// 2026-09-11 against a full VSS 6.0 broker with no providers writing, all ten
/// paths resolved as *known* while every single one carried `hasValue == false`
/// — so an "unmeasured" count sourced from `onUnknownPaths` would have read
/// zero at the exact moment nothing was being measured. Saying "this vehicle
/// does not have it" and "this sensor is quiet" with one number would have been
/// a fabricated distinction.
///
/// [vehicleSourceSelected] is load-bearing and was nearly got wrong. The old
/// `else` branch is reached by TWO different states: "a live source was
/// selected and failed" AND "no live source was ever selected". In the second,
/// *"live in-vehicle when KUKSA_HOST set"* is true and useful advice, and the
/// scene really is showing the simulated default — deleting that guidance to
/// fix the first state would have removed correct help from the common path.
/// The states are split instead.
String vehicleConditionCaption({
  required bool liveVehicleReceived,
  required bool liveWeatherReceived,
  required List<String> absentSignals,
  bool vehicleSourceSelected = false,
  String? unavailableReason,
}) {
  const head = 'Forward-view — CPU-projected still frame, ';
  if (liveVehicleReceived) {
    if (absentSignals.isEmpty) {
      return '${head}LIVE in-vehicle VSS signals '
          '(KUKSA databroker, offline-capable)';
    }
    // Partial cover is still cover. Say what this vehicle cannot give us, so a
    // sensor it does not have reads as a gap rather than as reassurance.
    return '${head}LIVE in-vehicle VSS signals — '
        '${absentSignals.length} of '
        '${kSngnavVehicleConditionSignals.length} signals not available on '
        'this vehicle (${absentSignals.map(_leaf).join(', ')})';
  }
  if (liveWeatherReceived) {
    return '${head}live Digitraffic winter-road severity';
  }
  if (unavailableReason != null) {
    return '${head}in-vehicle signals UNAVAILABLE — road surface NOT MEASURED, '
        'which is not an all-clear. $unavailableReason';
  }
  if (vehicleSourceSelected) {
    // Selected, connect still in flight. Claim nothing in either direction.
    return '${head}asking the vehicle which road-condition signals it has…';
  }
  // No live source was ever selected, so the simulated getting-started scenario
  // really is what is on the glass. Say that it is not a measurement, and keep
  // the (here TRUE) pointer to the two live sources.
  return '${head}simulated default — NOT a measurement '
      '(live Digitraffic when WEATHER_PROVIDER=digitraffic; '
      'live in-vehicle when KUKSA_HOST set)';
}

/// `Vehicle.Exterior.Humidity` -> `Humidity`, so the caption stays readable at
/// a glance. The full path is in the failure reason for whoever needs it.
String _leaf(String vssPath) =>
    vssPath.contains('.') ? vssPath.split('.').last : vssPath;

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
    HysteresisFilter<RoadSurfaceState?>? surfaceFilter,
    DateTime Function()? clock,
    List<String> absentSignals = const <String>[],
  })  : assert(
          surfaceFilter is! HysteresisFilter<RoadSurfaceState>,
          'surfaceFilter must be HysteresisFilter<RoadSurfaceState?> — the '
          'NULLABLE type argument. Dart generics are covariant, so a '
          'HysteresisFilter<RoadSurfaceState> is ACCEPTED here at compile time '
          'and then throws "type \'Null\' is not a subtype of type '
          '\'RoadSurfaceState\'" inside HysteresisFilter.add the first time the '
          'road cannot be classified — the compound-failure frame this whole '
          'path exists to survive. Measured 2026-09-11: the throw escapes as an '
          'uncaught async error, so it does NOT become an honest `unavailable` '
          'update and the listener\'s onError never sees it. The analyzer '
          'cannot catch this; only running it can. This assert can.',
        ),
        _absentSignals = List<String>.unmodifiable(absentSignals),
        _fusion = VehicleConditionFusion.fromPartialFrames(
          partialFrames: updates.map(vehicleSignalsFromDatapoints),
          surfaceFilter: surfaceFilter,
          clock: clock,
        );

  final VehicleConditionFusion _fusion;
  final List<String> _absentSignals;

  /// The FIRST failure reason seen, which is the causal one.
  String? _firstFailureReason;

  /// The leaves this databroker holds no METADATA for — the vehicle does not
  /// have that sensor. Named by `onUnknownPaths` before the stream opened.
  ///
  /// **Not** the set of leaves that are merely quiet. `onUnknownPaths` is blind
  /// to those by construction: `resolveKnownPaths` calls a path *known* when
  /// metadata exists "whether or not a provider has ever written a value"
  /// (`kuksa_dart_sdk-0.2.6/lib/src/client/kuksa_client.dart:228-232`). A
  /// silent sensor is a liveness question, answered by the fusion's own
  /// watchdog, never by this list.
  List<String> get absentSignals => _absentSignals;

  /// The fused condition stream driving the Snow Scene.
  ///
  /// **The causal failure reason is preserved here, not clobbered.** The fusion
  /// emits `unavailable(reason: <the error>)` and then, one event later,
  /// `unavailable(reason: 'vehicle signal stream ended')` from its own
  /// end-of-stream handler — measured 2026-09-11, so the last thing a caller
  /// saw named nothing at all. A caller that had bothered to read the reason
  /// would have been shown the useless one. We keep the first.
  Stream<KuksaConditionUpdate> get conditions =>
      _fusion.conditions.map((update) {
        if (update.isAvailable) return update;
        _firstFailureReason ??= update.unavailableReason;
        final reason = _firstFailureReason;
        if (reason == null || reason == update.unavailableReason) return update;
        return VehicleConditionUpdate.unavailable(reason: reason);
      });

  /// Whether the most recent activity indicates live signals are flowing.
  bool get available => _fusion.available;

  /// Releases the source subscription and closes the output stream.
  Future<void> dispose() => _fusion.dispose();

  /// Connects [client] and subscribes to the leaves THIS vehicle actually has,
  /// out of [paths] (default [kSngnavVehicleConditionSignals]).
  ///
  /// ## Why this asks the vehicle what it has before it asks for anything
  ///
  /// `kuksa.val.v2` Subscribe is all-or-nothing. Measured 2026-09-11 against
  /// `kuksa-databroker:0.7.1` on a trim without TPMS: `connect()` returned OK,
  /// the subscribe stream then died `NOT_FOUND` with the bare message
  /// `Path not found` — naming no path — and **none** of the ten requested
  /// leaves was delivered. Friction, TCS, ABS, temperature, wiper, rain and
  /// speed, all lost to two tyre-pressure leaves this app never reads.
  ///
  /// So we resolve first and subscribe to the survivors: measured on the same
  /// vehicle, 8 of 10 leaves delivered and the 2 absent ones named. A signal
  /// this vehicle lacks costs us that signal, never all of them.
  ///
  /// ## Two different failures, never conflated
  ///
  /// A leaf the databroker has no metadata for (this vehicle has no such
  /// sensor) lands in [absentSignals]. A leaf that exists and is silent is a
  /// LIVENESS question and is not visible here at all — `resolveKnownPaths`
  /// reports a path known "whether or not a provider has ever written a value".
  ///
  /// Connection failure rethrows, and so does a vehicle that has NONE of the
  /// signals — the caller owns the honest fallback ([unmeasuredVehicleAssessment]),
  /// never a fabricated source.
  static Future<KuksaConditionProvider> connect(
    KuksaClient client, {
    List<String> paths = kSngnavVehicleConditionSignals,
    HysteresisFilter<RoadSurfaceState?>? surfaceFilter,
  }) async {
    await client.connect();

    final known = await client.resolveKnownPaths(paths);
    final absent = paths.where((p) => !known.contains(p)).toList();

    if (known.isEmpty) {
      // Not a degraded read — no read at all. Surface it rather than opening a
      // subscription that can only ever be silent.
      throw StateError(
        'this databroker knows none of the ${paths.length} road-condition '
        'signals we asked for: ${paths.join(', ')}',
      );
    }

    return KuksaConditionProvider(
      updates: client.subscribe(known),
      surfaceFilter: surfaceFilter,
      absentSignals: absent,
    );
  }
}
