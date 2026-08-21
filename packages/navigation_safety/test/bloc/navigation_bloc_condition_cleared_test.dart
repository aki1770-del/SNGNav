/// SafetyAlertDismissed(conditionCleared: true) tests (0.9.5).
///
/// Locks the hazard-owner clear path: the component that raised an alert
/// can clear it when the condition passes — including non-dismissible
/// alerts — while driver dismissal stays refused for non-dismissible.
/// Before 0.9.5 no code path could clear a non-dismissible alert.
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
  totalDistanceKm: 30.0,
  totalTimeSeconds: 1500,
  summary: '30 km, 25 min',
);

void main() {
  group('SafetyAlertDismissed(conditionCleared: true)', () {
    blocTest<NavigationBloc, NavigationState>(
      'clears a NON-dismissible alert (hazard owner reports condition passed)',
      build: NavigationBloc.new,
      act: (bloc) => bloc
        ..add(NavigationStarted(route: _testRoute))
        ..add(
          const SafetyAlertReceived(
            message: 'Visibility zero - pull over immediately',
            severity: AlertSeverity.critical,
            dismissible: false,
          ),
        )
        ..add(const SafetyAlertDismissed(conditionCleared: true)),
      verify: (bloc) {
        expect(bloc.state.hasSafetyAlert, isFalse);
        expect(bloc.state.alertMessage, isNull);
        expect(bloc.state.alertSeverity, isNull);
        expect(bloc.state.alertScenario, isNull);
        expect(bloc.state.alertCondition, isNull);
        expect(bloc.state.alertDismissible, isTrue); // reset to default
        // Navigation session itself is untouched by the clear.
        expect(bloc.state.status, NavigationStatus.navigating);
        expect(bloc.state.route, isNotNull);
      },
    );

    blocTest<NavigationBloc, NavigationState>(
      'clears a dismissible alert too',
      build: NavigationBloc.new,
      act: (bloc) => bloc
        ..add(
          const SafetyAlertReceived(
            message: 'Snow expected in 30 minutes',
            severity: AlertSeverity.info,
          ),
        )
        ..add(const SafetyAlertDismissed(conditionCleared: true)),
      verify: (bloc) {
        expect(bloc.state.hasSafetyAlert, isFalse);
      },
    );

    blocTest<NavigationBloc, NavigationState>(
      'is a no-op when no alert is active (no state emitted)',
      build: NavigationBloc.new,
      act: (bloc) => bloc.add(const SafetyAlertDismissed(conditionCleared: true)),
      expect: () => const <NavigationState>[],
    );

    blocTest<NavigationBloc, NavigationState>(
      'a new alert can fire after a non-dismissible alert was cleared '
      '(severity floor resets with the clear)',
      build: NavigationBloc.new,
      act: (bloc) => bloc
        ..add(
          const SafetyAlertReceived(
            message: 'Visibility zero - pull over immediately',
            severity: AlertSeverity.critical,
            dismissible: false,
          ),
        )
        ..add(const SafetyAlertDismissed(conditionCleared: true))
        ..add(
          const SafetyAlertReceived(
            message: 'Snow expected in 30 minutes',
            severity: AlertSeverity.info,
          ),
        ),
      verify: (bloc) {
        expect(bloc.state.hasSafetyAlert, isTrue);
        expect(bloc.state.alertMessage, 'Snow expected in 30 minutes');
        expect(bloc.state.alertSeverity, AlertSeverity.info);
      },
    );
  });

  group('non-dismissible contract still holds around the new event', () {
    blocTest<NavigationBloc, NavigationState>(
      'driver dismissal (SafetyAlertDismissed) is STILL refused for a '
      'non-dismissible alert',
      build: NavigationBloc.new,
      act: (bloc) => bloc
        ..add(
          const SafetyAlertReceived(
            message: 'Visibility zero - pull over immediately',
            severity: AlertSeverity.critical,
            dismissible: false,
          ),
        )
        ..add(const SafetyAlertDismissed()),
      verify: (bloc) {
        expect(bloc.state.hasSafetyAlert, isTrue);
        expect(
          bloc.state.alertMessage,
          'Visibility zero - pull over immediately',
        );
        expect(bloc.state.alertDismissible, isFalse);
      },
    );

    blocTest<NavigationBloc, NavigationState>(
      'RerouteCompleted STILL preserves a non-dismissible alert',
      build: NavigationBloc.new,
      act: (bloc) => bloc
        ..add(NavigationStarted(route: _testRoute))
        ..add(
          const SafetyAlertReceived(
            message: 'Ice road ahead',
            severity: AlertSeverity.critical,
            dismissible: false,
          ),
        )
        ..add(const RouteDeviationDetected())
        ..add(RerouteCompleted(newRoute: _rerouteResult)),
      verify: (bloc) {
        expect(bloc.state.status, NavigationStatus.navigating);
        expect(bloc.state.route!.summary, '30 km, 25 min');
        expect(bloc.state.hasSafetyAlert, isTrue);
        expect(bloc.state.alertMessage, 'Ice road ahead');
        expect(bloc.state.alertDismissible, isFalse);
      },
    );
  });
}
