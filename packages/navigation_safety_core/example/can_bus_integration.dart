// Example: navigation_safety_core composed with the `j1939` package.
//
// Shows how a vehicle-CAN-aware Flutter or Dart app can pipe SAE J1939
// telematics events through the Pure-Dart safety vocabulary in
// `navigation_safety_core`. The result: an integrator-developer can
// `pub add navigation_safety_core j1939` and reach a driver-cognition
// advisory loop without authoring per-cohort threshold logic.
//
// Composition seam:
//
//   j1939.J1939Ecu.events  ──► PGN decode (here, J1939/71 vehicle
//                              speed only)
//   ambient-air reading    ──► (a labelled PLACEHOLDER in main below)
//                          ──► DrivingContext mapping (a signal this
//                              integration does not measure stays null)
//                          ──► NavigationSafetyConfig
//                              .forProfileWithContext
//                          ──► AlertExplainer.forConditionAndProfile(...)
//                              .action
//                          ──► driver-facing advisory string
//
// The mapping below decodes one J1939/71 PGN as an illustrative anchor:
//
//   * 0xFEF1 — Cruise Control / Vehicle Speed (CCVS1).
//     Byte offset 1..2 = wheel-based vehicle speed, 1/256 km/h per bit.
//
// It decodes no ambient-air, humidity or precipitation signal. Engine
// coolant temperature is NOT ambient air temperature and must not be
// passed as `ambientTempCelsius`: an earlier revision of this file did,
// so once the engine warmed past the warning temperature the advisory
// could not fire, whatever the air outside.
//
// Real integrations should consult SAE J1939/71 for the full SPN /
// PGN catalog and apply the same composition pattern to the other
// signals `DrivingContext` has fields for (ambient air temperature,
// relative humidity, time since precipitation). Wiper status, headlamp
// state and ABS / TCS engagement have no `DrivingContext` field.
//
// To run on a development host without a real CAN bus, see the j1939
// package README for `vcan` setup. This file is illustrative — the
// composition pattern is the load-bearing part, not the specific PGN
// payload decoder.
//
// ── Where work goes, and why it matters here ─────────────────────────
//
// A CAN frame loop runs at vehicle-bus rate for the whole journey, and
// this stream is an `async*` body: anything that throws inside the
// `await for` terminates the stream, and the driver stops receiving
// advisories entirely for the rest of the drive. So the rule this
// example teaches is:
//
//   ONCE, at startup   — build the VehicleThresholdOverrides registry
//                        with `.validated()`. Registration is where a
//                        wrong transform is refused, loudly, in front
//                        of the developer who can fix it.
//   PER FRAME          — derive only what genuinely depends on live
//                        context, and only when a sample actually
//                        changed. `forProfileWithContext` cannot throw
//                        on account of a registry built this way; each
//                        field it refuses goes back to its
//                        un-overridden value and is reported. A class
//                        that implements VehicleThresholdOverrides, or
//                        extends it and replaces applyOverrideForToken,
//                        is guarded only as far as its own method is: a
//                        throw from that method ends the stream.
//
// The config itself cannot be fully hoisted — it is a function of
// live speed and temperature, which is the entire point of a CAN
// integration. What CAN be hoisted is the registry, which is the part
// capable of being wrong. Earlier revisions of this file rebuilt
// everything per frame and taught the opposite.
//
// SPDX-License-Identifier: BSD-3-Clause

import 'dart:async';
import 'dart:typed_data';

import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Subset of the j1939 package's API used here. The real types live in
/// `package:j1939/j1939.dart`. Re-declared as a minimal abstract
/// surface so this example file can be analyzed without pulling the
/// j1939 dependency (which requires Linux SocketCAN + a CMake build).
abstract class _J1939EcuLike {
  Stream<_FrameReceivedLike> get frames;
  void dispose();
}

class _FrameReceivedLike {
  const _FrameReceivedLike({
    required this.pgn,
    required this.source,
    required this.data,
  });
  final int pgn;
  final int source;
  final Uint8List data;
}

// ── PGN decoders (J1939/71) ──────────────────────────────────────────

/// CCVS1 PGN 0xFEF1 — wheel-based vehicle speed in km/h.
double? decodeWheelSpeedKmh(_FrameReceivedLike frame) {
  if (frame.pgn != 0xFEF1 || frame.data.length < 3) return null;
  final raw = frame.data[1] | (frame.data[2] << 8);
  return raw / 256.0;
}

// ── DrivingContext bridge ────────────────────────────────────────────

/// Builds a [DrivingContext] from what this integration actually
/// measures. Only speed is required: pass `null` for any other signal
/// you do not measure, and the factory keeps the per-profile baseline
/// for that dimension. Never substitute a constant or another sensor
/// for a missing one: engine coolant temperature is not
/// [ambientAirTempCelsius], and a fixed humidity or precipitation
/// history tells the factory about weather nobody observed.
DrivingContext driveContextFromCanSamples({
  required double speedKmh,
  double? ambientAirTempCelsius,
  double? humidityRH,
  Duration? timeSincePrecipitation,
  String? vehicleClassToken,
}) {
  return DrivingContext(
    speedMps: speedKmh / 3.6,
    humidityRH: humidityRH,
    ambientTempCelsius: ambientAirTempCelsius,
    timeSincePrecipitation: timeSincePrecipitation,
    vehicleClassToken: vehicleClassToken,
  );
}

// ── Composition: vehicle-CAN → safety advisory ───────────────────────

