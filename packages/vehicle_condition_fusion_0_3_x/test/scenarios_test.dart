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
List<RoadSurfaceState> _phases(List<DrivingConditionAssessment> a) {
  final out = <RoadSurfaceState>[];
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

    test(
      'emits all frames of a named scenario (step zero = instant)',
      () async {
        final emitted = await replayWinterDrive(akitaWhiteoutDrive).toList();
        expect(emitted, hasLength(akitaWhiteoutDrive.length));
        expect(emitted, akitaWhiteoutDrive);
      },
    );

    test('a non-zero step still emits every frame', () async {
      final emitted = await replayWinterDrive(
        blackIcePatch,
        step: const Duration(milliseconds: 1),
      ).toList();
      expect(emitted, blackIcePatch);
    });

    test('an empty trace emits nothing and completes', () async {
      final emitted = await replayWinterDrive(
        const <VehicleConditionSignals>[],
      ).toList();
      expect(emitted, isEmpty);
    });
  });

  group('akitaWhiteoutDrive — the trace yields the hazard it claims', () {
    test(
      'progression is clear → compacted snow → black ice → slush → wet',
      () async {
        final a = await runScenario(akitaWhiteoutDrive);

        // Starts on a clear (dry) road and ends on a cleared (wet) road.
        expect(
          a.first.surfaceState,
          RoadSurfaceState.dry,
          reason: 'drive must start clear',
        );
        expect(
          a.last.surfaceState,
          RoadSurfaceState.wet,
          reason: 'drive must clear (no longer black ice) by the end',
        );

        // The whiteout black-ice phase is actually reached, with an ice advisory.
        expect(
          a.map((e) => e.surfaceState),
          contains(RoadSurfaceState.blackIce),
          reason: 'the whiteout phase must produce black ice',
        );
        final ice = a.firstWhere(
          (e) => e.surfaceState == RoadSurfaceState.blackIce,
        );
        expect(ice.advisoryMessage.toLowerCase(), contains('ice'));
        // Black ice = lowest grip; the whiteout visibility proxy is heavy fog.
        expect(ice.gripFactor, RoadSurfaceState.blackIce.gripFactor);
        expect(
          ice.visibility.opacity,
          greaterThan(0.5),
          reason: 'the whiteout must read as a heavy-fog / low-visibility cue',
        );

        // The exact phase progression (escalate, then de-escalate and clear).
        expect(_phases(a), <RoadSurfaceState>[
          RoadSurfaceState.dry,
          RoadSurfaceState.compactedSnow,
          RoadSurfaceState.blackIce,
          RoadSurfaceState.slush,
          RoadSurfaceState.wet,
        ]);

        // Ordering: ice escalates after the clear start and clears before the end.
        final iceIndex = a.indexWhere(
          (e) => e.surfaceState == RoadSurfaceState.blackIce,
        );
        expect(
          iceIndex,
          greaterThan(0),
          reason: 'ice must escalate, not start',
        );
        expect(
          a.sublist(iceIndex + 1).map((e) => e.surfaceState),
          contains(RoadSurfaceState.wet),
          reason: 'the road must clear AFTER the whiteout',
        );
      },
    );

    test(
      'carry-forward HOLDS the whiteout across a speed-only partial frame',
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
        expect(
          iceRun,
          greaterThanOrEqualTo(2),
          reason: 'black ice must hold across the speed-only partial frame',
        );
      },
    );
  });

  group('blackIcePatch — cold-slip TCS ice path', () {
    test('progression is dry → black ice → dry', () async {
      final a = await runScenario(blackIcePatch);
      expect(_phases(a), <RoadSurfaceState>[
        RoadSurfaceState.dry,
        RoadSurfaceState.blackIce,
        RoadSurfaceState.dry,
      ]);
      // The ice here is from the TCS cold-slip rule, not from low friction.
      final ice = a.firstWhere(
        (e) => e.surfaceState == RoadSurfaceState.blackIce,
      );
      expect(ice.advisoryMessage.toLowerCase(), contains('ice'));
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
      expect(
        a.map((e) => e.surfaceState),
        isNot(contains(RoadSurfaceState.blackIce)),
      );
    });
  });
}
