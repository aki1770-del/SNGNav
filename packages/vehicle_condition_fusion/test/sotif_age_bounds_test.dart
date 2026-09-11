// SOTIF age bounds — the failure this suite exists to stop is PI-8:
// friction measured good on the valley floor, the road glazing at altitude, and
// the display still saying "we measured, and grip is fine".
//
// Everything here is about AGE. The absence-honesty contract (a missing signal
// is never a measurement) is already covered by honest_absence_test.dart and
// vss_adapter_test.dart and is NOT re-tested here.
import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

/// The ice verdict behind an update, read back through the same pure mapping
/// the processor used. `DrivingConditionAssessment` exposes `surfaceState`, not
/// `iceRisk` — this keeps the tri-state visible where it is the thing at issue.
bool? _iceRiskOf(VehicleConditionUpdate u) =>
    vehicleSignalsToWeatherCondition(u.signals!).iceRisk;

void main() {
  // A hand-wound clock. Tests that drive it pass watchdogInterval: zero so the
  // real timer never races the wound one.
  late DateTime now;
  DateTime clock() => now;
  setUp(() => now = DateTime(2026, 1, 15, 7, 0));

  group('INV-5 — no liveness claim before evidence', () {
    test('available is FALSE before a single signal has arrived', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );

      // A quiet bus is indistinguishable from a busy one at this instant. The
      // only honest answer is "no evidence yet".
      expect(fusion.available, isFalse);

      await fusion.dispose();
      await source.close();
    });
  });

  group('INV-3 — a stream that goes quiet stops counting as live', () {
    test('open, silent, no error and no done → unavailable', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      source.add(const VehicleConditionSignals(roadFriction: 0.8, speedKmh: 50));
      await pumpEventQueue();
      expect(fusion.available, isTrue, reason: 'a real frame arrived');
      seen.clear();

      // The transport does not error and does not end. It simply stops.
      now = now.add(kMaxFrameSilence + const Duration(seconds: 1));
      fusion.checkLiveness();
      await pumpEventQueue();

      expect(fusion.available, isFalse);
      expect(seen.single.isAvailable, isFalse);
      expect(seen.single.unavailableReason, contains('quiet'));

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('the watchdog fires on its own — nobody has to call it', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        maxFrameSilence: const Duration(milliseconds: 20),
        watchdogInterval: const Duration(milliseconds: 5),
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      // Real time, real timer, and not one frame ever delivered.
      await Future<void>.delayed(const Duration(milliseconds: 120));

      expect(seen, isNotEmpty,
          reason: 'a connected-but-silent bus must say so unprompted');
      expect(seen.last.isAvailable, isFalse);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('it announces once per quiet spell, not on every tick', () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      source.add(const VehicleConditionSignals(speedKmh: 50));
      await pumpEventQueue();
      seen.clear();

      now = now.add(const Duration(minutes: 5));
      fusion.checkLiveness();
      fusion.checkLiveness();
      fusion.checkLiveness();
      await pumpEventQueue();

      expect(seen, hasLength(1), reason: 'one quiet spell, one announcement');

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });
  });

  group('INV-4 — carry-forward is ASYMMETRIC (the load-bearing pair)', () {
    // Both halves drive the SAME field through the SAME mechanism for the SAME
    // elapsed time. Only the value differs, and so only the direction of the
    // inference differs. That is the whole claim.

    test('PI-8: a good-grip reading EXPIRES — no stale all-clear on the pass',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      // Valley floor, +3 °C: the ESC really did measure a good road.
      source.add(
          const VehicleConditionSignals(roadFriction: 0.85, airTempC: 3.0));
      await pumpEventQueue();
      expect(_iceRiskOf(seen.last), isFalse,
          reason: 'a FRESH measurement may say the road is not icy');

      // Climbing the pass. The thermometer keeps reporting and it is falling;
      // the ESC never re-sends friction, because nothing about it CHANGED as
      // far as the ECU is concerned.
      now = now.add(kMaxOptimisticSignalAge + const Duration(seconds: 30));
      source.add(const VehicleConditionSignals(airTempC: -4.0));
      await pumpEventQueue();

      expect(seen.last.isAvailable, isTrue, reason: 'the stream is still live');
      expect(_iceRiskOf(seen.last), isNot(false),
          reason: 'the all-clear was measured before the pass — it has expired');
      expect(_iceRiskOf(seen.last), isNull,
          reason: 'expiry degrades to UNKNOWN, never to a benign value');
      
      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('the mirror: an ICE warning is HELD over the same elapsed time',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      source.add(
          const VehicleConditionSignals(roadFriction: 0.12, airTempC: 3.0));
      await pumpEventQueue();
      expect(_iceRiskOf(seen.last), isTrue);
      expect(seen.last.assessment!.surfaceState, RoadSurfaceState.blackIce);

      // Exactly the elapsed time that expired the all-clear above.
      now = now.add(kMaxOptimisticSignalAge + const Duration(seconds: 30));
      source.add(const VehicleConditionSignals(airTempC: -4.0));
      await pumpEventQueue();

      expect(_iceRiskOf(seen.last), isTrue,
          reason: 'a held ice warning is defensible; a held all-clear is not');
      expect(seen.last.assessment!.surfaceState, RoadSurfaceState.blackIce,
          reason: 'she is still warned');

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('a hazard witness is not immortal either — it expires, slowly',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      source.add(
          const VehicleConditionSignals(roadFriction: 0.12, airTempC: 3.0));
      await pumpEventQueue();

      now = now.add(kMaxPessimisticSignalAge + const Duration(minutes: 1));
      source.add(const VehicleConditionSignals(airTempC: -4.0));
      await pumpEventQueue();

      expect(_iceRiskOf(seen.last), isNull,
          reason: '"we saw ice 16 minutes ago" is a claim about the past');
      // She is NOT left unwarned: the thermometer is still reporting -4 °C and
      // that alone holds the surface at blackIce. The stale reading went; the
      // warning stayed, because a FRESH signal supports it. This is the whole
      // point of the asymmetry — expiry removes claims, not protection.
      expect(seen.last.assessment!.surfaceState, RoadSurfaceState.blackIce);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('expiry nobody is TOLD about is not expiry', () async {
      // Found by this suite, not by review. `hasAnySignal` deliberately counts
      // only classification-relevant leaves, so a vehicle still sending speed
      // after every hazard signal has aged out produced NO emission at all —
      // and the caller went on displaying the assessment it already had. The
      // expiry was real internally and invisible to her, which is the same
      // outcome as no expiry.
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      source.add(const VehicleConditionSignals(roadFriction: 0.85));
      await pumpEventQueue();
      expect(seen.last.isAvailable, isTrue);

      // Only the heartbeat keeps coming. Nothing classification-relevant.
      now = now.add(kMaxOptimisticSignalAge + const Duration(seconds: 30));
      source.add(const VehicleConditionSignals(speedKmh: 55));
      await pumpEventQueue();

      expect(seen.last.isAvailable, isFalse,
          reason: 'the last all-clear aged out and she must be told');
      expect(seen.last.unavailableReason, contains('aged out'));
      expect(fusion.available, isFalse);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('loss of knowledge is NOT debounced — the floor is immediate',
        () async {
      // +2 °C with 70 %RH is radiative frost: blackIce, from two fresh leaves.
      // Let the humidity age out and the classifier can no longer justify the
      // call. The HysteresisFilter (window 3, threshold 2) would hold the
      // confident blackIce for two more frames; debouncing a LOSS OF KNOWLEDGE
      // is not flicker-suppression, it is two frames of stale claim.
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      source.add(
          const VehicleConditionSignals(airTempC: 2.0, humidityRH: 70.0));
      await pumpEventQueue();
      expect(seen.last.assessment!.surfaceState, RoadSurfaceState.blackIce);

      now = now.add(kMaxPessimisticSignalAge + const Duration(minutes: 1));
      source.add(const VehicleConditionSignals(airTempC: 2.0));
      await pumpEventQueue();

      expect(seen.last.assessment!.surfaceState, isNull,
          reason: 'unknown is taken in the SAME frame, not two frames later');

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });

    test('the asymmetry is a real ordering, not a coincidence', () {
      expect(kMaxOptimisticSignalAge, lessThan(kMaxPessimisticSignalAge));
    });
  });

  group('AoU-5 — the component can report the age of its own inputs', () {
    test('each field carries the time the VEHICLE sent it, not fusion time',
        () async {
      final source = StreamController<VehicleConditionSignals>();
      final fusion = VehicleConditionFusion.fromPartialFrames(
        partialFrames: source.stream,
        clock: clock,
        watchdogInterval: Duration.zero,
      );
      final seen = <VehicleConditionUpdate>[];
      final sub = fusion.conditions.listen(seen.add);

      final tFriction = now;
      source.add(const VehicleConditionSignals(roadFriction: 0.9));
      await pumpEventQueue();

      now = now.add(const Duration(seconds: 20));
      source.add(const VehicleConditionSignals(speedKmh: 60));
      await pumpEventQueue();

      final u = seen.last;
      // The fields of one snapshot do NOT share an age. Before this, an
      // integrator could not see that, so it could not bound it.
      expect(u.fieldObservedAt[VehicleSignalField.roadFriction], tFriction);
      expect(u.ageOf(VehicleSignalField.roadFriction, now),
          const Duration(seconds: 20));
      expect(u.ageOf(VehicleSignalField.speedKmh, now), Duration.zero);
      expect(u.ageOf(VehicleSignalField.humidityRH, now), isNull,
          reason: 'never sent → no age, not a zero age');
      expect(u.observedAt, now);

      await sub.cancel();
      await fusion.dispose();
      await source.close();
    });
  });

  group('THE WARN/ALL-CLEAR CONTRACT — n=1 may warn, an all-clear may not', () {
    // The safety contract for a partial vehicle. A warning and an all-clear are
    // not the same claim and do not cost the same when wrong, so they do not
    // carry the same evidentiary burden.

    test('a squall warns from the wiper ALONE — every other leaf dark', () {
      // The trim-dependent leaves are gone; this is what a thin vehicle gives.
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(wiperIntensity: 6),
        timestamp: DateTime(2026, 1, 15, 7, 0),
      );
      expect(c.intensity, PrecipitationIntensity.heavy);
      expect(c.visibilityMeters, lessThan(1000),
          reason: 'she is notified in a squall even from one leaf');
    });

    test('and from the rain sensor alone', () {
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(rainIntensity: 90),
        timestamp: DateTime(2026, 1, 15, 7, 0),
      );
      expect(c.intensity, PrecipitationIntensity.heavy);
      expect(c.visibilityMeters, lessThan(1000));
    });

    test('a sub-zero thermometer ALONE warns — n=1, every other leaf dark', () {
      // The thinnest vehicle there is. She is still notified.
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: -4.0),
        timestamp: DateTime(2026, 1, 15, 7, 0),
      );
      expect(DrivingConditionAssessment.fromCondition(c).surfaceState,
          RoadSurfaceState.blackIce);
    });

    test('radiative frost warns from temp + humidity — the leaf we never ask '
        'for', () {
      // +2 °C and 70 %RH is black ice BEFORE any wheel has slipped. The
      // humidity leaf is decodable and is NOT in the subscribed set (INV-1).
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(airTempC: 2.0, humidityRH: 70.0),
        timestamp: DateTime(2026, 1, 15, 7, 0),
      );
      expect(DrivingConditionAssessment.fromCondition(c).surfaceState,
          RoadSurfaceState.blackIce);
    });

    test('but an ALL-CLEAR needs a fresh measurement, not a thin one', () {
      // Wipers off is real evidence about precipitation and is honoured...
      final c = vehicleSignalsToWeatherCondition(
        const VehicleConditionSignals(wiperIntensity: 0),
        timestamp: DateTime(2026, 1, 15, 7, 0),
      );
      expect(c.intensity, PrecipitationIntensity.none);
      // ...but it says NOTHING about grip, and must not be allowed to.
      expect(c.iceRisk, isNull,
          reason: 'no friction signal is not an all-clear on ice');
    });

    test('an expired all-clear cannot be laundered back through the merge', () {
      final t0 = DateTime(2026, 1, 15, 7, 0);
      final expired = expireStaleSignals(
        const VehicleConditionSignals(roadFriction: 0.9, speedKmh: 50),
        observedAt: {
          VehicleSignalField.roadFriction: t0,
          VehicleSignalField.speedKmh:
              t0.add(kMaxOptimisticSignalAge + const Duration(seconds: 5)),
        },
        now: t0.add(kMaxOptimisticSignalAge + const Duration(seconds: 5)),
      );
      expect(expired.roadFriction, isNull);
      expect(expired.speedKmh, 50, reason: 'the heartbeat is still fresh');
      expect(
        vehicleSignalsToWeatherCondition(expired, timestamp: t0).iceRisk,
        isNull,
      );
    });
  });
}
