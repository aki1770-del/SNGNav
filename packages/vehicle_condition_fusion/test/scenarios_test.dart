/// Tests for the SYNTHETIC scenarios + replay helper — PURE DART.
///
/// These pin two things:
///   1. `replayWinterDrive` emits exactly the frames it is given, and
///   2. each SYNTHETIC trace, driven through the published fusion, actually
///      yields the hazard PROGRESSION it claims (so a trace cannot silently
///      drift into not exercising the hazard it advertises).
///
/// As with the core tests: no `kuksa_dart_sdk`, no protobuf, no databroker —
/// just `StreamController`-free replay of plain `VehicleConditionSignals`.
library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:test/test.dart';
import 'package:vehicle_condition_fusion/scenarios.dart';
import 'package:vehicle_condition_fusion/vehicle_condition_fusion.dart';

/// Drives [frames] through the partial-frame carry-forward rail to completion
/// and returns every LIVE assessment, in order. The replay's end-of-stream
/// makes the fusion emit its honest `unavailable` marker, which we use as the
/// "drive finished" signal.
Future<List<DrivingConditionAssessment>> runScenario(
  List<VehicleConditionSignals> frames,
) async {
  final fusion = VehicleConditionFusion.fromPartialFrames(
    partialFrames: replayWinterDrive(frames),
  );
  final assessments = <DrivingConditionAssessment>[];
  final done = Completer<void>();

  final sub = fusion.conditions.listen((u) {
    if (u.isAvailable) {
      assessments.add(u.assessment!);
    } else if (!done.isCompleted) {
      done.complete();
    }
  });

  await done.future;
  await sub.cancel();
  await fusion.dispose();
  return assessments;
}

/// Consecutive-dedup of the surface-state sequence (the distinct phases seen).
List<RoadSurfaceState?> _phases(List<DrivingConditionAssessment> a) {
  final out = <RoadSurfaceState?>[];
  for (final s in a.map((e) => e.surfaceState)) {
    if (out.isEmpty || out.last != s) out.add(s);
  }
  return out;
}

