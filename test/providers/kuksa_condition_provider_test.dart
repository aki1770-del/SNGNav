/// KuksaConditionProvider unit/integration tests.
///
/// Drives the provider from an INJECTED signal stream of mock [Datapoint]s —
/// no running databroker required — and asserts the deterministic VSS →
/// driving_conditions fusion, the HysteresisFilter debounce, the partial-update
/// merge, and the honest no-broker / stream-error fallback (never fabricated).
library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kuksa_dart_sdk/kuksa_dart_sdk.dart';
// The SDK 0.2.3 public API exposes Datapoint only as a value RECEIVED from the
// client (its `raw` is a generated protobuf message that is not re-exported), so
// to construct mock Datapoints for injection we reach into the generated types.
// ignore: implementation_imports
import 'package:kuksa_dart_sdk/src/generated/kuksa/val/v2/types.pb.dart' as pb;
import 'package:sngnav_snow_scene/providers/kuksa_condition_provider.dart';
// The calibrated fusion now lives ONCE in the package; the app file is a thin
// KUKSA adapter (vehicleSignalsFromDatapoints) over it. The types and the
// deterministic mapping under test come from the package.
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

// --- mock Datapoint builders (the only place that touches generated types) ---

Datapoint _floatDp(String path, double v) =>
    Datapoint(raw: pb.Datapoint(value: pb.Value(float: v)), path: path);

Datapoint _boolDp(String path, bool v) =>
    Datapoint(raw: pb.Datapoint(value: pb.Value(bool_12: v)), path: path);

Datapoint _intDp(String path, int v) =>
    Datapoint(raw: pb.Datapoint(value: pb.Value(int32: v)), path: path);

Datapoint _valuelessDp(String path) => Datapoint(raw: pb.Datapoint(), path: path);

