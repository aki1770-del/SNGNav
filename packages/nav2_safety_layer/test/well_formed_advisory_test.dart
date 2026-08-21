/// The success path: what a WELL-FORMED collision state tells the driver.
///
/// ⚑ This file exists because the four prove-it-fails tests written on
/// 2026-08-20 all fed MALFORMED input, and were therefore structurally
/// incapable of catching the worse defect: a perfectly well-formed
/// `STOP` produced a fabricated meteorological claim.
///
/// Recorded RED state, measured 2026-08-21 against 0.1.3 as published —
/// every one of the four non-zero actions emitted, byte-identically:
///   「凍結路面です。気温0°C以下で薄氷ができています。
///     時速30km以下に減速し、急ブレーキは避けてください」
/// nav2 had said an OBJECT was inside a configured polygon. The text
/// invents a temperature from a message carrying none, and instructs the
/// driver to AVOID BRAKING HARD while the monitor commands a stop.
///
/// Found by WDA. Corrected by mapping obstacle events to
/// `RoadSurfaceCondition.unknown`, which claims nothing about a surface
/// this message says nothing about.
library;

import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

const _actions = [
  Nav2CollisionAction.stop,
  Nav2CollisionAction.slowdown,
  Nav2CollisionAction.approach,
  Nav2CollisionAction.limit,
];

void main() {
  group('a well-formed obstacle event must not claim anything about the surface', () {
    for (final profile in DriverProfile.values) {
      for (final a in _actions) {
        test('${a.name} / ${profile.name} invents no weather', () {
          final e = Nav2SafetyMapper.toAdvisory(
              Nav2CollisionMonitorState(actionType: a, polygonName: 'ZONE_A'),
              profile);
          expect(e, isNotNull);
          final text = e!.action;
          expect(text, isNot(contains('凍結')),
              reason: 'nav2 reported an obstacle, not ice.');
          expect(text, isNot(contains('薄氷')),
              reason: 'no thin-ice claim from a message with no surface data.');
          expect(text, isNot(contains('0°C')),
              reason: 'no temperature claim from a message with no temperature.');
        });

        test('${a.name} / ${profile.name} does not tell her to avoid braking', () {
          final e = Nav2SafetyMapper.toAdvisory(
              Nav2CollisionMonitorState(actionType: a, polygonName: 'ZONE_A'),
              profile);
          expect(e!.action, isNot(contains('急ブレーキは避けて')),
              reason: 'the monitor is constraining motion; instructing her to '
                  'avoid hard braking inverts what nav2 asked for.');
        });
      }
    }
  });
}
