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

Datapoint _floatDp(String path, double v) => Datapoint(
  raw: pb.Datapoint(value: pb.Value(float: v)),
  path: path,
);

Datapoint _boolDp(String path, bool v) => Datapoint(
  raw: pb.Datapoint(value: pb.Value(bool_12: v)),
  path: path,
);

Datapoint _intDp(String path, int v) => Datapoint(
  raw: pb.Datapoint(value: pb.Value(int32: v)),
  path: path,
);

Datapoint _valuelessDp(String path) =>
    Datapoint(raw: pb.Datapoint(), path: path);

void main() {
  // The app's job is the SDK decode ONLY (Datapoint → scalar). The VSS mapping —
  // paths, types, and the load-bearing friction PERCENT→0..1 conversion — is
  // `VehicleConditionSignals.fromVss`, and exists exactly once, in the package.
  // These tests therefore assert the composed pipeline the provider runs:
  //   Datapoints → vssLeavesFromDatapoints → fromVss
  VehicleConditionSignals signalsFrom(Map<String, Datapoint> dps) =>
      VehicleConditionSignals.fromVss(vssLeavesFromDatapoints(dps));

  group('vssLeavesFromDatapoints + fromVss (KUKSA decode → typed signals)', () {
    test('decodes REAL wire values to typed fields (friction is a PERCENT)', () {
      final signals = signalsFrom({
        // 20.0 PERCENT — the value a real ESC emits. NOT 0.2. VSS
        // `ESC.RoadFriction.MostProbable` is float, unit percent, min 0 max 100.
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0),
        kTcsIsEngaged: _boolDp(kTcsIsEngaged, true),
        kAbsIsEngaged: _boolDp(kAbsIsEngaged, false),
        kWiperFrontIntensity: _intDp(kWiperFrontIntensity, 5),
        kRaindetectionIntensity: _intDp(kRaindetectionIntensity, 80),
        kAirTemperature: _floatDp(kAirTemperature, -6.0),
        kVehicleSpeed: _floatDp(kVehicleSpeed, 42.0),
      });

      // NORMALIZED into the VehicleConditionSignals 0.0–1.0 contract.
      expect(signals.roadFriction, closeTo(0.2, 1e-4));
      expect(signals.tcsEngaged, isTrue);
      expect(signals.absEngaged, isFalse);
      expect(signals.wiperIntensity, 5);
      expect(signals.rainIntensity, 80);
      expect(signals.airTempC, closeTo(-6.0, 1e-4));
      expect(signals.speedKmh, closeTo(42.0, 1e-4));
      expect(signals.hasAnySignal, isTrue);
    });

    test('a full-grip wire value (95 %) normalizes to 0.95, not 95.0', () {
      final signals = signalsFrom({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 95.0),
      });
      expect(signals.roadFriction, closeTo(0.95, 1e-4));
    });

    test('absent / value-less signals decode to null (never guessed)', () {
      final signals = signalsFrom({
        kRoadFrictionMostProbable: _valuelessDp(kRoadFrictionMostProbable),
        // everything else simply absent from the map
      });
      expect(signals.roadFriction, isNull);
      expect(signals.tcsEngaged, isNull);
      expect(signals.airTempC, isNull);
      expect(signals.hasAnySignal, isFalse);
    });
  });

  group(
    'vehicleSignalsToWeatherCondition + assessment fusion (deterministic)',
    () {
      DrivingConditionAssessment assess(VehicleConditionSignals s) =>
          DrivingConditionAssessment.fromCondition(
            vehicleSignalsToWeatherCondition(s),
          );

      test('low road friction → black ice + ice advisory', () {
        final a = assess(
          const VehicleConditionSignals(roadFriction: 0.2, airTempC: -5.0),
        );
        expect(a.surfaceState, RoadSurfaceState.blackIce);
        expect(a.advisoryMessage.toLowerCase(), contains('ice'));
      });

      test('heavy snowfall, adequate grip → compacted snow + fog wall', () {
        final a = assess(
          const VehicleConditionSignals(
            roadFriction: 0.5, // not below the icy threshold
            wiperIntensity: 5, // heavy
            airTempC: -5.0,
          ),
        );
        expect(a.surfaceState, RoadSurfaceState.compactedSnow);
        // heavy precip → 300 m visibility proxy → strong fog opacity
        expect(a.visibility!.opacity, greaterThan(0.5));
      });

      test('moderate rain, warm, good grip → wet + mild fog', () {
        final a = assess(
          const VehicleConditionSignals(
            roadFriction: 0.9,
            wiperIntensity: 4, // moderate
            airTempC: 8.0,
          ),
        );
        expect(a.surfaceState, RoadSurfaceState.wet);
        // moderate precip → 800 m → some, but not heavy, fog
        expect(a.visibility!.opacity, greaterThan(0.0));
        expect(a.visibility!.opacity, lessThan(0.5));
      });

      test('TCS engaged on a COLD road → ice risk → black ice', () {
        final a = assess(
          const VehicleConditionSignals(
            roadFriction: 0.6, // not itself below the icy threshold
            tcsEngaged: true,
            airTempC: 0.0,
          ),
        );
        expect(a.surfaceState, RoadSurfaceState.blackIce);
      });

      test(
        'TCS engaged on a WARM road → NOT ice (aquaplaning, not freezing)',
        () {
          final a = assess(
            const VehicleConditionSignals(
              tcsEngaged: true,
              wiperIntensity: 4, // moderate rain
              airTempC: 12.0,
            ),
          );
          expect(a.surfaceState, isNot(RoadSurfaceState.blackIce));
        },
      );

      test('dry, warm, full grip, no precip → dry + normal advisory', () {
        final a = assess(
          const VehicleConditionSignals(
            roadFriction: 0.95,
            wiperIntensity: 0,
            airTempC: 5.0,
          ),
        );
        expect(a.surfaceState, RoadSurfaceState.dry);
      });

      test('missing temperature + low friction → still black ice '
          '(friction is a direct measurement)', () {
        final a = assess(const VehicleConditionSignals(roadFriction: 0.2));
        expect(a.surfaceState, RoadSurfaceState.blackIce);
      });
    },
  );

  group('KuksaConditionProvider (injected stream)', () {
    test('emits a fused live assessment from a snapshot', () async {
      final source = StreamController<Map<String, Datapoint>>();
      final provider = KuksaConditionProvider(updates: source.stream);
      final results = <KuksaConditionUpdate>[];
      final sub = provider.conditions.listen(results.add);

      source.add({
        // PERCENT wire value (20 %) → normalizes to 0.20 → below the 0.3 icy
        // threshold.
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

      // First: friction + temp. 50 % wire → 0.50 (above the icy threshold).
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
      // NULLABLE (snow_rendering 0.3.0). The baseline frames carry friction and
      // air temperature but NO wiper signal — so the precipitation type was
      // never measured, and the surface CANNOT be classified. Up to 0.2.7 those
      // frames fell through to `RoadSurfaceState.dry` (gripFactor 1.0,
      // "Conditions normal") — a confident claim about a road whose
      // precipitation nobody had observed. The honest answer is `null`.
      final surfaces = <RoadSurfaceState?>[];
      final sub = provider.conditions.listen((u) {
        surfaces.add(u.assessment?.surfaceState);
      });

      // dry baseline — 95 % wire → 0.95
      source.add({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 95.0),
        kAirTemperature: _floatDp(kAirTemperature, 5.0),
      });
      await pumpEventQueue();
      // one icy reading, 20 % wire → 0.20 (should be HELD — below the
      // hysteresis threshold)
      source.add({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0),
      });
      await pumpEventQueue();
      // a second icy reading (now persists → flip allowed)
      source.add({
        kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 20.0),
      });
      await pumpEventQueue();

      // unknown (precipitation never measured), then HELD unknown (the
      // single-frame icy flip is debounced — the hysteresis still works), then
      // black ice once the icy reading PERSISTS.
      //
      // The load-bearing change from 0.2.7: the first two are `null`, not
      // `dry`. Absence is no longer maximum grip. The POSITIVE evidence (a
      // persisted low-friction cold reading) still fires — the asymmetry holds.
      expect(surfaces, [
        null,
        null,
        RoadSurfaceState.blackIce,
      ]);

      await sub.cancel();
      await provider.dispose();
      await source.close();
    });

    test(
      'does NOT emit when no signal is decodable (never fabricates)',
      () async {
        final source = StreamController<Map<String, Datapoint>>();
        final provider = KuksaConditionProvider(updates: source.stream);
        final results = <KuksaConditionUpdate>[];
        final sub = provider.conditions.listen(results.add);

        source.add({}); // empty cycle
        source.add({
          kAirTemperature: _valuelessDp(kAirTemperature),
        }); // value-less
        await pumpEventQueue();

        expect(results, isEmpty);

        await sub.cancel();
        await provider.dispose();
        await source.close();
      },
    );

    // ── REGRESSION: the 100× friction-unit bug ────────────────────────────
    //
    // `Vehicle.ADAS.ESC.RoadFriction.MostProbable` is a COVESA VSS **percent**
    // (float, min 0, max 100). A real ESC on black ice emits 18.0 — NOT 0.18.
    //
    // The app's bespoke adapter passed that raw percent straight into
    // `VehicleConditionSignals.roadFriction`, whose contract is 0.0–1.0 and
    // whose icy threshold is 0.3. `18.0 < 0.3` is false, so the classifier did
    // not merely abstain — it POSITIVELY asserted "we measured the friction and
    // the road is fine" (`_iceRisk` returns false on a non-null friction), and
    // returned a DRY road at full grip.
    //
    // +1.0 °C with the wipers off is exactly the radiative-frost black-ice
    // window this product exists for: the air is above freezing, nothing is
    // falling, and the road is ice.
    test(
      'REGRESSION: real ESC wire value 18.0 PERCENT at +1°C, wipers off '
      '→ black ice (was: dry, full grip — the 100× unit bug)',
      () async {
        final source = StreamController<Map<String, Datapoint>>();
        // Pinned no-debounce filter so this asserts the CLASSIFICATION, not the
        // hysteresis hold.
        final provider = KuksaConditionProvider(
          updates: source.stream,
          surfaceFilter: HysteresisFilter<RoadSurfaceState>(
            windowSize: 1,
            threshold: 1,
          ),
        );
        final results = <KuksaConditionUpdate>[];
        final sub = provider.conditions.listen(results.add);

        source.add({
          // The wire value a real ESC emits on black ice: 18.0 PERCENT.
          kRoadFrictionMostProbable: _floatDp(kRoadFrictionMostProbable, 18.0),
          // Above freezing — the air, not the road.
          kAirTemperature: _floatDp(kAirTemperature, 1.0),
          // Nothing falling. Nothing to see. That is the hazard.
          kWiperFrontIntensity: _intDp(kWiperFrontIntensity, 0),
        });
        await pumpEventQueue();

        expect(results, hasLength(1));
        final update = results.single;

        // The percent MUST be normalized to the 0.0–1.0 contract.
        expect(
          update.signals!.roadFriction,
          closeTo(0.18, 1e-6),
          reason: 'VSS friction is a percent; the signals contract is 0..1',
        );
        // And the road MUST read as ice, not as a dry road at full grip.
        expect(update.assessment!.surfaceState, RoadSurfaceState.blackIce);
        expect(update.assessment!.gripFactor, lessThan(0.5));

        await sub.cancel();
        await provider.dispose();
        await source.close();
      },
    );

    test(
      'honest fallback: a stream ERROR surfaces unavailable, no throw',
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
        expect(
          results.single.unavailableReason,
          contains('connection refused'),
        );

        await sub.cancel();
        await provider.dispose();
        await source.close();
      },
    );

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
