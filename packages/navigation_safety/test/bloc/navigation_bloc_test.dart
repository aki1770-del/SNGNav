/// NavigationBloc unit tests - session lifecycle, state model, and safety alerts.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);
const _inuyama = LatLng(35.3883, 136.9394);

final _testRoute = NavigationRoute(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    NavigationManeuver(
      index: 0,
      instruction: 'Head east on Route 153',
      type: 'depart',
      lengthKm: 12.5,
      timeSeconds: 720,
      position: _nagoya,
    ),
    NavigationManeuver(
      index: 1,
      instruction: 'Turn right onto Route 248',
      type: 'right',
      lengthKm: 8.2,
      timeSeconds: 480,
      position: LatLng(35.1100, 137.0200),
    ),
    NavigationManeuver(
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
);

final _rerouteResult = NavigationRoute(
  shape: const [_nagoya, _inuyama, _toyota],
  maneuvers: const [
    NavigationManeuver(
      index: 0,
      instruction: 'Head north to Inuyama bypass',
      type: 'depart',
      lengthKm: 18.0,
      timeSeconds: 900,
      position: _nagoya,
    ),
    NavigationManeuver(
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
);

final _shortRoute = NavigationRoute(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    NavigationManeuver(
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
);

void main() {
  group('NavigationState', () {
    test('idle has no route and no alert', () {
      const state = NavigationState.idle();
      expect(state.status, NavigationStatus.idle);
      expect(state.isNavigating, isFalse);
      expect(state.hasRoute, isFalse);
      expect(state.hasSafetyAlert, isFalse);
      expect(state.route, isNull);
    });

    test('currentManeuver returns correct item', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );

      expect(state.currentManeuver?.instruction, 'Turn right onto Route 248');
    });

    test('nextManeuver returns next item', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 0,
      );

      expect(state.nextManeuver?.instruction, 'Turn right onto Route 248');
    });

    test('currentManeuver is null when index exceeds route length', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: _testRoute.maneuvers.length,
      );

      expect(state.currentManeuver, isNull);
    });

    test('nextManeuver is null at final maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: _testRoute.maneuvers.length - 1,
      );

      expect(state.nextManeuver, isNull);
    });

    test('progress reflects maneuver index while navigating', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      );

      expect(state.progress, closeTo(1 / 3, 0.0001));
    });

    test('progress is zero when route has no maneuvers', () {
      final emptyRoute = NavigationRoute(
        shape: const [_nagoya, _toyota],
        maneuvers: const [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '0 km, 0 min',
      );

      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: emptyRoute,
      );

      expect(state.progress, 0.0);
    });

    test('progress reaches 1.0 when arrived', () {
      final state = NavigationState(
        status: NavigationStatus.arrived,
        route: _testRoute,
        currentManeuverIndex: 2,
      );

      expect(state.progress, 1.0);
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
    });
  });

  group('NavigationBloc', () {
    test('initial state is idle', () {
      final bloc = NavigationBloc();
      expect(bloc.state, const NavigationState.idle());
      bloc.close();
    });

    blocTest<NavigationBloc, NavigationState>(
      'idle to navigating on start',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(NavigationStarted(
        route: _testRoute,
        destinationLabel: 'Toyota HQ',
      )),
      expect: () => [
        isA<NavigationState>()
            .having((state) => state.status, 'status', NavigationStatus.navigating)
            .having((state) => state.route, 'route', _testRoute)
            .having((state) => state.destinationLabel, 'label', 'Toyota HQ'),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'navigating to idle on stop',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [const NavigationState.idle()],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advance through maneuvers to arrived',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 0,
      ),
      act: (bloc) {
        bloc.add(const ManeuverAdvanced());
        bloc.add(const ManeuverAdvanced());
        bloc.add(const ManeuverAdvanced());
      },
      expect: () => [
        isA<NavigationState>().having((state) => state.currentManeuverIndex, 'index', 1),
        isA<NavigationState>().having((state) => state.currentManeuverIndex, 'index', 2),
        isA<NavigationState>().having((state) => state.status, 'status', NavigationStatus.arrived),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'single-maneuver route arrives immediately on advance',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _shortRoute,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [
        isA<NavigationState>().having((state) => state.status, 'status', NavigationStatus.arrived),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'navigating to deviated on deviation',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        currentManeuverIndex: 1,
      ),
      act: (bloc) => bloc.add(const RouteDeviationDetected(reason: 'off-route')),
      expect: () => [
        isA<NavigationState>()
            .having((state) => state.status, 'status', NavigationStatus.deviated)
            .having((state) => state.currentManeuverIndex, 'index', 1),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'deviated to navigating on reroute completed',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _testRoute,
        currentManeuverIndex: 1,
        destinationLabel: 'Toyota HQ',
      ),
      act: (bloc) => bloc.add(RerouteCompleted(newRoute: _rerouteResult)),
      expect: () => [
        isA<NavigationState>()
            .having((state) => state.status, 'status', NavigationStatus.navigating)
            .having((state) => state.route, 'route', _rerouteResult)
            .having((state) => state.currentManeuverIndex, 'index', 0)
            .having((state) => state.destinationLabel, 'label', 'Toyota HQ'),
      ],
    );

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
            .having((state) => state.status, 'status', NavigationStatus.navigating)
            .having((state) => state.alertMessage, 'message', 'Icy road conditions ahead')
            .having((state) => state.alertSeverity, 'severity', AlertSeverity.warning),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'critical alert can be non-dismissible',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Visibility zero - pull over immediately',
        severity: AlertSeverity.critical,
        dismissible: false,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((state) => state.alertSeverity, 'severity', AlertSeverity.critical)
            .having((state) => state.alertDismissible, 'dismissible', isFalse),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'lower-severity alert does not replace an existing critical alert',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Fleet reports: icy road conditions detected',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: false,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Heavy snow - reduced traction and visibility',
        severity: AlertSeverity.warning,
      )),
      expect: () => <NavigationState>[],
      verify: (bloc) {
        expect(bloc.state.alertSeverity, AlertSeverity.critical);
        expect(bloc.state.alertMessage, 'Fleet reports: icy road conditions detected');
        expect(bloc.state.alertDismissible, isFalse);
      },
    );

    blocTest<NavigationBloc, NavigationState>(
      'higher-severity alert replaces an existing warning alert',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Heavy snow - reduced traction and visibility',
        alertSeverity: AlertSeverity.warning,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Fleet reports: icy road conditions detected',
        severity: AlertSeverity.critical,
        dismissible: false,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((state) => state.alertSeverity, 'severity', AlertSeverity.critical)
            .having((state) => state.alertMessage, 'message', 'Fleet reports: icy road conditions detected')
            .having((state) => state.alertDismissible, 'dismissible', isFalse),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'dismissible alert can be cleared',
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
        isA<NavigationState>().having((state) => state.hasSafetyAlert, 'hasSafetyAlert', isFalse),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'ignores maneuver advance while idle',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'ignores route deviation while idle',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const RouteDeviationDetected(reason: 'off-route')),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'ignores reroute completion unless deviated',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
      ),
      act: (bloc) => bloc.add(RerouteCompleted(newRoute: _rerouteResult)),
      expect: () => <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'non-dismissible alert cannot be cleared',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Pull over immediately',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: false,
      ),
      act: (bloc) => bloc.add(const SafetyAlertDismissed()),
      expect: () => <NavigationState>[],
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
            .having((state) => state.status, 'status', NavigationStatus.navigating)
            .having((state) => state.alertMessage, 'message', 'Snow warning active'),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'stop clears route but preserves active safety alert state',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _testRoute,
        alertMessage: 'Snow warning active',
        alertSeverity: AlertSeverity.warning,
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [
        const NavigationState(
          status: NavigationStatus.idle,
          alertMessage: 'Snow warning active',
          alertSeverity: AlertSeverity.warning,
        ),
      ],
    );
  });
}