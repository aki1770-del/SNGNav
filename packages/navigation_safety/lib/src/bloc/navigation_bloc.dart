/// Navigation session BLoC with advisory safety alerts.
library;

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/alert_severity.dart';
import 'navigation_event.dart';
import 'navigation_state.dart';

/// Returns true if [incoming] severity should replace [current].
/// Prevents alert downgrade: lower severity never replaces higher.
bool _canUpdateSeverity(AlertSeverity incoming, AlertSeverity? current) {
  if (current == null) return true;
  const order = {
    AlertSeverity.info: 0,
    AlertSeverity.warning: 1,
    AlertSeverity.critical: 2,
  };
  return order[incoming]! >= order[current]!;
}

class NavigationBloc extends Bloc<NavigationEvent, NavigationState> {
  NavigationBloc() : super(const NavigationState.idle()) {
    on<NavigationStarted>(_onStarted);
    on<NavigationStopped>(_onStopped);
    on<ManeuverAdvanced>(_onManeuverAdvanced);
    on<RouteDeviationDetected>(_onDeviation);
    on<RerouteCompleted>(_onRerouteCompleted);
    on<SafetyAlertReceived>(_onSafetyAlert);
    on<SafetyAlertDismissed>(_onAlertDismissed);
  }

  void _onStarted(
    NavigationStarted event,
    Emitter<NavigationState> emit,
  ) {
    emit(NavigationState(
      status: NavigationStatus.navigating,
      route: event.route,
      currentManeuverIndex: 0,
      destinationLabel: event.destinationLabel,
      alertMessage: state.alertMessage,
      alertSeverity: state.alertSeverity,
      alertDismissible: state.alertDismissible,
      alertScenario: state.alertScenario,
    ));
  }

  void _onStopped(
    NavigationStopped event,
    Emitter<NavigationState> emit,
  ) {
    emit(NavigationState(
      status: NavigationStatus.idle,
      alertMessage: state.alertMessage,
      alertSeverity: state.alertSeverity,
      alertDismissible: state.alertDismissible,
      alertScenario: state.alertScenario,
    ));
  }

  void _onManeuverAdvanced(
    ManeuverAdvanced event,
    Emitter<NavigationState> emit,
  ) {
    if (state.status != NavigationStatus.navigating) return;
    if (state.route == null) return;

    final nextIndex = state.currentManeuverIndex + 1;
    final totalManeuvers = state.route!.maneuvers.length;

    if (totalManeuvers == 0 || nextIndex >= totalManeuvers) {
      emit(state.copyWith(
        status: NavigationStatus.arrived,
        currentManeuverIndex: totalManeuvers > 0 ? totalManeuvers - 1 : 0,
      ));
    } else {
      emit(state.copyWith(currentManeuverIndex: nextIndex));
    }
  }

  void _onDeviation(
    RouteDeviationDetected event,
    Emitter<NavigationState> emit,
  ) {
    if (state.status != NavigationStatus.navigating) return;

    emit(state.copyWith(status: NavigationStatus.deviated));
  }

  void _onRerouteCompleted(
    RerouteCompleted event,
    Emitter<NavigationState> emit,
  ) {
    if (state.status != NavigationStatus.deviated) return;

    emit(state.copyWith(
      status: NavigationStatus.navigating,
      route: event.newRoute,
      currentManeuverIndex: 0,
      // Only clear dismissible alerts — non-dismissible safety alerts persist
      // through reroutes (e.g. "ice road ahead" must not be silenced by reroute).
      clearAlert: state.alertDismissible,
    ));
  }

  void _onSafetyAlert(
    SafetyAlertReceived event,
    Emitter<NavigationState> emit,
  ) {
    if (!_canUpdateSeverity(event.severity, state.alertSeverity)) return;

    final Stopwatch? sw = kDebugMode ? (Stopwatch()..start()) : null;

    emit(state.copyWith(
      alertMessage: event.message,
      alertSeverity: event.severity,
      alertDismissible: event.dismissible,
      alertScenario: event.scenario,
    ));

    assert(() {
      sw?.stop();
      final elapsed = sw?.elapsedMilliseconds ?? 0;
      if (elapsed > 500) {
        // ignore: avoid_print
        print(
          '[navigation_safety] LATENCY WARNING: SafetyAlertReceived '
          'processing took ${elapsed}ms (OODA orient budget: 500ms)',
        );
      }
      return true;
    }());
  }

  void _onAlertDismissed(
    SafetyAlertDismissed event,
    Emitter<NavigationState> emit,
  ) {
    if (!state.alertDismissible) return;

    emit(state.copyWith(clearAlert: true));
  }
}
