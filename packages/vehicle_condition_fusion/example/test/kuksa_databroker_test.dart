// Behavioural tests for the KUKSA-databroker bridge example.
//
// These exercise the SAME `bridgeVssFramesToFusion` wiring the runnable demo
// uses (and that a real `kuksaVssFrames(client)` would feed), but with
// hand-fed `Map<String, Object?>` frames shaped exactly like a decoded KUKSA
// `subscribe` yield — so they assert the load-bearing safety behaviours without
// a databroker. The surface debounce is pinned to threshold 1 so each frame
// commits its verdict, making the assertions deterministic.
import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart'
    show HysteresisFilter, RoadSurfaceState;
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

import '../kuksa_databroker.dart';

// VSS leaf-path keys, straight from the package (cannot drift from `fromVss`).
const _kFriction = VehicleConditionSignals.vssRoadFriction; // percent 0..100
const _kTcs = VehicleConditionSignals.vssTcsEngaged;
const _kTemp = VehicleConditionSignals.vssAirTemperature; // °C
const _kSpeed = VehicleConditionSignals.vssSpeed; // km/h

/// Run a list of partial VSS frames through the example bridge (debounce pinned
/// to commit-every-frame) and collect every emission. If [errorAfter] is true,
/// the source errors once the frames are exhausted (a simulated disconnect);
/// otherwise it ends cleanly.
Future<List<VehicleConditionUpdate>> _run(
  List<Map<String, Object?>> frames, {
  bool errorAfter = false,
}) async {
  Stream<Map<String, Object?>> source() async* {
    for (final f in frames) {
      yield f;
    }
    if (errorAfter) {
      throw StateError('databroker connection lost');
    }
  }

  final fusion = bridgeVssFramesToFusion(
    source(),
    // Nullable type argument: `null` is the honest not-measured surface state,
    // and a non-nullable filter throws inside `HysteresisFilter.add` when it
    // arrives. See the note on `bridgeVssFramesToFusion`.
    surfaceFilter: HysteresisFilter<RoadSurfaceState?>(threshold: 1),
  );
  final out = <VehicleConditionUpdate>[];
  final done = Completer<void>();
  StreamSubscription<VehicleConditionUpdate>? sub;
  sub = fusion.conditions.listen((u) {
    out.add(u);
    // Stop at the first unavailable marker (as the runnable demo does), so the
    // disconnect reason — not a trailing end-of-stream marker — is `out.last`.
    if (!u.isAvailable && !done.isCompleted) {
      done.complete();
      sub?.cancel();
    }
  });
  await done.future;
  await fusion.dispose();
  return out;
}

void main() {
  // The whiteout frames: friction collapses + TCS engages + sub-freezing temp.
  final icyWhiteout = <Map<String, Object?>>[
    {_kFriction: 95.0, _kTcs: false, _kTemp: -1.0, _kSpeed: 50.0},
    {_kFriction: 18.0, _kTcs: true, _kTemp: -6.0, _kSpeed: 25.0},
  ];

  test('icy sequence yields a black-ice (ice-risk) verdict', () async {
    final out = await _run(icyWhiteout);
    final assessments = out.where((u) => u.isAvailable).toList();
    expect(assessments, isNotEmpty);
    expect(assessments.last.assessment!.surfaceState, RoadSurfaceState.blackIce);
    expect(
      assessments.last.assessment!.advisoryMessage.toLowerCase(),
      contains('ice'),
    );
  });

  test('a garbage non-finite friction frame does NOT fabricate grip', () async {
    // The documented danger: a NaN friction would survive
    // `(NaN/100).clamp(0,1) == 1.0` and fabricate MAX grip — a fail-toward-safe
    // under-warn. The guard degrades it to `null` instead. Temp is held above
    // freezing so the verdict comes ONLY from real signals (the classifier
    // independently calls a sub-−3°C dry road black ice, which is not what this
    // test is about).
    //
    // With the friction reading gone, the surface is NOT measured, and
    // `DrivingConditionAssessment.fromCondition` documents its answer as `null`:
    // "when [condition] carries too little to classify … [surfaceState] and
    // [gripFactor] are null". An above-freezing air temperature does not
    // establish a dry road — it is equally consistent with wet, slush or
    // standing water. This test asserted `RoadSurfaceState.dry` until
    // 2026-08-18, which is the same absence-becomes-a-benign-verdict fabrication
    // the driving_weather 0.5.0 / snow_rendering 0.3.0 recall exists to end. The
    // assertion contradicted this test's own name.
    final out = await _run([
      {_kFriction: double.nan, _kTemp: 5.0, _kSpeed: 30.0},
    ]);
    final live = out.where((u) => u.isAvailable).toList();
    expect(live, isNotEmpty);
    // No fabricated friction value reached the snapshot (NOT 1.0, NOT anything).
    expect(live.last.signals!.roadFriction, isNull);
    // …so no ice verdict was invented from the garbage friction — and no DRY
    // verdict either. Unmeasured is reported as unmeasured.
    expect(live.last.assessment!.surfaceState, isNull);
    expect(live.last.assessment!.gripFactor, isNull);
  });

  test('garbage friction cannot ERASE a once-seen ice hazard', () async {
    // The driver-dangerous direction: on black ice, a corrupt NaN-friction
    // frame must NOT flip the verdict to a safe road. NaN → null → carry-forward
    // HOLDS the real 0.18, so the verdict stays black ice.
    final out = await _run([
      {_kFriction: 95.0, _kTcs: false, _kTemp: -1.0, _kSpeed: 50.0},
      {_kFriction: 18.0, _kTcs: true, _kTemp: -6.0, _kSpeed: 25.0}, // black ice
      {_kFriction: double.nan, _kSpeed: 20.0}, // garbage — must not clear it
    ]);
    final live = out.where((u) => u.isAvailable).toList();
    expect(live.last.signals!.roadFriction, closeTo(0.18, 1e-9)); // carried
    expect(live.last.assessment!.surfaceState, RoadSurfaceState.blackIce);
  });

  test('a partial (speed-only) frame carries a once-seen ice signal forward',
      () async {
    final out = await _run([
      {_kFriction: 95.0, _kTcs: false, _kTemp: -1.0, _kSpeed: 50.0},
      {_kFriction: 18.0, _kTcs: true, _kTemp: -6.0, _kSpeed: 25.0}, // black ice
      {_kSpeed: 20.0}, // ONLY speed re-sent — ice leaves NOT re-sent
    ]);
    final live = out.where((u) => u.isAvailable).toList();
    // The final, speed-only frame still reports black ice (friction/TCS held).
    expect(live.last.signals!.roadFriction, closeTo(0.18, 1e-9));
    expect(live.last.signals!.tcsEngaged, isTrue);
    expect(live.last.assessment!.surfaceState, RoadSurfaceState.blackIce);
  });

  test('a disconnect yields an honest UNKNOWN, never the stale ice verdict',
      () async {
    final out = await _run(icyWhiteout, errorAfter: true);
    // The last live emission was black ice…
    final live = out.where((u) => u.isAvailable).toList();
    expect(live.last.assessment!.surfaceState, RoadSurfaceState.blackIce);
    // …but the FINAL emission after the drop is an explicit unavailable marker,
    // carrying no assessment (the caller must not keep showing stale ice).
    expect(out.last.isAvailable, isFalse);
    expect(out.last.assessment, isNull);
    expect(out.last.unavailableReason, contains('databroker connection lost'));
  });
}
