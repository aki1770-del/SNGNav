/// Navigation events - inputs to the navigation session state machine.
library;

import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';

import '../models/alert_severity.dart';

sealed class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => [];
}

class NavigationStarted extends NavigationEvent {
  final RouteResult route;
  final String? destinationLabel;

  const NavigationStarted({
    required this.route,
    this.destinationLabel,
  });

  @override
  List<Object?> get props => [route, destinationLabel];
}

class NavigationStopped extends NavigationEvent {
  const NavigationStopped();
}

class ManeuverAdvanced extends NavigationEvent {
  const ManeuverAdvanced();
}

class RouteDeviationDetected extends NavigationEvent {
  final String? reason;

  const RouteDeviationDetected({this.reason});

  @override
  List<Object?> get props => [reason];
}

class RerouteCompleted extends NavigationEvent {
  final RouteResult newRoute;

  const RerouteCompleted({required this.newRoute});

  @override
  List<Object?> get props => [newRoute];
}

class SafetyAlertReceived extends NavigationEvent {
  final String message;
  final AlertSeverity severity;
  final bool dismissible;

  const SafetyAlertReceived({
    required this.message,
    required this.severity,
    this.dismissible = true,
  });

  @override
  List<Object?> get props => [message, severity, dismissible];
}

class SafetyAlertDismissed extends NavigationEvent {
  const SafetyAlertDismissed();
}