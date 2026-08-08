// Runnable KUKSA-databroker bridge for `vehicle_condition_fusion`.
//
// This shows the ONE wiring an edge developer writes to drive the
// safety-calibrated fusion from a live Eclipse KUKSA databroker — and that the
// bridge is a four-line map chain, because the package's `fromVss` + the
// partial-frame carry-forward rail do the load-bearing work for you:
//
//   client.subscribe(paths)                         // Stream<Map<String,Datapoint>>
//     .map((u) => {for (final e in u.entries) e.key: e.value.value})  // decode → Object?
//     .map(VehicleConditionSignals.fromVss)         // typed snapshot, honest on garbage
//   → VehicleConditionFusion.fromPartialFrames(...)  // carry-forward + debounce + degrade
//
// ── HOW TO RUN ───────────────────────────────────────────────────────────────
//   From a clone of this repository (the package README has the `pub add`
//   on-ramp; `pub add` does NOT copy `example/` into your project):
//
//     cd packages/vehicle_condition_fusion/example
//     dart pub get
//     dart run kuksa_databroker.dart            # FAKE source — NO databroker needed
//     dart run kuksa_databroker.dart --live localhost:55555   # REAL KuksaClient
//
//   The DEFAULT run uses an in-process FAKE source shaped EXACTLY like the real
//   SDK `subscribe` yield (after `.value` decode), so it runs end-to-end on a
//   laptop with no broker and is what CI exercises. The `--live` path constructs
//   a real `KuksaClient` and dials the databroker; the real `kuksaVssFrames`
//   bridge below is COMPILE-CHECKED against the SDK either way.
//
// ⚠️ The fake drive is ILLUSTRATIVE / SYNTHETIC — hand-authored plausible VSS
//    values, NOT a recording of any real vehicle or any real storm.
import 'dart:async';
import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart'
    show DrivingConditionAssessment, HysteresisFilter, RoadSurfaceState;
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

// ════════════════════════════════════════════════════════════════════════════
// THE BRIDGE — the only code a real KUKSA user writes.
// ════════════════════════════════════════════════════════════════════════════

/// THE REAL KUKSA bridge: a live `KuksaClient.subscribe(...)` decoded to the
/// `Map<String, Object?>` frame shape `VehicleConditionSignals.fromVss` consumes.
///
/// `subscribe` yields a `Stream<Map<String, Datapoint>>` — one **partial frame**
/// per update cycle (only the leaves that changed are present; the first
/// emission carries the current value of every subscribed path). Decoding each
/// `Datapoint` to its scalar `.value` (a `bool` / `int` / `double`, or `null`
/// when the leaf is absent/None) is the whole adapter. No pre-merge here: the
/// partial frames flow straight to `fromPartialFrames`, which owns carry-forward.
///
/// This function is exercised only by `dart analyze` (compile-checked against
/// SDK 0.2.3 types) and by the `--live host:port` run — NOT by CI.
Stream<Map<String, Object?>> kuksaVssFrames(KuksaClient client) {
  return client
      .subscribe(VehicleConditionSignals.recognizedVssPaths)
      .map(
        (update) => {
          for (final entry in update.entries) entry.key: entry.value.value,
        },
      );
}

/// Wire ANY `Stream<Map<String, Object?>>` of **partial** VSS frames (the real
/// [kuksaVssFrames] above, or the fake source below) into the fusion.
///
/// `subscribe` is a partial-frame transport, so this uses the
/// `fromPartialFrames` rail: it carries the last-known value of any leaf a frame
/// did not re-send (`VehicleConditionSignals.carriedForwardOnto`) BEFORE running
/// the identical fusion pipeline — so a once-seen ice signal persists across
/// later partial frames instead of silently dropping to `null` (the under-warn
/// gap). Do NOT pre-accumulate the frames yourself; the rail owns that.
///
/// An explicit-None leaf (a real broker re-sends a leaf whose value went invalid
/// → `Datapoint.value` is `null`) reads on this rail as "unchanged → carry
/// forward the last value", NOT a fresh unknown — the fail-safe direction for a
/// persisting hazard, consistent with the documented-primary `subscribe` rail.
///
/// [surfaceFilter] is exposed only so the test can pin the debounce
/// (threshold 1 = commit every frame) for deterministic assertions; production
/// callers leave it null to get the realistic anti-flicker default.
VehicleConditionFusion bridgeVssFramesToFusion(
  Stream<Map<String, Object?>> vssFrames, {
  HysteresisFilter<RoadSurfaceState>? surfaceFilter,
}) {
  return VehicleConditionFusion.fromPartialFrames(
    partialFrames: vssFrames.map(VehicleConditionSignals.fromVss),
    surfaceFilter: surfaceFilter,
  );
}

