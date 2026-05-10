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
//   j1939.J1939Ecu.events  ──► PGN decode (here, for J1939/71 vehicle
//                              speed and engine coolant temperature)
//                          ──► DrivingContext mapping
//                          ──► NavigationSafetyConfig
//                              .forProfileWithContext
//                          ──► AlertExplainer.explain(...)
//                          ──► driver-facing advisory string
//
// The mapping below uses two J1939/71 PGNs as illustrative anchors:
//
//   * 0xFEF1 — Cruise Control / Vehicle Speed (CCVS1).
//     Byte offset 1..2 = wheel-based vehicle speed, 1/256 km/h per bit.
//   * 0xFEEE — Engine Temperature 1 (ET1).
//     Byte offset 0 = engine coolant temperature, 1 °C per bit, offset −40.
//
// Real integrations should consult SAE J1939/71 for the full SPN /
// PGN catalog and apply the same composition pattern to other
// vehicle-bus signals (wiper status, headlamp state, ambient air
// temperature, ABS / TCS engagement, and so on).
//
// To run on a development host without a real CAN bus, see the j1939
// package README for `vcan` setup. This file is illustrative — the
// composition pattern is the load-bearing part, not the specific PGN
// payload decoder.
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

/// ET1 PGN 0xFEEE — engine coolant temperature in °C.
double? decodeCoolantTempCelsius(_FrameReceivedLike frame) {
  if (frame.pgn != 0xFEEE || frame.data.isEmpty) return null;
  return frame.data[0] - 40.0;
}

// ── DrivingContext bridge ────────────────────────────────────────────

/// Builds a [DrivingContext] from the most-recent vehicle-bus samples.
/// Engine coolant temperature is used here as a proxy for ambient
/// temperature once the engine is cold-started; production code should
/// prefer a dedicated ambient-air PGN where available.
DrivingContext driveContextFromCanSamples({
  required double speedKmh,
  required double coolantTempCelsius,
  double humidityRH = 0.85,
  Duration timeSincePrecipitation = const Duration(minutes: 30),
}) {
  return DrivingContext(
    speedMps: speedKmh / 3.6,
    humidityRH: humidityRH,
    ambientTempCelsius: coolantTempCelsius,
    timeSincePrecipitation: timeSincePrecipitation,
  );
}

// ── Composition: vehicle-CAN → safety advisory ───────────────────────

/// Listens for J1939 frames, builds a [DrivingContext] from the latest
/// speed and coolant samples, and yields the advisory action an app
/// can surface to the driver. Profile is fixed here for clarity; in
/// production it comes from the active driver session.
Stream<String> safetyAdvisoryStream(_J1939EcuLike ecu) async* {
  double? lastSpeedKmh;
  double? lastCoolantC;
  const profile = DriverProfile.snowZoneExperienced;

  await for (final frame in ecu.frames) {
    final speed = decodeWheelSpeedKmh(frame);
    if (speed != null) lastSpeedKmh = speed;
    final coolant = decodeCoolantTempCelsius(frame);
    if (coolant != null) lastCoolantC = coolant;

    if (lastSpeedKmh == null || lastCoolantC == null) continue;

    final ctx = driveContextFromCanSamples(
      speedKmh: lastSpeedKmh,
      coolantTempCelsius: lastCoolantC,
    );
    final config = NavigationSafetyConfig.forProfileWithContext(
      profile,
      context: ctx,
    );

    if (lastCoolantC <= config.warningTemperatureCelsius) {
      final explainer = AlertExplainer.forConditionAndProfile(
        RoadSurfaceCondition.ice,
        profile,
      );
      yield explainer.action;
    }
  }
}

// ── Local mock for analyzer-only runs ────────────────────────────────

/// Synthetic ECU that emits one warm-up sample then one cold-cabin
/// sample. Replace with `J1939Ecu.create(...)` from the j1939 package
/// in production.
class _MockEcu implements _J1939EcuLike {
  final _controller = StreamController<_FrameReceivedLike>();
  _MockEcu() {
    Future<void>.microtask(() async {
      _controller
        ..add(
          _FrameReceivedLike(
            pgn: 0xFEF1,
            source: 0x00,
            data: Uint8List.fromList([0, 0x00, 0x50, 0, 0, 0, 0, 0]),
          ),
        )
        ..add(
          _FrameReceivedLike(
            pgn: 0xFEEE,
            source: 0x00,
            data: Uint8List.fromList([35, 0, 0, 0, 0, 0, 0, 0]),
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
  final ecu = _MockEcu();
  await for (final advisory in safetyAdvisoryStream(ecu)) {
    print('Advisory: $advisory');
  }
  ecu.dispose();
}