void main() {
  group('vehicleSignalsFromDatapoints (KUKSA decode adapter)', () {
    test('decodes mock Datapoints to typed fields', () {
      final signals = vehicleSignalsFromDatapoints({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0),
        kTcsIsEngaged: _boolDp(kTcsIsEngaged, true),
        kAbsIsEngaged: _boolDp(kAbsIsEngaged, false),
        kWiperFrontIntensity: _intDp(kWiperFrontIntensity, 5),
        kRaindetectionIntensity: _intDp(kRaindetectionIntensity, 80),
        kAirTemperature: _floatDp(kAirTemperature, -6.0),
        kVehicleSpeed: _floatDp(kVehicleSpeed, 42.0),
      });

      // VSS ships friction as PERCENT (0-100); the field is 0.0-1.0.
      expect(signals.roadFriction, closeTo(0.2, 1e-4));
      expect(signals.tcsEngaged, isTrue);
      expect(signals.absEngaged, isFalse);
      expect(signals.wiperIntensity, 5);
      expect(signals.rainIntensity, 80);
      expect(signals.airTempC, closeTo(-6.0, 1e-4));
      expect(signals.speedKmh, closeTo(42.0, 1e-4));
      expect(signals.hasAnySignal, isTrue);
    });

    test('a real ESC black-ice reading crosses the icy threshold', () {
      // An ESC on black ice emits about 18 PERCENT. Decoded without the unit
      // conversion that is 18.0, and 18.0 < 0.3 is false, so the friction limb
      // never fires.
      final signals = vehicleSignalsFromDatapoints({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 18.0),
      });

      expect(signals.roadFriction, closeTo(0.18, 1e-4));
      expect(signals.roadFriction! < 0.3, isTrue,
          reason: 'black ice at 18 percent must read as icy');
    });

    test('absent / value-less signals decode to null (never guessed)', () {
      final signals = vehicleSignalsFromDatapoints({
        kRoadFrictionMostProbable: _valuelessDp(kRoadFrictionMostProbable),
        // everything else simply absent from the map
      });
      expect(signals.roadFriction, isNull);
      expect(signals.tcsEngaged, isNull);
      expect(signals.airTempC, isNull);
      expect(signals.hasAnySignal, isFalse);
    });
  });

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

  group('KuksaConditionProvider (injected stream)', () {
    test('emits a fused live assessment from a snapshot', () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      source.add({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0),
        kAirTemperature: _floatDp(kAirTemperature, -5.0),
      });
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isTrue);
      expect(results.single.live, isTrue);
      expect(
        results.single.assessment!.surfaceState,
        RoadSurfaceState.blackIce,
      );

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });

    test('merges partial updates into a running snapshot', () async {
      final source = StreamController<Map<String, Datapoint>>();
      // No-debounce filter so this test isolates the MERGE behaviour from the
      // hysteresis hold (debounce is covered by its own test below).
      final provider = KuksaConditionProvider(
        updates: source.stream,
        surfaceFilter: HysteresisFilter<RoadSurfaceState>(
          windowSize: 1,
          threshold: 1,
        ),
      );
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      // First: friction + temp.
      source.add({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 50.0),
        kAirTemperature: _floatDp(kAirTemperature, -5.0),
      });
      await pumpEventQueue();
      // Then: only the wiper changes (partial update, as KUKSA subscribe sends).
      source.add({kWiperFrontIntensity: _intDp(kWiperFrontIntensity, 5)});
      await pumpEventQueue();

      // The latest update sees BOTH the carried friction/temp AND the new wiper.
      final last = results.last;
      expect(last.signals!.roadFriction, closeTo(0.5, 1e-4));
      expect(last.signals!.airTempC, closeTo(-5.0, 1e-4));
      expect(last.signals!.wiperIntensity, 5);
      expect(last.assessment!.surfaceState, RoadSurfaceState.compactedSnow);

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });

    test('HysteresisFilter debounces a single-frame surface flip', () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final surfaces = <RoadSurfaceState>[];
      final sub = provider.conditions.listen((u) {
        // surfaceState is nullable: an absent reading is not a value and must
        // not be recorded as one. Same contract as averageConfidence and
        // lengthKmOrNull — absence of a measurement is not a measurement.
        final s = u.assessment?.surfaceState;
        if (s != null) surfaces.add(s);
      });

      // dry baseline
      source.add({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 95.0),
        kAirTemperature: _floatDp(kAirTemperature, 5.0),
      });
      await pumpEventQueue();
      // one icy reading (should be HELD — below the hysteresis threshold)
      source.add({kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0)});
      await pumpEventQueue();
      // a second icy reading (now persists → flip allowed)
      source.add({kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0)});
      await pumpEventQueue();

      // UPDATED at the main<-feature merge, 2026-08-28, and the reason matters
      // more than the change: this expectation asserted `dry` on evidence that
      // cannot support it. `RoadSurfaceState.fromCondition` documents the rule
      // verbatim — "classification, above all [dry], requires knowing BOTH the
      // temperature and the precipitation type. Being offline does not mean
      // 'ice'; it means 'unknown', and unknown is a thing the driver is TOLD."
      // The KUKSA path supplies friction, wiper intensity and air temperature;
      // it carries no precipitation TYPE, so the baseline is honestly unknown
      // and surfaceState is null. The old expectation predates the
      // honest-absence wave (6de4034), which main does not yet contain.
      //
      // The debounce this test exists to prove is STILL PROVEN, and that is why
      // the expectation is corrected rather than the test deleted: the FIRST
      // icy frame is held (nothing emitted) and only the SECOND flips. One
      // entry is the debounce working.
      //
      // ⚑ ROUTED TO SDE: the stronger test would feed a fully classifiable dry
      // baseline (add a precipitation type) so the sequence reads dry -> held
      // -> blackIce again. That is a test-input change, not an expectation
      // change, and it is the better fix. Not taken here to keep the merge
      // diff to what the merge itself requires.
      expect(surfaces, [RoadSurfaceState.blackIce]);

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });

    test('does NOT emit when no signal is decodable (never fabricates)',
        () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      source.add({}); // empty cycle
      source.add({kAirTemperature: _valuelessDp(kAirTemperature)}); // value-less
      await pumpEventQueue();

      expect(results, isEmpty);

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });

    test('honest fallback: a stream ERROR surfaces unavailable, no throw',
        () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      source.addError('connection refused');
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isFalse);
      expect(results.single.assessment, isNull);
      expect(provider.available, isFalse);
      expect(results.single.unavailableReason, contains('connection refused'));

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });

    test('honest fallback: stream DONE surfaces unavailable', () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      await source.close(); // broker stream ends
      await pumpEventQueue();

      expect(results, hasLength(1));
      expect(results.single.isAvailable, isFalse);
      expect(results.single.unavailableReason, contains('ended'));

      await sub.cancel();
      await provider.dispose();
    });
  });
}