// ════════════════════════════════════════════════════════════════════════════
// ENTRY POINT.
// ════════════════════════════════════════════════════════════════════════════

Future<void> main(List<String> args) async {
  final liveIndex = args.indexOf('--live');
  final live = liveIndex >= 0;

  stdout
    ..writeln('=' * 78)
    ..writeln('vehicle_condition_fusion — KUKSA databroker bridge')
    ..writeln('=' * 78);

  if (live) {
    final endpoint = liveIndex + 1 < args.length ? args[liveIndex + 1] : '';
    await _runLive(endpoint);
    return;
  }

  stdout
    ..writeln('SOURCE: in-process FAKE (no databroker). The frames below are')
    ..writeln('shaped EXACTLY like a real `client.subscribe(...).map(.value)`')
    ..writeln(
      'yield — partial VSS frames of {leaf-path: decoded-scalar}. To go',
    )
    ..writeln('live, swap the fake for `kuksaVssFrames(client)` (see --live).')
    ..writeln('⚠️ SYNTHETIC hand-authored values — NOT a real vehicle/storm.')
    ..writeln(
      'Steps marked "(held)" = the anti-flicker debounce LAGS onset by one frame',
    )
    ..writeln(
      '  (fail-safe on clearing) — a stale verdict beside fresh inputs by design,',
    )
    ..writeln('  NOT an under-warn.')
    ..writeln('=' * 78);

  // ── Demo 1 · a realistic icy drive, ending with a clean end-of-stream ──────
  stdout
    ..writeln('')
    ..writeln(
      'DEMO 1 — escalating icy drive  (carry-forward + garbage-frame honesty)',
    )
    ..writeln('WATCH: once black ice appears, the LAST TWO frames re-send only')
    ..writeln(
      '  speed / a non-finite friction — yet fric still reads 0.18 (carried,',
    )
    ..writeln('  never a fabricated 1.00) and the verdict HOLDS at black ice.')
    ..writeln('-' * 78);
  await _driveAndPrint(bridgeVssFramesToFusion(_fakeIcyDriveFrames()));

  // ── Demo 2 · a mid-drive databroker DISCONNECT → honest UNKNOWN ────────────
  stdout
    ..writeln('')
    ..writeln(
      'DEMO 2 — mid-drive databroker DISCONNECT  (honest UNKNOWN, never stale)',
    )
    ..writeln(
      'WATCH: the connection drops while on black ice — the fusion reports',
    )
    ..writeln('  an explicit UNAVAILABLE, NOT the now-stale black-ice verdict.')
    ..writeln('-' * 78);
  await _driveAndPrint(bridgeVssFramesToFusion(_fakeDisconnectFrames()));

  stdout
    ..writeln('')
    ..writeln('=' * 78)
    ..writeln(
      'Done. An example lowers the adoption BARRIER; it is not adoption.',
    )
    ..writeln('=' * 78);
}

/// Live path: construct a REAL [KuksaClient] and drive the SAME bridge.
/// Not run by CI; requires a reachable databroker.
Future<void> _runLive(String endpoint) async {
  final parts = endpoint.split(':');
  final host = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0] : 'localhost';
  final port = parts.length > 1 ? int.tryParse(parts[1]) ?? 55555 : 55555;
  stdout
    ..writeln('SOURCE: LIVE KuksaClient(host: $host, port: $port)')
    ..writeln(
      'Subscribing to: ${VehicleConditionSignals.recognizedVssPaths.join(', ')}',
    )
    ..writeln('=' * 78);

  final client = KuksaClient(host: host, port: port);
  await client.connect();
  try {
    // The ONLY substitution vs. the fake demo: real frames from the databroker.
    await _driveAndPrint(bridgeVssFramesToFusion(kuksaVssFrames(client)));
  } finally {
    await client.dispose();
  }
}

