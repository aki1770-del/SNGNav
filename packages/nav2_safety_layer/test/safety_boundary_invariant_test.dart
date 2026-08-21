/// Executable oracle for `SAFETY_BOUNDARY.md`.
///
/// Authored by FSE (functional-safety-engineer), 2026-08-21, under bylaws C4:
/// a safety document with no code-enforced invariant behind it is papers-as-end
/// and is cut. This file is that invariant.
///
/// WHAT THIS FILE IS NOT
/// --------------------
/// These tests do NOT assert that the behaviour they pin is correct. Most of it
/// is not. They assert it is WHAT IS CURRENTLY SHIPPED, so that the gap between
/// SAFETY_BOUNDARY.md and the code cannot widen silently.
///
/// If you are fixing one of the recorded insufficiencies, the matching test here
/// WILL FAIL. That is deliberate and it is the whole point: the failure is the
/// reminder to update SAFETY_BOUNDARY.md in the same change. Do not delete the
/// test to make the suite green — invert it, and move the row in the table.
///
/// Every ID below (PI-nn / D-nn / BI-n / AoU-n) resolves to a row or section in
/// SAFETY_BOUNDARY.md.
library;

import 'dart:async';
import 'dart:io';

import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// Broadcast delivery is asynchronous; a synchronous read of a collector list
/// measures nothing. Every stream assertion below settles first.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

/// Locate pubspec.yaml whether the runner's cwd is the package root or above it.
File _pubspec() {
  for (final p in ['pubspec.yaml', 'packages/nav2_safety_layer/pubspec.yaml']) {
    final f = File(p);
    if (f.existsSync()) return f;
  }
  fail('pubspec.yaml not found from cwd ${Directory.current.path}');
}

/// Runtime dependency names declared in pubspec.yaml (excludes dev_dependencies).
Set<String> _runtimeDeps() {
  final lines = _pubspec().readAsLinesSync();
  final deps = <String>{};
  var inBlock = false;
  for (final line in lines) {
    if (line.startsWith('dependencies:')) {
      inBlock = true;
      continue;
    }
    // Any other top-level key ends the block.
    if (inBlock && line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#')) {
      break;
    }
    if (!inBlock) continue;
    final m = RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
    if (m != null) deps.add(m.group(1)!);
  }
  return deps;
}

