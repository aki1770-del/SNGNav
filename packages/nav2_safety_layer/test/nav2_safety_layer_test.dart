/// Tests for nav2_safety_layer.
///
/// No live ROS bridge is required; tests construct typed records
/// directly and observe the advisory stream.
library;

import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:test/test.dart';

void main() {
  group('Nav2CollisionAction', () {
    test('fromInt maps 0..4 to canonical actions', () {
      expect(Nav2CollisionAction.fromInt(0), Nav2CollisionAction.doNothing);
      expect(Nav2CollisionAction.fromInt(1), Nav2CollisionAction.stop);
      expect(Nav2CollisionAction.fromInt(2), Nav2CollisionAction.slowdown);
      expect(Nav2CollisionAction.fromInt(3), Nav2CollisionAction.approach);
      expect(Nav2CollisionAction.fromInt(4), Nav2CollisionAction.limit);
    });

    test('fromInt maps an unknown code to unreadable, never doNothing', () {
      // REPAIRED 0.2.0 (was: "degrades unknown to doNothing (caution-add-only)").
      // doNothing is a value nav2 actively publishes; synthesising it for a
      // code we cannot read made a sixth upstream action arrive here as
      // "the monitor wants nothing done".
      expect(Nav2CollisionAction.fromInt(99), Nav2CollisionAction.unreadable);
      expect(Nav2CollisionAction.fromInt(-1), Nav2CollisionAction.unreadable);
      expect(Nav2CollisionAction.fromInt(99), isNot(Nav2CollisionAction.doNothing));
    });
  });

  group('Nav2CollisionMonitorState.fromJson', () {
    test('parses canonical message shape', () {
      final s = Nav2CollisionMonitorState.fromJson(<String, dynamic>{
        'action_type': 1,
        'polygon_name': 'forward_safety',
      });
      expect(s.actionType, Nav2CollisionAction.stop);
      expect(s.polygonName, 'forward_safety');
    });

    test('an absent action_type is unreadable, not doNothing', () {
      // REPAIRED 0.2.0 (was: "tolerates missing fields"). Tolerating a missing
      // action_type meant manufacturing DO_NOTHING for a frame the monitor may
      // have published as STOP. polygon_name '' stays: an absent NAME is
      // genuinely empty, and carries no safety meaning of its own.
      final s = Nav2CollisionMonitorState.fromJson(const <String, dynamic>{});
      expect(s.actionType, Nav2CollisionAction.unreadable);
      expect(s.actionType, isNot(Nav2CollisionAction.doNothing));
      expect(s.polygonName, '');
    });
  });

  group('Nav2CollisionDetectorState.fromJson', () {
    test('parses parallel polygon/detection arrays', () {
      final s = Nav2CollisionDetectorState.fromJson(<String, dynamic>{
        'polygons': <dynamic>['front', 'rear', 'left'],
        'detections': <dynamic>[true, false, true],
      });
      expect(s.polygons, ['front', 'rear', 'left']);
      expect(s.detections, [true, false, true]);
      expect(s.anyDetection, isTrue);
      expect(s.triggeredPolygons, ['front', 'left']);
    });

    test('triggeredPolygons handles length mismatch defensively', () {
      const s = Nav2CollisionDetectorState(
        polygons: ['front', 'rear'],
        detections: [true],
      );
      expect(s.triggeredPolygons, ['front']);
    });
  });

  group('Nav2SafetyMapper', () {
    test('toAdvisory returns null for doNothing', () {
      const state = Nav2CollisionMonitorState(
        actionType: Nav2CollisionAction.doNothing,
        polygonName: '',
      );
      final adv = Nav2SafetyMapper.toAdvisory(
        state,
        DriverProfile.snowZoneExperienced,
      );
      expect(adv, isNull);
    });

    test(
      'toAdvisory returns AlertExplainer for stop / slowdown / approach / limit',
      () {
        for (final action in [
          Nav2CollisionAction.stop,
          Nav2CollisionAction.slowdown,
          Nav2CollisionAction.approach,
          Nav2CollisionAction.limit,
        ]) {
          final state = Nav2CollisionMonitorState(
            actionType: action,
            polygonName: 'forward',
          );
          final adv = Nav2SafetyMapper.toAdvisory(
            state,
            DriverProfile.snowZoneExperienced,
          );
          expect(
            adv,
            isNotNull,
            reason: 'action $action should map to advisory',
          );
          expect(adv!.action, isNotEmpty);
        }
      },
    );
  });

  group('Nav2SafetyLayer', () {
    test('emits advisory string on stop event', () async {
      final layer = Nav2SafetyLayer(
        profile: DriverProfile.snowZoneExperienced,
        throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
      );
      final received = <String>[];
      final sub = layer.advisories.listen(received.add);

      layer.onMonitorState(
        const Nav2CollisionMonitorState(
          actionType: Nav2CollisionAction.stop,
          polygonName: 'forward',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, hasLength(1));
      await sub.cancel();
      await layer.dispose();
    });

    test('does not emit on doNothing', () async {
      final layer = Nav2SafetyLayer(
        profile: DriverProfile.snowZoneExperienced,
        throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
      );
      final received = <String>[];
      final sub = layer.advisories.listen(received.add);

      layer.onMonitorState(
        const Nav2CollisionMonitorState(
          actionType: Nav2CollisionAction.doNothing,
          polygonName: '',
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, isEmpty);
      await sub.cancel();
      await layer.dispose();
    });

    test(
      'detector state with detections emits advisory citing polygon names',
      () async {
        final layer = Nav2SafetyLayer(
          profile: DriverProfile.snowZoneExperienced,
          throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
        );
        final received = <String>[];
        final sub = layer.advisories.listen(received.add);

        layer.onDetectorState(
          const Nav2CollisionDetectorState(
            polygons: ['front', 'rear'],
            detections: [true, false],
          ),
        );

        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(received, hasLength(1));
        expect(received.first, contains('front'));
        await sub.cancel();
        await layer.dispose();
      },
    );

    test('detector state with no detections emits nothing', () async {
      final layer = Nav2SafetyLayer(
        profile: DriverProfile.snowZoneExperienced,
        throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
      );
      final received = <String>[];
      final sub = layer.advisories.listen(received.add);

      layer.onDetectorState(
        const Nav2CollisionDetectorState(
          polygons: ['front'],
          detections: [false],
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(received, isEmpty);
      await sub.cancel();
      await layer.dispose();
    });
  });
}