/// Subscribe to one fusion's [VehicleConditionFusion.conditions] stream and
/// print each emission until the stream ends. Completes when the fusion has
/// emitted its honest end-of-stream / disconnect `unavailable` marker.
Future<void> _driveAndPrint(VehicleConditionFusion fusion) async {
  final done = Completer<void>();
  var step = 0;
  StreamSubscription<VehicleConditionUpdate>? sub;
  sub = fusion.conditions.listen((update) {
    if (update.isAvailable) {
      stdout.writeln(_describe(++step, update));
    } else {
      // Honest degradation: NO live signals → an explicit "unavailable" marker.
      // Never a stale verdict, never a fabricated road. The caller would keep
      // its own offline-first default and stop claiming "live".
      stdout.writeln('     └─ UNAVAILABLE → ${update.unavailableReason}');
      if (!done.isCompleted) done.complete();
    }
  });
  await done.future;
  await sub.cancel();
  await fusion.dispose();
}

/// One glanceable two-line record per emission (each ≤80 cols):
///  line 1 — the carried-forward input signals + the debounced surface verdict;
///  line 2 — grip + the advisory message.
String _describe(int step, VehicleConditionUpdate update) {
  final s = update.signals!;
  final a = update.assessment!;

  // Re-derive the FRESH candidate (pure, read-only — never mutates the fusion)
  // to detect a debounce-held step: when the freshly computed surface differs
  // from the displayed (debounced) surface, the default HysteresisFilter
  // (window 3 / threshold 2) is holding the prior verdict against fresh inputs.
  // The hold LAGS onset by one frame by design (documented anti-flicker) and
  // fails safe on CLEARING — so a held step is NOT an under-warn; the marker
  // makes that legible rather than mistakable for the fusion under-warning.
  // `OrNull` is the honest entry point: it abstains when no hazard is asserted
  // and the ambient temperature was never measured. It cannot be null here —
  // the fusion only emitted an assessment because it was not — so the fallback
  // is the displayed verdict itself (i.e. "no fresh disagreement").
  final fresh = vehicleSignalsToWeatherConditionOrNull(s);
  final candidate = fresh == null
      ? null
      : DrivingConditionAssessment.fromCondition(fresh);
  final held = candidate != null && candidate.surfaceState != a.surfaceState;
  final marker = held ? ' (held)' : '';

  final fric = s.roadFriction == null
      ? '  ?  '
      : s.roadFriction!.toStringAsFixed(2).padLeft(5);
  final temp = s.airTempC == null
      ? '   ? '
      : '${s.airTempC!.toStringAsFixed(0)}°C'.padLeft(5);
  final tcs = (s.tcsEngaged ?? false) ? 'ON ' : 'off';
  final wiper = (s.wiperIntensity ?? 0).toString();

  final line1 =
      'step ${step.toString().padLeft(2)}  '
      'fric=$fric temp=$temp tcs=$tcs wiper=$wiper'
      '  →  ${a.surfaceState.name}$marker';
  final line2 =
      '          grip=${a.gripFactor.toStringAsFixed(2)}  '
      '“${a.advisoryMessage}”';
  return '$line1\n$line2';
}

// ════════════════════════════════════════════════════════════════════════════
// FAKE SOURCE — shaped EXACTLY like the real SDK `subscribe` yield.
//
//   replace this fake with:  kuksaVssFrames(client)   (the real bridge above)
//
// Each yielded map is one PARTIAL frame of {VSS-leaf-path: decoded-scalar} —
// precisely what `client.subscribe(paths).map((u) => {for (e in u.entries)
// e.key: e.value.value})` produces. A `Datapoint.value` is a bool / int /
// double, or null when the leaf is absent/None — so these fakes use exactly
// those Dart scalar types (and a deliberate non-finite double for the garbage
// frame). Friction is a VSS PERCENT (0–100); fromVss divides by 100.
// ════════════════════════════════════════════════════════════════════════════

// Short aliases for the VSS leaf-path keys, straight from the package so the
// fake can never drift from the paths `fromVss` actually reads.
const _kFriction = VehicleConditionSignals.vssRoadFriction; // percent 0..100
const _kTcs = VehicleConditionSignals.vssTcsEngaged;
const _kAbs = VehicleConditionSignals.vssAbsEngaged;
const _kEsc = VehicleConditionSignals.vssEscEngaged;
const _kTemp = VehicleConditionSignals.vssAirTemperature; // °C
const _kSpeed = VehicleConditionSignals.vssSpeed; // km/h
const _kWiper = VehicleConditionSignals.vssWiperIntensity; // setpoint, no max
const _kRain = VehicleConditionSignals.vssRainIntensity; // percent 0..100