/// Listens for J1939 frames, builds a [DrivingContext] from the latest
/// speed sample and the latest ambient-air reading, and yields the
/// advisory action an app can surface to the driver. Profile is fixed
/// here for clarity; in production it comes from the active driver
/// session.
///
/// [readAmbientAirTempCelsius] returns the vehicle's current ambient
/// air temperature, or `null` when there is none. This example has no
/// ambient-air source, so [main] passes a placeholder labelled as one.
/// With `null`, no temperature advisory is yielded: an unmeasured
/// temperature is never treated as a cold one.
///
/// [vehicleOverrides] is built ONCE by the caller (see [main]) and
/// passed in. It is never constructed inside the loop below: a
/// registry is startup configuration, not per-frame data, and
/// `.validated()` has already refused, at startup, any transform its
/// probes caught relaxing a warning threshold or changing a field an
/// override may not change.
Stream<String> safetyAdvisoryStream(
  _J1939EcuLike ecu, {
  required double? Function() readAmbientAirTempCelsius,
  VehicleThresholdOverrides? vehicleOverrides,
  String? vehicleClassToken,
}) async* {
  double? lastSpeedKmh;
  const profile = DriverProfile.snowZoneExperienced;

  // Hoisted: the explainer depends only on condition + profile, both
  // fixed for the session. Rebuilding it per frame bought nothing.
  final explainer = AlertExplainer.forConditionAndProfile(
    RoadSurfaceCondition.ice,
    profile,
  );

  // Memoised config: recomputed only when a sample actually moved.
  // A J1939 bus repeats PGNs at a fixed rate whether or not the value
  // changed, so most frames need no new config at all.
  double? configSpeedKmh;
  double? configAmbientC;
  NavigationSafetyConfig? config;

  await for (final frame in ecu.frames) {
    final speed = decodeWheelSpeedKmh(frame);
    if (speed != null) lastSpeedKmh = speed;
    final ambientC = readAmbientAirTempCelsius();

    if (lastSpeedKmh == null) continue;

    if (config == null ||
        configSpeedKmh != lastSpeedKmh ||
        configAmbientC != ambientC) {
      // Humidity and precipitation history are left null: this
      // integration measures neither, so the factory keeps the
      // per-profile baseline for them rather than acting on weather
      // nobody observed.
      final ctx = driveContextFromCanSamples(
        speedKmh: lastSpeedKmh,
        ambientAirTempCelsius: ambientC,
        vehicleClassToken: vehicleClassToken,
      );
      // Cannot throw on account of a registry built with a
      // VehicleThresholdOverrides constructor, as main() builds it: a
      // violating field goes back to its un-overridden value and is
      // reported, not raised. That is what keeps this `async*` stream
      // alive for the whole journey. A registry class that implements
      // VehicleThresholdOverrides, or extends it and replaces
      // applyOverrideForToken, runs its own method here, and a throw from
      // that method ends the stream.
      config = NavigationSafetyConfig.forProfileWithContext(
        profile,
        context: ctx,
        vehicleOverrides: vehicleOverrides,
      );
      configSpeedKmh = lastSpeedKmh;
      configAmbientC = ambientC;
    }

    // The measured AMBIENT AIR temperature, compared with the warning
    // temperature the config returns. `null` yields nothing.
    if (ambientC != null && ambientC <= config.warningTemperatureCelsius) {
      yield explainer.action;
    }
  }
}

// ── Local mock for analyzer-only runs ────────────────────────────────

/// Synthetic ECU that emits one CCVS1 wheel-speed frame (80 km/h).
/// Replace with `J1939Ecu.create(...)` from the j1939 package in
/// production.
class _MockEcu implements _J1939EcuLike {
  final _controller = StreamController<_FrameReceivedLike>();
  _MockEcu() {
    Future<void>.microtask(() async {
      _controller.add(
        _FrameReceivedLike(
          pgn: 0xFEF1,
          source: 0x00,
          data: Uint8List.fromList([0, 0x00, 0x50, 0, 0, 0, 0, 0]),
        ),
      );
      await _controller.close();
    });
  }
  @override
  Stream<_FrameReceivedLike> get frames => _controller.stream;
  @override
  void dispose() {}
}

Future<void> main() async {
  print('--- navigation_safety_core: example/can_bus_integration.dart ---\n');

  // ONCE, at startup, before a single frame is read. `.validated()`
  // probes every registered transform against a battery of baselines
  // and throws here — on the developer's machine, at wiring time — if
  // one relaxes a warning threshold or changes a field an override may
  // not change, on any probe. The battery is finite, so the drive path
  // still checks every config it derives; what it refuses there is
  // reported, not thrown.
  final overrides = VehicleThresholdOverrides.withKeiCarDefault();

  // PLACEHOLDER, not a bus sample and not a measurement: this example
  // decodes no ambient-air signal. Replace it with your vehicle's
  // ambient air temperature reading, or return `null` when you have
  // none. The fixed value is here only so the run shows an advisory.
  double? placeholderAmbientAirTempCelsius() => -1.0;

  final ecu = _MockEcu();
  await for (final advisory in safetyAdvisoryStream(
    ecu,
    readAmbientAirTempCelsius: placeholderAmbientAirTempCelsius,
    vehicleOverrides: overrides,
    vehicleClassToken: 'kei-car',
  )) {
    print('Advisory: $advisory');
  }
  ecu.dispose();
}
