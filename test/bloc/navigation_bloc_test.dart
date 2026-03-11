/// NavigationBloc unit tests — navigation session lifecycle + safety alerts.
///
/// Tests the complete state machine with pure events — no providers needed.
/// NavigationBloc has no external dependencies (unlike LocationBloc/RoutingBloc).
///
/// Sprint 7 Day 4 — NavigationBloc extraction.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:routing_engine/routing_engine.dart';

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);
const _inuyama = LatLng(35.3883, 136.9394);

final _testRoute = RouteResult(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head east on Route 153',
      type: 'depart',
      lengthKm: 12.5,
      timeSeconds: 720,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Turn right onto Route 248',
      type: 'right',
      lengthKm: 8.2,
      timeSeconds: 480,
      position: LatLng(35.1100, 137.0200),
    ),
    RouteManeuver(
      index: 2,
      instruction: 'Arrive at Toyota HQ',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 25.7,
  totalTimeSeconds: 1200,
  summary: '25.7 km, 20 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

final _rerouteResult = RouteResult(
  shape: const [_nagoya, _inuyama, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head north to Inuyama bypass',
      type: 'depart',
      lengthKm: 18.0,
      timeSeconds: 900,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Arrive at Toyota HQ',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 32.0,
  totalTimeSeconds: 1800,
  summary: '32.0 km, 30 min (via Inuyama bypass)',
  engineInfo: const EngineInfo(name: 'mock'),
);

final _shortRoute = RouteResult(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Arrive',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 1.0,
  totalTimeSeconds: 60,
  summary: '1.0 km, 1 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('NavigationState model', () {
    test('idle has no route, no alert', () {
      const state = NavigationState.idle();
      expect(state.status, equals(NavigationStatus.idle));
      expect(state.isNavigating, isFalse);
      expect(state.hasRoute, isFalse);
      expect(state.hasSafetyAlert, isFalse);
      expect(state.route, isNull);
      expect(state.currentManeuverIndex, equals(0));
      expect(state.destinationLabel, isNull);
      expect(state.alertMessage, isNull);
    });

    test('isNavigating true only when navigating', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      );
      expect(state.isNavigating, isTrue);
    });

    test('isNavigating false when deviated', () {
      final state = NavigationState(
        status: NavigationStatus.deviated,
        route: _testRoute,
      );
      expect(state.isNavigating, isFalse);
    });

    test('hasRoute true when navigating with route', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      );
      expect(state.hasRoute, isTrue);
    });

    test('hasRoute true when deviated (still has route)', () {
      final state = NavigationState(
        status: NavigationStatus.deviated,
        route: _testRoute,
      );
      expect(state.hasRoute, isTrue);
    });

    test('hasRoute false when idle', () {
      const state = NavigationState(status: NavigationStatus.idle);
      expect(state.hasRoute, isFalse);
    });

    test('currentManeuver returns correct maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );
      expect(state.currentManeuver!.instruction,
          equals('Turn right onto Route 248'));
    });

    test('currentManeuver null when no route', () {
      const state = NavigationState(status: NavigationStatus.idle);
      expect(state.currentManeuver, isNull);
    });

    test('currentManeuver null when index out of bounds', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 99,
      );
      expect(state.currentManeuver, isNull);
    });

    test('nextManeuver returns maneuver at index+1', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 0,
      );
      expect(state.nextManeuver!.instruction,
          equals('Turn right onto Route 248'));
    });

    test('nextManeuver null at last maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 2,
      );
      expect(state.nextManeuver, isNull);
    });

    test('progress is 0.0 when no route', () {
      const state = NavigationState(status: NavigationStatus.idle);
      expect(state.progress, equals(0.0));
    });

    test('progress is 0.0 at first maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 0,
      );
      expect(state.progress, equals(0.0));
    });

    test('progress is 1/3 at second maneuver (3 total)', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );
      expect(state.progress, closeTo(1.0 / 3.0, 0.01));
    });

    test('progress is 1.0 when arrived', () {
      final state = NavigationState(
        status: NavigationStatus.arrived,
        route: _testRoute,
        currentManeuverIndex: 2,
      );
      expect(state.progress, equals(1.0));
    });

    test('hasSafetyAlert true when alert message present', () {
      const state = NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'Ice ahead',
        alertSeverity: AlertSeverity.warning,
      );
      expect(state.hasSafetyAlert, isTrue);
    });

    test('copyWith preserves fields', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
        destinationLabel: 'Toyota HQ',
        alertMessage: 'Snow',
        alertSeverity: AlertSeverity.info,
      );
      final updated = state.copyWith(currentManeuverIndex: 2);
      expect(updated.route, equals(_testRoute));
      expect(updated.destinationLabel, equals('Toyota HQ'));
      expect(updated.currentManeuverIndex, equals(2));
      expect(updated.alertMessage, equals('Snow'));
    });

    test('copyWith clearAlert removes alert fields', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Ice',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: false,
      );
      final cleared = state.copyWith(clearAlert: true);
      expect(cleared.alertMessage, isNull);
      expect(cleared.alertSeverity, isNull);
      expect(cleared.alertDismissible, isTrue);
      expect(cleared.route, equals(_testRoute)); // route preserved
    });

    test('equality works (Equatable)', () {
      final a = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );
      final b = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );
      expect(a, equals(b));
    });

    test('toString includes status and maneuver index', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );
      final s = state.toString();
      expect(s, contains('navigating'));
      expect(s, contains('1'));
    });
  });

  group('NavigationEvent', () {
    test('events are equatable', () {
      expect(
        NavigationStarted(route: _testRoute, destinationLabel: 'Toyota'),
        equals(NavigationStarted(
            route: _testRoute, destinationLabel: 'Toyota')),
      );
      expect(
        const NavigationStopped(),
        equals(const NavigationStopped()),
      );
      expect(
        const ManeuverAdvanced(),
        equals(const ManeuverAdvanced()),
      );
      expect(
        const RouteDeviationDetected(reason: 'off-route'),
        equals(const RouteDeviationDetected(reason: 'off-route')),
      );
      expect(
        const SafetyAlertDismissed(),
        equals(const SafetyAlertDismissed()),
      );
    });
  });

  group('AlertSeverity', () {
    test('has three levels', () {
      expect(AlertSeverity.values.length, equals(3));
      expect(AlertSeverity.values,
          containsAll([AlertSeverity.info, AlertSeverity.warning,
                       AlertSeverity.critical]));
    });
  });

  group('NavigationBloc — initial state', () {
    test('initial state is idle', () {
      final bloc = NavigationBloc();
      expect(bloc.state, equals(const NavigationState.idle()));
      bloc.close();
    });
  });

  group('NavigationBloc — session lifecycle', () {
    blocTest<NavigationBloc, NavigationState>(
      'idle → navigating on start',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(NavigationStarted(
        route: _testRoute,
        destinationLabel: 'Toyota HQ',
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.navigating)
            .having((s) => s.route, 'route', _testRoute)
            .having((s) => s.currentManeuverIndex, 'index', 0)
            .having((s) => s.destinationLabel, 'label', 'Toyota HQ'),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'navigating → idle on stop',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        destinationLabel: 'Toyota HQ',
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [const NavigationState.idle()],
    );

    blocTest<NavigationBloc, NavigationState>(
      'arrived → idle on stop',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.arrived,
        route: _testRoute,
        currentManeuverIndex: 2,
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [const NavigationState.idle()],
    );

    blocTest<NavigationBloc, NavigationState>(
      'deviated → idle on stop',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _testRoute,
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [const NavigationState.idle()],
    );

    blocTest<NavigationBloc, NavigationState>(
      'idle → idle on stop (idempotent)',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [const NavigationState.idle()],
    );
  });

  group('NavigationBloc — maneuver advancement', () {
    blocTest<NavigationBloc, NavigationState>(
      'advance from index 0 → 1',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 0,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.currentManeuverIndex, 'index', 1)
            .having((s) => s.status, 'status', NavigationStatus.navigating),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance to last maneuver → arrived',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 2, // last maneuver (index 2 of 3)
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.arrived)
            .having((s) => s.currentManeuverIndex, 'index', 2),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance through all maneuvers to arrival (3-step route)',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 0,
      ),
      act: (bloc) {
        bloc.add(const ManeuverAdvanced()); // 0 → 1
        bloc.add(const ManeuverAdvanced()); // 1 → 2
        bloc.add(const ManeuverAdvanced()); // 2 → arrived
      },
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.currentManeuverIndex, 'index', 1),
        isA<NavigationState>()
            .having((s) => s.currentManeuverIndex, 'index', 2),
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.arrived),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance single-maneuver route → arrived immediately',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _shortRoute,
        currentManeuverIndex: 0,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.arrived),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance ignored when idle',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance ignored when arrived',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.arrived,
        route: _testRoute,
        currentManeuverIndex: 2,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance ignored when deviated',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _testRoute,
        currentManeuverIndex: 1,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => <NavigationState>[],
    );
  });

  group('NavigationBloc — deviation and reroute', () {
    blocTest<NavigationBloc, NavigationState>(
      'navigating → deviated on deviation',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      ),
      act: (bloc) => bloc.add(
          const RouteDeviationDetected(reason: 'off-route')),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.deviated)
            .having((s) => s.currentManeuverIndex, 'index', 1),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'deviation ignored when idle',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const RouteDeviationDetected()),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'deviated → navigating on reroute completed',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _testRoute,
        currentManeuverIndex: 1,
        destinationLabel: 'Toyota HQ',
      ),
      act: (bloc) =>
          bloc.add(RerouteCompleted(newRoute: _rerouteResult)),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.navigating)
            .having((s) => s.route, 'route', _rerouteResult)
            .having((s) => s.currentManeuverIndex, 'index', 0)
            .having((s) => s.destinationLabel, 'label', 'Toyota HQ'),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'reroute ignored when navigating (not deviated)',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      ),
      act: (bloc) =>
          bloc.add(RerouteCompleted(newRoute: _rerouteResult)),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'reroute ignored when idle',
      build: NavigationBloc.new,
      act: (bloc) =>
          bloc.add(RerouteCompleted(newRoute: _rerouteResult)),
      expect: () => <NavigationState>[],
    );
  });

  group('NavigationBloc — safety alerts', () {
    blocTest<NavigationBloc, NavigationState>(
      'alert received while navigating',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Icy road conditions ahead',
        severity: AlertSeverity.warning,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.navigating)
            .having((s) => s.alertMessage, 'msg', 'Icy road conditions ahead')
            .having((s) => s.alertSeverity, 'sev', AlertSeverity.warning)
            .having((s) => s.alertDismissible, 'dismissible', isTrue)
            .having((s) => s.currentManeuverIndex, 'index', 1),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'alert received while idle (weather can arrive before nav)',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Snow expected in 30 minutes',
        severity: AlertSeverity.info,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.idle)
            .having((s) => s.hasSafetyAlert, 'hasAlert', isTrue)
            .having((s) => s.alertMessage, 'msg',
                'Snow expected in 30 minutes'),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'critical non-dismissible alert',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Visibility zero — pull over immediately',
        severity: AlertSeverity.critical,
        dismissible: false,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.alertSeverity, 'sev', AlertSeverity.critical)
            .having((s) => s.alertDismissible, 'dismissible', isFalse),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'dismiss dismissible alert',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Snow ahead',
        alertSeverity: AlertSeverity.info,
        alertDismissible: true,
      ),
      act: (bloc) => bloc.add(const SafetyAlertDismissed()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.hasSafetyAlert, 'hasAlert', isFalse)
            .having((s) => s.alertMessage, 'msg', isNull)
            .having((s) => s.status, 'status', NavigationStatus.navigating),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'dismiss ignored for non-dismissible alert',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Pull over',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: false,
      ),
      act: (bloc) => bloc.add(const SafetyAlertDismissed()),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'alert replaces previous alert',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Old alert',
        alertSeverity: AlertSeverity.info,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'New critical alert',
        severity: AlertSeverity.critical,
        dismissible: false,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.alertMessage, 'msg', 'New critical alert')
            .having((s) => s.alertSeverity, 'sev', AlertSeverity.critical),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'alert preserved across navigation start',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.idle,
        alertMessage: 'Snow warning active',
        alertSeverity: AlertSeverity.warning,
      ),
      act: (bloc) => bloc.add(NavigationStarted(
        route: _testRoute,
        destinationLabel: 'Toyota HQ',
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.navigating)
            .having((s) => s.alertMessage, 'msg', 'Snow warning active')
            .having((s) => s.route, 'route', _testRoute),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'alert preserved on navigation stop',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Ice ahead',
        alertSeverity: AlertSeverity.warning,
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [
        const NavigationState(
          status: NavigationStatus.idle,
          alertMessage: 'Ice ahead',
          alertSeverity: AlertSeverity.warning,
        ),
      ],
    );
  });
}