/// SYNTHETIC partial-frame trace: dry → snow → WHITEOUT black ice, then a
/// speed-only frame (carry-forward HOLDS the ice) and a garbage non-finite
/// friction frame (no fabricated max grip), then the stream ENDS cleanly.
Stream<Map<String, Object?>> _fakeIcyDriveFrames() async* {
  const step = Duration(milliseconds: 120);

  // Frame 1 — first emission carries every subscribed leaf (dry, cold, clear).
  // Friction is sent as an `int` (95): VSS `ESC.RoadFriction.MostProbable` is a
  // `uint8`, so a real KuksaClient decodes `Datapoint.value` to a Dart int —
  // `fromVss` int-coerces it (int 95 and double 95.0 classify identically).
  yield {
    _kFriction: 95, // → 0.95 grip
    _kTcs: false,
    _kAbs: false,
    _kEsc: false,
    _kTemp: -1.0,
    _kSpeed: 50.0,
    _kWiper: 0,
    _kRain: 0,
  };
  await Future<void>.delayed(step);

  // Frame 2 — partial: ONLY speed changed. Still dry (everything else carried).
  yield {_kSpeed: 55.0};
  await Future<void>.delayed(step);

  // Frame 3 — snow onset: friction drops, wipers + rain sensor rise, road cools.
  yield {_kFriction: 45, _kWiper: 3, _kRain: 40, _kTemp: -3.0, _kSpeed: 40.0};
  await Future<void>.delayed(step);

  // Frame 4 — partial: snowfall intensifies (wiper/rain up); friction/temp held.
  yield {_kWiper: 4, _kRain: 50, _kSpeed: 35.0};
  await Future<void>.delayed(step);

  // Frame 5 — WHITEOUT: friction collapses to 0.18, TCS engages on a −6°C
  // surface, wiper maxes, rain pegs near 80% → black ice.
  yield {
    _kFriction: 18, // int wire type (uint8), like a real broker
    _kTcs: true,
    _kWiper: 5,
    _kRain: 80,
    _kTemp: -6.0,
    _kSpeed: 25.0,
  };
  await Future<void>.delayed(step);

  // Frame 6 — partial: ONLY speed changed. The ice/whiteout leaves are NOT
  // re-sent — carry-forward HOLDS them, so this STILL reports black ice. This
  // is the load-bearing safety property of the partial-frame rail, made visible.
  yield {_kSpeed: 20.0};
  await Future<void>.delayed(step);

  // Frame 7 — GARBAGE: a non-finite friction leaf (a corrupt update). fromVss
  // degrades a NaN to `null` (it does NOT survive `(NaN/100).clamp(0,1)==1.0`
  // and fabricate MAX grip — the dangerous under-warn). null then means
  // "unchanged" to carry-forward, which HOLDS the real 0.18 → STILL black ice.
  yield {_kFriction: double.nan, _kSpeed: 18.0};
  await Future<void>.delayed(step);

  // Stream ends → the fusion emits its honest end-of-stream `unavailable`.
}

/// SYNTHETIC partial-frame trace that escalates to black ice, then the
/// databroker connection DROPS mid-drive (a stream error) — the fusion must
/// report an honest UNKNOWN, never the last (now-stale) black-ice verdict.
Stream<Map<String, Object?>> _fakeDisconnectFrames() async* {
  const step = Duration(milliseconds: 120);

  yield {
    _kFriction: 92, // int wire type (uint8), like a real broker
    _kTcs: false,
    _kTemp: -1.0,
    _kSpeed: 60.0,
    _kWiper: 0,
    _kRain: 0,
  };
  await Future<void>.delayed(step);

  // Hit black ice.
  yield {_kFriction: 18, _kTcs: true, _kTemp: -6.0, _kSpeed: 30.0};
  await Future<void>.delayed(step);
  yield {_kSpeed: 25.0}; // carry-forward holds the ice
  await Future<void>.delayed(step);

  // The databroker connection drops. A real `subscribe` stream errors here;
  // the fusion surfaces `unavailable(reason)` and never re-emits the stale ice.
  throw const SocketException('databroker connection lost (simulated)');
}
