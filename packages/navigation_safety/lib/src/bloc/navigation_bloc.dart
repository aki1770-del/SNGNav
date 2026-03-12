/// Navigation session BLoC with advisory safety alerts.
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
      alertMessage: state.alertMessage,
      alertSeverity: state.alertSeverity,
      alertDismissible: state.alertDismissible,
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

    if (nextIndex >= totalManeuvers) {
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
    ));
  }

  void _onSafetyAlert(
    SafetyAlertReceived event,
    Emitter<NavigationState> emit,
  ) {
    final currentSeverity = state.alertSeverity;
    if (currentSeverity != null &&
        event.severity.index < currentSeverity.index) {
      return;
    }

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
    if (!state.alertDismissible) return;

    emit(state.copyWith(clearAlert: true));
  }
}