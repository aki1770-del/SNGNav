/// Edge-case tests for NavigationBloc — alert priority, double deviation,
/// ManeuverAdvanced at last index, and state accessor coverage.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';

const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);
const _inuyama = LatLng(35.3883, 136.9394);

final _route = RouteResult(
  shape: const [_nagoya, _inuyama, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head north',
      type: 'depart',
      lengthKm: 10.0,
      timeSeconds: 600,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Turn right',
      type: 'right',
      lengthKm: 8.0,
      timeSeconds: 480,
      position: _inuyama,
    ),
    RouteManeuver(
      index: 2,
      instruction: 'Arrive',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 18.0,
  totalTimeSeconds: 1080,
  summary: '18.0 km, 18 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

final _secondRoute = RouteResult(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head east',
      type: 'depart',
      lengthKm: 25.0,
      timeSeconds: 1500,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Arrive',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 25.0,
  totalTimeSeconds: 1500,
  summary: '25.0 km, 25 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

void main() {
  group('NavigationBloc — ManeuverAdvanced edge cases', () {
    blocTest<NavigationBloc, NavigationState>(
      'advancing at last maneuver emits arrived',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 2, // last index
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.arrived)
            .having((s) => s.currentManeuverIndex, 'index', 2),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'advancing at penultimate maneuver emits arrived',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 1, // nextIndex=2 which equals length-1; still valid
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.currentManeuverIndex, 'index', 2),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'ManeuverAdvanced ignored when not navigating',
      build: NavigationBloc.new,
      seed: () => const NavigationState.idle(),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'ManeuverAdvanced ignored when arrived',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.arrived,
        route: _route,
        currentManeuverIndex: 2,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'ManeuverAdvanced ignored when route is null',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.navigating,
      ),
      act: (bloc) => bloc.add(const ManeuverAdvanced()),
      expect: () => [],
    );
  });

  group('NavigationBloc — alert priority', () {
    blocTest<NavigationBloc, NavigationState>(
      'higher severity replaces existing alert',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'Watch for ice',
        alertSeverity: AlertSeverity.info,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Black ice detected!',
        severity: AlertSeverity.critical,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.alertMessage, 'msg', 'Black ice detected!')
            .having((s) => s.alertSeverity, 'sev', AlertSeverity.critical),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'lower severity is suppressed by existing higher alert',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'Blizzard warning',
        alertSeverity: AlertSeverity.critical,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Light rain ahead',
        severity: AlertSeverity.info,
      )),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'same severity replaces existing alert',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'First warning',
        alertSeverity: AlertSeverity.warning,
      ),
      act: (bloc) => bloc.add(const SafetyAlertReceived(
        message: 'Second warning',
        severity: AlertSeverity.warning,
      )),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.alertMessage, 'msg', 'Second warning')
            .having((s) => s.alertSeverity, 'sev', AlertSeverity.warning),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'non-dismissible alert blocks dismiss',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'Critical: chains required',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: false,
      ),
      act: (bloc) => bloc.add(const SafetyAlertDismissed()),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'dismissible alert clears on dismiss',
      build: NavigationBloc.new,
      seed: () => const NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'Light fog ahead',
        alertSeverity: AlertSeverity.info,
        alertDismissible: true,
      ),
      act: (bloc) => bloc.add(const SafetyAlertDismissed()),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.alertMessage, 'msg', isNull)
            .having((s) => s.alertSeverity, 'sev', isNull),
      ],
    );
  });

  group('NavigationBloc — deviation edge cases', () {
    blocTest<NavigationBloc, NavigationState>(
      'double deviation is no-op on second event',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _route,
      ),
      act: (bloc) => bloc.add(const RouteDeviationDetected()),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'deviation ignored when idle',
      build: NavigationBloc.new,
      seed: () => const NavigationState.idle(),
      act: (bloc) => bloc.add(const RouteDeviationDetected()),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'reroute ignored when not deviated',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
      ),
      act: (bloc) =>
          bloc.add(RerouteCompleted(newRoute: _secondRoute)),
      expect: () => [],
    );

    blocTest<NavigationBloc, NavigationState>(
      'reroute resets maneuver index to 0',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _route,
        currentManeuverIndex: 2,
      ),
      act: (bloc) =>
          bloc.add(RerouteCompleted(newRoute: _secondRoute)),
      expect: () => [
        isA<NavigationState>()
            .having((s) => s.status, 'status', NavigationStatus.navigating)
            .having((s) => s.route, 'route', _secondRoute)
            .having((s) => s.currentManeuverIndex, 'index', 0),
      ],
    );
  });

  group('NavigationState — accessor coverage', () {
    test('currentManeuver returns correct maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 1,
      );
      expect(state.currentManeuver?.instruction, 'Turn right');
    });

    test('currentManeuver null when out of bounds', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 99,
      );
      expect(state.currentManeuver, isNull);
    });

    test('nextManeuver returns the maneuver after current', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 0,
      );
      expect(state.nextManeuver?.instruction, 'Turn right');
    });

    test('nextManeuver null at last maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 2,
      );
      expect(state.nextManeuver, isNull);
    });

    test('progress is 0.0 with no route', () {
      const state = NavigationState(status: NavigationStatus.navigating);
      expect(state.progress, 0.0);
    });

    test('progress is 1.0 when arrived', () {
      final state = NavigationState(
        status: NavigationStatus.arrived,
        route: _route,
        currentManeuverIndex: 2,
      );
      expect(state.progress, 1.0);
    });

    test('progress proportional during navigation', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 1,
      );
      expect(state.progress, closeTo(1 / 3, 0.01));
    });

    test('hasRoute false for idle even with route', () {
      final state = NavigationState(
        status: NavigationStatus.idle,
        route: _route,
      );
      expect(state.hasRoute, isFalse);
    });

    test('hasRoute true when navigating with route', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
      );
      expect(state.hasRoute, isTrue);
    });

    test('hasSafetyAlert true when alert message present', () {
      const state = NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'Snow ahead',
        alertSeverity: AlertSeverity.warning,
      );
      expect(state.hasSafetyAlert, isTrue);
    });

    test('hasSafetyAlert false when no alert', () {
      const state = NavigationState(status: NavigationStatus.navigating);
      expect(state.hasSafetyAlert, isFalse);
    });

    test('toString includes status and maneuver', () {
      final state = NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        currentManeuverIndex: 1,
        alertMessage: 'Ice',
      );
      final str = state.toString();
      expect(str, contains('navigating'));
      expect(str, contains('maneuver=1'));
      expect(str, contains('alert=true'));
    });
  });

  group('Alert lifecycle', () {
    blocTest<NavigationBloc, NavigationState>(
      'alert cleared when reroute completes',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.deviated,
        route: _route,
        alertMessage: 'Icy conditions ahead',
        alertSeverity: AlertSeverity.warning,
      ),
      act: (bloc) => bloc.add(RerouteCompleted(newRoute: _route)),
      expect: () => [
        predicate<NavigationState>(
          (s) => s.status == NavigationStatus.navigating && s.alertMessage == null,
          'navigating with no alert',
        ),
      ],
    );

    blocTest<NavigationBloc, NavigationState>(
      'non-dismissible alert preserved across navigation stop',
      build: NavigationBloc.new,
      seed: () => NavigationState(
        status: NavigationStatus.navigating,
        route: _route,
        alertMessage: 'Black ice — pull over',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: false,
      ),
      act: (bloc) => bloc.add(const NavigationStopped()),
      expect: () => [
        predicate<NavigationState>(
          (s) =>
              s.status == NavigationStatus.idle &&
              s.alertMessage == 'Black ice — pull over' &&
              s.alertSeverity == AlertSeverity.critical &&
              !s.alertDismissible,
          'idle with non-dismissible critical alert preserved',
        ),
      ],
    );
  });
}