void main() {
  // ---------------------------------------------------------------------------
  // BI-1 — the ONE safety property this package holds by construction.
  // ---------------------------------------------------------------------------
  group('BI-1 — no transport dependency (SAFETY_BOUNDARY §7, "driver always drives")', () {
    test('runtime dependencies are exactly {equatable, navigation_safety_core}', () {
      expect(
        _runtimeDeps(),
        equals({'equatable', 'navigation_safety_core'}),
        reason:
            'SAFETY_BOUNDARY §7 claims this package CANNOT reach ROS 2 or actuate '
            'anything, and grounds that claim on declaring no transport dependency. '
            'That is the only structurally-provable safety property this package has. '
            'If a ROS / HTTP / socket / FFI dependency has been added, the §7 claim is '
            'no longer true by construction and the boundary record needs re-auditing '
            'by AAA + DIA before release.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // BI-2..BI-5 — the four silence-on-unreadable-input insufficiencies.
  // Each is CURRENT SHIPPED BEHAVIOUR and each is UNSAFE. Pinned, not endorsed.
  // ---------------------------------------------------------------------------
  group('BI-2..BI-5 — unreadable input renders as "no hazard" (KNOWN-UNSAFE, pinned)', () {
    test('PI-01: absent action_type still reads as DO_NOTHING', () {
      final s = Nav2CollisionMonitorState.fromJson({'polygon_name': 'front'});
      expect(s.actionType, Nav2CollisionAction.doNothing,
          reason: 'PI-01 pinned. A truncated frame is indistinguishable from a '
              'quiet monitor. If this now differs, PI-01 is fixed — update the table.');
    });

    test('PI-02: unknown action code still reads as DO_NOTHING', () {
      final s = Nav2CollisionMonitorState.fromJson(
          {'action_type': 5, 'polygon_name': 'front'});
      expect(s.actionType, Nav2CollisionAction.doNothing,
          reason: 'PI-02 pinned. See AoU-9: nav2 declares ActionType twice with '
              'nothing linking the C++ enum to the .msg constants, so an upstream '
              'addition arrives here silently.');
    });

    test('PI-03: absent detections array still reports anyDetection == false', () {
      final d = Nav2CollisionDetectorState.fromJson({
        'polygons': ['front', 'rear'],
      });
      expect(d.anyDetection, isFalse,
          reason: 'PI-03 pinned. "detections absent" is unreadable, and is '
              'currently rendered as "nothing detected".');
    });

    test('PI-04: length mismatch is still absorbed as a shorter loop', () {
      final d = Nav2CollisionDetectorState.fromJson({
        'polygons': ['a', 'b', 'c', 'd', 'e'],
        'detections': [false, false],
      });
      expect(d.polygons.length, 5);
      expect(d.detections.length, 2);
      expect(d.triggeredPolygons, isEmpty,
          reason: 'PI-04 pinned. 5 polygons against 2 detections is proof the '
              'message is corrupt; triggeredPolygons iterates min(len) and '
              'reports on 2 without signalling anything.');
    });

    test('the whole channel is silent on all four — nothing reaches the HMI', () async {
      final layer = Nav2SafetyLayer(
        profile: DriverProfile.snowZoneExperienced,
        throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
      );
      final got = <String>[];
      final sub = layer.advisories.listen(got.add);
      await settle();

      layer.onMonitorState(
          Nav2CollisionMonitorState.fromJson({'polygon_name': 'front'})); // PI-01
      layer.onMonitorState(Nav2CollisionMonitorState.fromJson(
          {'action_type': 5, 'polygon_name': 'front'})); // PI-02
      layer.onDetectorState(Nav2CollisionDetectorState.fromJson({
        'polygons': ['front', 'rear'],
      })); // PI-03
      await settle();

      expect(got, isEmpty,
          reason: 'AoU-1 is the assumption this proves necessary: an integrator '
              'CANNOT read silence on `advisories` as an all-clear. Four distinct '
              'unreadable-message conditions produce exactly what a quiet, healthy '
              'monitor produces.');
      await sub.cancel();
      await layer.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // BI-6 — severity collapse.
  // ---------------------------------------------------------------------------
  group('BI-6 — PI-05: four upstream action classes collapse to one string', () {
    test('STOP and LIMIT are byte-identical at the HMI', () {
      const p = DriverProfile.snowZoneExperienced;
      final stop = Nav2SafetyMapper.toAdvisory(
          const Nav2CollisionMonitorState(
              actionType: Nav2CollisionAction.stop, polygonName: 'front'),
          p)!;
      final limit = Nav2SafetyMapper.toAdvisory(
          const Nav2CollisionMonitorState(
              actionType: Nav2CollisionAction.limit, polygonName: 'front'),
          p)!;
      expect(stop.action, equals(limit.action),
          reason: 'PI-05 pinned. nav2 STOP ("stop the robot") and LIMIT ("limit '
              'velocity if pts in range") are the extremes of the upstream action '
              'set and are indistinguishable downstream. AoU-4: an integrator '
              'needing severity must read state.actionType itself.');
    });

    test('all four non-doNothing actions produce one distinct string', () {
      const p = DriverProfile.snowZoneExperienced;
      final texts = <String>{};
      for (final a in Nav2CollisionAction.values) {
        if (a == Nav2CollisionAction.doNothing) continue;
        texts.add(Nav2SafetyMapper.toAdvisory(
                Nav2CollisionMonitorState(actionType: a, polygonName: 'p'), p)!
            .action);
      }
      expect(texts, hasLength(1),
          reason: 'PI-05 pinned: the mapper is information-destroying by design '
              '(nav2_safety_mapper.dart:30-45).');
    });
  });

  // ---------------------------------------------------------------------------
  // BI-7 — false-cause attribution.
  //
  // ⚑ THIS BLOCK WAS REWRITTEN MID-AUDIT, 2026-08-21, AND THE REASON IS THE
  // POINT OF THE FILE. It was first written to pin the SHIPPED 0.1.3 behaviour:
  // an obstacle rendered as 「凍結路面です。気温0°C以下で薄氷ができています…
  // 急ブレーキは避けてください」. Between the writing of SAFETY_BOUNDARY.md
  // (05:30) and the first run of this oracle (05:32), another seat corrected the
  // mapper to `RoadSurfaceCondition.unknown`. These two tests FAILED, which is
  // exactly what this file exists to do: the record said one thing, the code had
  // come to say another, and the oracle refused to stay quiet about the gap.
  //
  // Pinned below is the CORRECTED working-tree behaviour. PUBLISHED 0.1.3 ON
  // PUB.DEV STILL EMITS THE ICE TEXT — the fix has not been released, so for
  // every consumer PI-06 is still live. See SAFETY_BOUNDARY.md §3.1 PI-06.
  // ---------------------------------------------------------------------------
  group('BI-7 — PI-06: obstacle events must not assert a road-surface cause', () {
    test('an obstacle no longer yields a fabricated frozen-surface claim', () {
      final ex = Nav2SafetyMapper.toAdvisory(
          const Nav2CollisionMonitorState(
              actionType: Nav2CollisionAction.stop, polygonName: 'front'),
          DriverProfile.ageingRural)!;
      expect(ex.condition, RoadSurfaceCondition.unknown,
          reason: 'PI-06 corrected in the working tree (nav2_safety_mapper.dart). '
              'The message asserted an obstacle in a polygon and says nothing '
              'about the surface, so the advisory must claim nothing about it.');
      expect(ex.action, isNot(contains('凍結')),
          reason: 'No frozen-surface claim may be synthesised from a message '
              'carrying no temperature and no surface state.');
      expect(ex.action, isNot(contains('急ブレーキは避けて')),
          reason: 'PI-06 sharpest form, now closed in-tree: the advisory must '
              'never counter-instruct the manoeuvre an upstream STOP demands.');
    });

    test('the residual is real and is pinned: no obstacle vocabulary exists', () {
      final ex = Nav2SafetyMapper.toAdvisory(
          const Nav2CollisionMonitorState(
              actionType: Nav2CollisionAction.stop, polygonName: 'front'),
          DriverProfile.ageingRural)!;
      expect(ex.action, contains('路面状況不明'),
          reason: 'RESIDUAL, recorded not closed. `.unknown` is honest and still '
              'wrong in DOMAIN: nav2 reported an OBSTACLE, and '
              'RoadSurfaceCondition has no obstacle member, so the driver is '
              'told the SURFACE is unknown when the actual event was an object '
              'in a collision polygon. The vocabulary gap belongs to '
              'navigation_safety_core and is not closeable in this package.');
    });
  });

  // ---------------------------------------------------------------------------
  // BI-8 — documentation/code divergence.
  // ---------------------------------------------------------------------------
  group('BI-8 — D-08: the monitor path does not relay polygon_name', () {
    test('polygon_name is absent from monitor-path advisory text', () {
      final ex = Nav2SafetyMapper.toAdvisory(
          const Nav2CollisionMonitorState(
              actionType: Nav2CollisionAction.stop, polygonName: 'REAR_LEFT_ZONE'),
          DriverProfile.snowZoneExperienced)!;
      expect(ex.action.contains('REAR_LEFT_ZONE'), isFalse,
          reason: 'D-08 pinned. nav2_safety_mapper.dart:7-10 states polygon_name is '
              'surfaced verbatim into the advisory `areaDescription`. toAdvisory '
              'never reads state.polygonName, and `areaDescription` does not exist '
              'on AlertExplainer nor anywhere in navigation_safety_core.');
    });

    test('the detector path DOES relay polygon names — the divergence is path-specific', () async {
      final layer = Nav2SafetyLayer(
        profile: DriverProfile.snowZoneExperienced,
        throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
      );
      final got = <String>[];
      final sub = layer.advisories.listen(got.add);
      await settle();
      layer.onDetectorState(const Nav2CollisionDetectorState(
          polygons: ['REAR_LEFT_ZONE'], detections: [true]));
      await settle();
      expect(got.single, contains('REAR_LEFT_ZONE'),
          reason: 'nav2_safety_layer.dart:64-65 relays on the detector path only. '
              'The documented discipline is half-implemented, which is why the '
              'README reads as though it were whole.');
      await sub.cancel();
      await layer.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // BI-9 — the severe one. A nav2 STOP is the most droppable signal in the package.
  // ---------------------------------------------------------------------------
  group('BI-9 — D-07 REPAIRED: a nav2 STOP survives advisory load', () {
    test('the core critical-bypass works, and this package NOW asks for it', () {
      final t = AlertDensityThrottle(alertsPerMinuteCap: 1);
      final now = DateTime(2026, 8, 21, 5, 0, 0);
      expect(t.shouldFire(now, AlertSeverity.warning), isTrue);
      expect(t.shouldFire(now, AlertSeverity.warning), isFalse,
          reason: 'cap consumed');
      expect(t.shouldFire(now, AlertSeverity.critical), isTrue,
          reason: '⚑ CORRECTED 2026-08-21. navigation_safety_core '
              'SAFETY_BOUNDARY.md:41-50 critical-bypass is intact in the dependency, '
              'and it is now REACHABLE from this package: nav2_safety_layer.dart:84 '
              'passes severityOf(state.actionType), which maps stop/approach to '
              'AlertSeverity.critical. The previous text — "…:47 and :59 pass '
              'AlertSeverity.warning hardcoded for EVERY event, so this bypass is '
              'never reachable from this package" — described a package that no '
              'longer exists, and it said so from inside a GREEN test, where nobody '
              'reads it.');
    });

    test('a burst of LIMIT consumes the cap and the following STOP STILL reaches the driver',
        () async {
      final layer = Nav2SafetyLayer(
        profile: DriverProfile.snowZoneExperienced,
        throttle: AlertDensityThrottle(alertsPerMinuteCap: 2),
      );
      final got = <String>[];
      final sub = layer.advisories.listen(got.add);
      await settle();

      for (var i = 0; i < 5; i++) {
        layer.onMonitorState(const Nav2CollisionMonitorState(
            actionType: Nav2CollisionAction.limit, polygonName: 'far'));
        await settle();
      }
      final afterBurst = got.length;
      expect(afterBurst, 2, reason: 'cap is 2/min');

      layer.onMonitorState(const Nav2CollisionMonitorState(
          actionType: Nav2CollisionAction.stop, polygonName: 'IMMINENT_FRONT'));
      await settle();

      expect(got.length, equals(afterBurst + 1),
          reason: '⚑ D-07 REPAIRED 2026-08-21 — this assertion is INVERTED from a pin '
              'into a live regression guard. It previously demanded that the STOP be '
              'DROPPED, and it went stale the moment the defect was fixed: '
              'Nav2SafetyLayer.severityOf now maps stop/approach to '
              'AlertSeverity.critical, and AlertDensityThrottle holds a non-negotiable '
              'invariant that critical always fires regardless of in-window count '
              '(alert_density_throttle.dart:18). The most severe action nav2 can '
              'publish now reaches the driver exactly when the monitor is busiest. '
              'If this ever fails again, the critical-bypass has been broken and a '
              'reflexive-stop signal is being swallowed under load.');
      await sub.cancel();
      await layer.dispose();
    });
  });

  // ---------------------------------------------------------------------------
  // BI-10 — the boundary record must exist and must stay attached.
  // ---------------------------------------------------------------------------
  group('BI-10 — the boundary record exists and is reachable from the package', () {
    test('SAFETY_BOUNDARY.md is present beside pubspec.yaml', () {
      final dir = _pubspec().parent;
      final rec = File('${dir.path}${Platform.pathSeparator}SAFETY_BOUNDARY.md');
      expect(rec.existsSync(), isTrue,
          reason: 'The package named `safety` was the one package in this catalog '
              'without a boundary record. This test exists so it cannot become that '
              'again silently.');
      final text = rec.readAsStringSync();
      for (final id in ['PI-01', 'PI-05', 'PI-06', 'D-07', 'D-08', 'AoU-1', 'AoU-9']) {
        expect(text, contains(id),
            reason: 'Every ID asserted in this oracle must resolve to a row in the '
                'boundary record. Missing: $id');
      }
    });
  });
}
