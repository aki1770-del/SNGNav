@Tags(['pinned-live'])
/// Prove-it-fails-first evidence for the four sites where this package renders
/// the SAFE answer from a message it could not read.
///
/// We maintain this package. It carries nav2 Collision Monitor state into an
/// app a driver uses. Every site below turns "I could not read this" into
/// "nothing is wrong", which is the one error a collision channel must not make.
///
/// The contract already exists in our own catalog, in driving_weather's
/// WeatherCondition: "Nothing was measured... It is NOT 'the road is clear'."
/// It was never applied here.
///
/// RED STATE IS RECORDED BELOW FROM AN ACTUAL RUN, not predicted.
library;

import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:test/test.dart';

void main() {
  group('DEFECT 1 — an absent action_type becomes DO_NOTHING', () {
    test('a message missing action_type must not read as "no action"', () {
      final s = Nav2CollisionMonitorState.fromJson({'polygon_name': 'front'});
      expect(s.actionType, isNot(Nav2CollisionAction.doNothing),
          reason: 'A truncated frame that drops action_type currently reports '
              'DO_NOTHING while the monitor may be publishing STOP.');
    });
  });

  group('DEFECT 2 — an unknown action code becomes DO_NOTHING', () {
    test('a code this package does not know must not read as "no action"', () {
      final s = Nav2CollisionMonitorState.fromJson(
          {'action_type': 5, 'polygon_name': 'front'});
      expect(s.actionType, isNot(Nav2CollisionAction.doNothing),
          reason: 'nav2 adding a sixth action code silently reads as no-action '
              'on every deployment running this package.');
    });
  });

  group('DEFECT 3 — an absent detections array becomes "no detection"', () {
    test('a message missing detections must not report anyDetection == false', () {
      final d = Nav2CollisionDetectorState.fromJson({
        'polygons': ['front', 'rear'],
      });
      expect(d.anyDetection, isNot(false),
          reason: 'detections absent is unreadable, not "nothing detected".');
    });
  });

  group('DEFECT 4 — a length mismatch is absorbed as a shorter loop', () {
    test('polygons and detections of different length is a malformed message', () {
      final d = Nav2CollisionDetectorState.fromJson({
        'polygons': ['a', 'b', 'c', 'd', 'e'],
        'detections': [false, false],
      });
      expect(d.polygons.length, equals(d.detections.length),
          reason: '5 polygons and 2 detections is proof the message is corrupt. '
              'triggeredPolygons iterates min(len) and reports on 2, silently.');
    });
  });
}
