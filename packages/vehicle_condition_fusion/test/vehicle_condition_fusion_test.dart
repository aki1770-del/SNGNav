/// vehicle_condition_fusion tests — PURE DART.
///
/// The whole point of this package is testability WITHOUT a databroker: every
/// test below drives the fusion from a plain
/// `StreamController<VehicleConditionSignals>` and direct
/// `VehicleConditionSignals(...)` construction. There is intentionally NO
/// `kuksa_dart_sdk` import, NO protobuf, NO running databroker anywhere in this
/// file — that absence IS the contract.
library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

/// Pure-Dart event-loop pump (no flutter_test dependency). Flushes pending
/// microtasks + events so broadcast-stream emissions are delivered.
Future<void> pumpEventQueue([int times = 20]) async {
  if (times == 0) return;
  await Future<void>.delayed(Duration.zero);
  return pumpEventQueue(times - 1);
}

void main() {
  group('vehicleSignalsToWeatherCondition + assessment fusion (deterministic)',
      () {
    DrivingConditionAssessment assess(VehicleConditionSignals s) =>
        DrivingConditionAssessment.fromCondition(
          vehicleSignalsToWeatherCondition(s),
        );

    test('low road friction → black ice + ice advisory', () {
      final a = assess(const VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: -5.0,
      ));
      expect(a.surfaceState, RoadSurfaceState.blackIce);
      expect(a.advisoryMessage.toLowerCase(), contains('ice'));
    });

    test('heavy snowfall, adequate grip → compacted snow + fog wall', () {
      final a = assess(const VehicleConditionSignals(
        roadFriction: 0.5, // not below the icy threshold
        wiperIntensity: 5, // heavy
        airTempC: -5.0,
      ));
      expect(a.surfaceState, RoadSurfaceState.compactedSnow);
      // heavy precip → 300 m visibility proxy → strong fog opacity
      expect(a.visibility!.opacity, greaterThan(0.5));
    });

    test('moderate rain, warm, good grip → wet + mild fog', () {
      final a = assess(const VehicleConditionSignals(
        roadFriction: 0.9,
        wiperIntensity: 4, // moderate
        airTempC: 8.0,
      ));
      expect(a.surfaceState, RoadSurfaceState.wet);
      // moderate precip → 800 m → some, but not heavy, fog
      expect(a.visibility!.opacity, greaterThan(0.0));
      expect(a.visibility!.opacity, lessThan(0.5));
    });

    test('TCS engaged on a COLD road → ice risk → black ice', () {
      final a = assess(const VehicleConditionSignals(
        roadFriction: 0.6, // not itself below the icy threshold
        tcsEngaged: true,
        airTempC: 0.0,
      ));
      expect(a.surfaceState, RoadSurfaceState.blackIce);
    });

    test('TCS engaged on a WARM road → NOT ice (aquaplaning, not freezing)',
        () {
      final a = assess(const VehicleConditionSignals(
        tcsEngaged: true,
        wiperIntensity: 4, // moderate rain
        airTempC: 12.0,
      ));
      expect(a.surfaceState, isNot(RoadSurfaceState.blackIce));
    });

    test('dry, warm, full grip, no precip → dry + normal advisory', () {
      final a = assess(const VehicleConditionSignals(
        roadFriction: 0.95,
        wiperIntensity: 0,
        airTempC: 5.0,
      ));
      expect(a.surfaceState, RoadSurfaceState.dry);
    });

    test('missing temperature + low friction → still black ice '
        '(friction is a direct measurement)', () {
      final a = assess(const VehicleConditionSignals(roadFriction: 0.2));
      expect(a.surfaceState, RoadSurfaceState.blackIce);
    });
  });

  group('VehicleConditionFusion (injected snapshot stream)', () {
    test('emits a fused live assessment from a snapshot', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(signals: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      source.add(const VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: -5.0,
      ));
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isTrue);
      expect(results.single.live, isTrue);
      expect(
        results.single.assessment!.surfaceState,
        RoadSurfaceState.blackIce,
      );

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('HysteresisFilter debounces a single-frame surface flip', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(signals: source.stream);
      final surfaces = <RoadSurfaceState?>[];
      final sub = fusion.conditions.listen((u) {
        if (u.assessment != null) surfaces.add(u.assessment!.surfaceState);
      });

      // dry baseline
      source.add(const VehicleConditionSignals(
        roadFriction: 0.95,
        airTempC: 5.0,
        wiperIntensity: 0,
      ));
      await pumpEventQueue();
      // one icy reading (should be HELD — below the hysteresis threshold)
      source.add(const VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: 5.0,
        wiperIntensity: 0,
      ));
      await pumpEventQueue();
      // a second icy reading (now persists → flip allowed)
      source.add(const VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: 5.0,
        wiperIntensity: 0,
      ));
      await pumpEventQueue();

      // dry, then HELD dry (flicker suppressed), then black ice.
      expect(surfaces, [
        RoadSurfaceState.dry,
        RoadSurfaceState.dry,
        RoadSurfaceState.blackIce,
      ]);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('does NOT emit when no signal is present (never fabricates)',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(signals: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      source.add(const VehicleConditionSignals()); // all-null snapshot
      source.add(const VehicleConditionSignals()); // still nothing real
      await pumpEventQueue();

      expect(results, isEmpty);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('honest fallback: a stream ERROR surfaces unavailable, no throw',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(signals: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      source.addError('connection refused');
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isFalse);
      expect(results.single.assessment, isNull);
      expect(fusion.available, isFalse);
      expect(results.single.unavailableReason, contains('connection refused'));

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('honest fallback: stream DONE surfaces unavailable', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(signals: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      await source.close(); // source stream ends
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isFalse);
      expect(results.single.unavailableReason, contains('ended'));

      await sub.cancel();
      await fusion.dispose();
    });
  });

  group('partial-frame carry-forward vs complete-snapshot divergence', () {
    // These two tests pin the load-bearing safety divergence between the rails.
    // Both inject a no-debounce HysteresisFilter (threshold: 1) so a single
    // frame flips the surface immediately — isolating the carry-forward
    // behaviour from the orthogonal hysteresis debounce, which would otherwise
    // hold the surface for an extra reading and mask the divergence.

    test(
        'fromPartialFrames: a later PARTIAL frame HOLDS a once-seen ice signal '
        '(no under-warn)', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        surfaceFilter: HysteresisFilter<RoadSurfaceState?>(threshold: 1),
      );
      final updates = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(updates.add);

      // frame1: a complete-enough first frame asserting black ice.
      source.add(const VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: -5.0,
      ));
      await pumpEventQueue();
      expect(updates.last.assessment!.surfaceState, RoadSurfaceState.blackIce);

      // frame2: a PARTIAL frame — only the wiper re-sent; roadFriction and
      // airTempC are NOT re-sent (null = "unchanged" on this transport).
      source.add(const VehicleConditionSignals(wiperIntensity: 5));
      await pumpEventQueue();

      // Ice is STILL HELD: carry-forward restored the friction/temp, so the
      // partial frame does not under-warn while the hazard persists.
      expect(updates.last.assessment!.surfaceState, RoadSurfaceState.blackIce);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test(
        'default constructor: the SAME two as COMPLETE snapshots — a null in '
        'the second is "unknown now", so it does NOT stale-over-warn', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(
        signals: source.stream,
        surfaceFilter: HysteresisFilter<RoadSurfaceState?>(threshold: 1),
      );
      final updates = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(updates.add);

      // frame1: complete snapshot asserting black ice (same as above).
      source.add(const VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: -5.0,
      ));
      await pumpEventQueue();
      expect(updates.last.assessment!.surfaceState, RoadSurfaceState.blackIce);

      // frame2: a COMPLETE snapshot where roadFriction (and airTempC) are
      // GENUINELY null — the source is stating the ice signal is no longer
      // valid, not merely "not re-sent".
      source.add(const VehicleConditionSignals(wiperIntensity: 5));
      await pumpEventQueue();

      // The complete-snapshot rail correctly treats null as "unknown now" and
      // does NOT carry the ice forward: the second yields NOT black ice.
      expect(
        updates.last.assessment!.surfaceState,
        isNot(RoadSurfaceState.blackIce),
      );

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('fromPartialFrames honest degradation: stream ERROR → unavailable',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion =
          VehicleConditionFusion.fromPartialFrames(partialFrames: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      source.addError('broker drop');
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isFalse);
      expect(fusion.available, isFalse);
      expect(results.single.unavailableReason, contains('broker drop'));

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('fromPartialFrames never fabricates: empty frames → no emit',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion =
          VehicleConditionFusion.fromPartialFrames(partialFrames: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      source.add(const VehicleConditionSignals()); // empty partial frame
      source.add(const VehicleConditionSignals()); // still nothing real
      await pumpEventQueue();

      expect(results, isEmpty);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('carriedForwardOnto: per-field — non-null wins, null carries forward',
        () {
      const previous = VehicleConditionSignals(
        roadFriction: 0.2,
        airTempC: -5.0,
        speedKmh: 40.0,
      );
      const partial = VehicleConditionSignals(
        wiperIntensity: 5, // new
        airTempC: -8.0, // overrides the carried value
        // roadFriction & speedKmh NOT re-sent → carried forward
      );

      final merged = partial.carriedForwardOnto(previous);

      expect(merged.roadFriction, 0.2); // carried forward
      expect(merged.speedKmh, 40.0); // carried forward
      expect(merged.wiperIntensity, 5); // new value
      expect(merged.airTempC, -8.0); // newer value wins over carried
      expect(merged.tcsEngaged, isNull); // never seen by either → still null
    });
  });

  group('SDK-free mock seam', () {
    test('a one-line mock — no SDK, no protobuf, no databroker — drives fusion',
        () async {
      // The entire mock: a direct const construction. No Datapoint, no
      // generated protobuf types, no databroker connection.
      const mock = VehicleConditionSignals(roadFriction: 0.2, airTempC: -5.0);
      expect(mock.hasAnySignal, isTrue);

      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion(signals: source.stream);
      final results = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(results.add);

      source.add(mock);
      await pumpEventQueue();

      expect(results.single.assessment!.surfaceState,
          RoadSurfaceState.blackIce);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('equatable value semantics on the snapshot', () {
      const a = VehicleConditionSignals(roadFriction: 0.2, airTempC: -5.0);
      const b = VehicleConditionSignals(roadFriction: 0.2, airTempC: -5.0);
      const c = VehicleConditionSignals(roadFriction: 0.9, airTempC: -5.0);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
