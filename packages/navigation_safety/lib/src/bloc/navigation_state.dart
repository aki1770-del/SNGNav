/// Navigation state for an active navigation session.
library;

import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';

import '../models/alert_severity.dart';

enum NavigationStatus {
  idle,
  navigating,
  deviated,
  arrived,
}

class NavigationState extends Equatable {
  final NavigationStatus status;
  final RouteResult? route;
  final int currentManeuverIndex;
  final String? destinationLabel;

  final String? alertMessage;
  final AlertSeverity? alertSeverity;
  final bool alertDismissible;

  const NavigationState({
    required this.status,
    this.route,
    this.currentManeuverIndex = 0,
    this.destinationLabel,
    this.alertMessage,
    this.alertSeverity,
    this.alertDismissible = true,
  });

  const NavigationState.idle()
      : status = NavigationStatus.idle,
        route = null,
        currentManeuverIndex = 0,
        destinationLabel = null,
        alertMessage = null,
        alertSeverity = null,
        alertDismissible = true;

  bool get isNavigating => status == NavigationStatus.navigating;

  bool get hasRoute => route != null && status != NavigationStatus.idle;

  bool get hasSafetyAlert => alertMessage != null;

  RouteManeuver? get currentManeuver {
    if (route == null) return null;
    if (currentManeuverIndex >= route!.maneuvers.length) return null;
    return route!.maneuvers[currentManeuverIndex];
  }

  RouteManeuver? get nextManeuver {
    if (route == null) return null;
    final nextIndex = currentManeuverIndex + 1;
    if (nextIndex >= route!.maneuvers.length) return null;
    return route!.maneuvers[nextIndex];
  }

  double get progress {
    if (route == null || route!.maneuvers.isEmpty) return 0.0;
    if (status == NavigationStatus.arrived) return 1.0;
    return currentManeuverIndex / route!.maneuvers.length;
  }

  NavigationState copyWith({
    NavigationStatus? status,
    RouteResult? route,
    int? currentManeuverIndex,
    String? destinationLabel,
    String? alertMessage,
    AlertSeverity? alertSeverity,
    bool? alertDismissible,
    bool clearAlert = false,
  }) {
    return NavigationState(
      status: status ?? this.status,
      route: route ?? this.route,
      currentManeuverIndex:
          currentManeuverIndex ?? this.currentManeuverIndex,
      destinationLabel: destinationLabel ?? this.destinationLabel,
      alertMessage: clearAlert ? null : (alertMessage ?? this.alertMessage),
      alertSeverity: clearAlert ? null : (alertSeverity ?? this.alertSeverity),
      alertDismissible:
          clearAlert ? true : (alertDismissible ?? this.alertDismissible),
    );
  }

  @override
  List<Object?> get props => [
        status,
        route,
        currentManeuverIndex,
        destinationLabel,
        alertMessage,
        alertSeverity,
        alertDismissible,
      ];

  @override
  String toString() =>
      'NavigationState($status, maneuver=$currentManeuverIndex, alert=${alertMessage != null})';
}