void main() {
  group('replayWinterDrive', () {
    test('emits exactly the frames it is given, in order', () async {
      const frames = [
        VehicleConditionSignals(roadFriction: 0.9, airTempC: 2.0),
        VehicleConditionSignals(wiperIntensity: 5),
        VehicleConditionSignals(roadFriction: 0.2, airTempC: -6.0),
      ];
      final emitted = await replayWinterDrive(frames).toList();
      expect(emitted, frames);
    });

    test('emits all frames of a named scenario (step zero = instant)', () async {
      final emitted = await replayWinterDrive(akitaWhiteoutDrive).toList();
      expect(emitted, hasLength(akitaWhiteoutDrive.length));
      expect(emitted, akitaWhiteoutDrive);
    });

    test('a non-zero step still emits every frame', () async {
      final emitted = await replayWinterDrive(
        blackIcePatch,
        step: const Duration(milliseconds: 1),
      ).toList();
      expect(emitted, blackIcePatch);
    });

    test('an empty trace emits nothing and completes', () async {
      final emitted =
          await replayWinterDrive(const <VehicleConditionSignals>[]).toList();
      expect(emitted, isEmpty);
    });
  });

  group('akitaWhiteoutDrive — the trace yields the hazard it claims', () {
    test('progression is clear → compacted snow → black ice → slush → wet',
        () async {
      final a = await runScenario(akitaWhiteoutDrive);

      // Starts UNCLASSIFIED and ends on a cleared (wet) road.
      //
      // This vehicle has no hygrometer, and it departs at -1 °C with no
      // precipitation — inside the radiative-frost window, where the surface
      // determination rests on humidity. The frost check abstains, so there is
      // no verdict. It used to read `dry`, and the fixture comment still called
      // that "a dry road just below 0 °C is still dry" — but nothing had
      // measured it; `dry` is gripFactor 1.0, a positive claim.
      expect(a.first.surfaceState, isNull,
          reason: 'a hygrometer-less departure at -1 °C is UNMEASURED, and an '
              'unmeasured road is not a clear one');
      expect(a.last.surfaceState, RoadSurfaceState.wet,
          reason: 'drive must clear (no longer black ice) by the end');

      // The whiteout black-ice phase is actually reached, with an ice advisory.
      expect(a.map((e) => e.surfaceState), contains(RoadSurfaceState.blackIce),
          reason: 'the whiteout phase must produce black ice');
      final ice = a.firstWhere(
          (e) => e.surfaceState == RoadSurfaceState.blackIce);
      expect(ice.advisoryMessage.toLowerCase(), contains('ice'));
      // Black ice = lowest grip; the whiteout visibility proxy is heavy fog.
      expect(ice.gripFactor, RoadSurfaceState.blackIce.gripFactor);
      expect(ice.visibility!.opacity, greaterThan(0.5),
          reason: 'the whiteout must read as a heavy-fog / low-visibility cue');

      // The exact phase progression (escalate, then de-escalate and clear).
      expect(_phases(a), <RoadSurfaceState?>[
        null, // departure: inside the frost window, no hygrometer
        RoadSurfaceState.compactedSnow,
        RoadSurfaceState.blackIce,
        RoadSurfaceState.slush,
        RoadSurfaceState.wet,
      ]);

      // Ordering: ice escalates after the clear start and clears before the end.
      final iceIndex =
          a.indexWhere((e) => e.surfaceState == RoadSurfaceState.blackIce);
      expect(iceIndex, greaterThan(0), reason: 'ice must escalate, not start');
      expect(
        a.sublist(iceIndex + 1).map((e) => e.surfaceState),
        contains(RoadSurfaceState.wet),
        reason: 'the road must clear AFTER the whiteout',
      );
    });

    test('carry-forward HOLDS the whiteout across a speed-only partial frame',
        () async {
      // The safety property made visible: the whiteout phase has a frame that
      // re-sends ONLY speed; black ice must persist (≥2 consecutive black-ice
      // emissions), never silently drop because the ice signals were not
      // re-sent that cycle.
      final a = await runScenario(akitaWhiteoutDrive);
      final iceRun = a
          .map((e) => e.surfaceState)
          .where((s) => s == RoadSurfaceState.blackIce)
          .length;
      expect(iceRun, greaterThanOrEqualTo(2),
          reason: 'black ice must hold across the speed-only partial frame');
    });
  });

  group('blackIcePatch — cold-slip TCS ice path', () {
    test('progression is dry → black ice → dry', () async {
      final a = await runScenario(blackIcePatch);
      // DEGRADED vehicle: friction, temperature and a rain sensor, but no
      // hygrometer. Both ends of this drive sit inside the frost window
      // (-1 °C and -2 °C, no precipitation), so the frost determination cannot
      // be made and the surface is honestly unknown at each end. The ice in the
      // middle still fires: it comes from the TCS cold-slip rule, which is
      // POSITIVE evidence and needs no humidity.
      expect(_phases(a), <RoadSurfaceState?>[
        null,
        RoadSurfaceState.blackIce,
        null,
      ]);
      // The ice here is from the TCS cold-slip rule, not from low friction.
      final ice =
          a.firstWhere((e) => e.surfaceState == RoadSurfaceState.blackIce);
      expect(ice.advisoryMessage.toLowerCase(), contains('ice'));
    });

    test('the SAME drive on a hygrometer-equipped vehicle classifies every '
        'frame — and is a WITNESS to the sub-zero presence gate', () async {
      final degraded = await runScenario(blackIcePatch);
      final measured = await runScenario(blackIcePatchMeasured);

      // The DURABLE property, and the reason the pair exists: publishing the
      // humidity leaf removes the abstention. Every frame the degraded vehicle
      // could not classify, the measured vehicle can. This assertion stays
      // correct however the exposure below is eventually resolved.
      expect(degraded.map((e) => e.surfaceState), contains(null),
          reason: 'the degraded vehicle must have something it cannot judge');
      expect(measured.map((e) => e.surfaceState), everyElement(isNotNull),
          reason: 'with the humidity leaf published, nothing is left unjudged');

      // The WITNESS. Not an endorsement — see the fixture docstring and
      // snow_rendering KNOWN_LIMITATIONS.md §2 (cry-wolf exposure, wind/time
      // gate deferred 2026-07-07). At or below 0 °C the frost check fires at
      // EVERY humidity, so the departure frame — a road the vehicle's own ESC
      // friction estimate reads at 0.90 — is classified black ice.
      expect(measured.first.surfaceState, RoadSurfaceState.blackIce,
          reason: 'WITNESS: at -1 °C ANY humidity value fires the frost check, '
              'so merely publishing the leaf turns a 0.90-friction road into '
              'black ice at departure. If a wind/time gate lands, this fails '
              'ON PURPOSE — come and read the report that filed it.');
    });
  });

  group('clearRoad — benign trace asserts no ice', () {
    test('progression is dry → wet → dry and never black ice', () async {
      final a = await runScenario(clearRoad);
      expect(_phases(a), <RoadSurfaceState>[
        RoadSurfaceState.dry,
        RoadSurfaceState.wet,
        RoadSurfaceState.dry,
      ]);
      expect(a.map((e) => e.surfaceState),
          isNot(contains(RoadSurfaceState.blackIce)));
    });
  });
}
