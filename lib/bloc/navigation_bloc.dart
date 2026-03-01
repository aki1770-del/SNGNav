/// NavigationBloc — active navigation session state machine.
///
/// Manages the turn-by-turn guidance lifecycle:
///   idle → navigating → (deviated → navigating) → arrived → idle
///
/// Domain separation:
///   [RoutingBloc]     — route *calculation* (engine ↔ request ↔ result)
///   [NavigationBloc]  — navigation *session* (guidance, maneuvers, alerts)
///
/// NavigationBloc receives [RouteResult] objects from RoutingBloc via
/// widget mediation. No direct BLoC-to-BLoC wiring.
///
/// Safety alerts live here — SafetyOverlay (Z=2) reads this BLoC's
/// state to display safety-critical information above all content.
///
/// SafetyOverlay (Z=2) reads this BLoC's state for safety-critical display.
library;

import 'package:flutter_bloc/flutter_bloc.dart';

import 'navigation_event.dart';
import 'navigation_state.dart';

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
      // Preserve active safety alert across route start
      alertMessage: state.alertMessage,
      alertSeverity: state.alertSeverity,
      alertDismissible: state.alertDismissible,
    ));
  }

  void _onStopped(
    NavigationStopped event,
    Emitter<NavigationState> emit,
  ) {
    emit(const NavigationState.idle());
  }

  void _onManeuverAdvanced(
    ManeuverAdvanced event,
    Emitter<NavigationState> emit,
  ) {
    // Only advance when actively navigating with a route.
    if (state.status != NavigationStatus.navigating) return;
    if (state.route == null) return;

    final nextIndex = state.currentManeuverIndex + 1;
    final totalManeuvers = state.route!.maneuvers.length;

    if (nextIndex >= totalManeuvers) {
      // Last maneuver reached → arrived.
      emit(state.copyWith(
        status: NavigationStatus.arrived,
        currentManeuverIndex: totalManeuvers - 1,
      ));
    } else {
      emit(state.copyWith(currentManeuverIndex: nextIndex));
    }
  }

  void _onDeviation(
    RouteDeviationDetected event,
    Emitter<NavigationState> emit,
  ) {
    // Only deviate when actively navigating.
    if (state.status != NavigationStatus.navigating) return;

    emit(state.copyWith(status: NavigationStatus.deviated));
  }

  void _onRerouteCompleted(
    RerouteCompleted event,
    Emitter<NavigationState> emit,
  ) {
    // Accept reroute from deviated state — resume navigating with new route.
    if (state.status != NavigationStatus.deviated) return;

    emit(state.copyWith(
      status: NavigationStatus.navigating,
      route: event.newRoute,
      currentManeuverIndex: 0,
    ));
  }

  void _onSafetyAlert(
    SafetyAlertReceived event,
    Emitter<NavigationState> emit,
  ) {
    // Safety alerts overlay independently of navigation status.
    emit(state.copyWith(
      alertMessage: event.message,
      alertSeverity: event.severity,
      alertDismissible: event.dismissible,
    ));
  }

  void _onAlertDismissed(
    SafetyAlertDismissed event,
    Emitter<NavigationState> emit,
  ) {
    // Only dismiss if the current alert is dismissible.
    if (!state.alertDismissible) return;

    emit(state.copyWith(clearAlert: true));
  }
}
