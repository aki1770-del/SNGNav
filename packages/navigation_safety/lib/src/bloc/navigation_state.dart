/// Navigation state for an active navigation session.
library;

import 'package:equatable/equatable.dart';

import 'package:navigation_safety_core/navigation_safety_core.dart';



enum NavigationStatus {
  idle,
  navigating,
  deviated,
  arrived,
}

class NavigationState extends Equatable {
  final NavigationStatus status;
  final NavigationRoute? route;
  final int currentManeuverIndex;
  final String? destinationLabel;

  final String? alertMessage;
  final AlertSeverity? alertSeverity;
  final bool alertDismissible;

  /// Structured scenario coordinate for the active alert.
  /// Null when no alert is active or when the alert has no scenario context.
  final SafetyScenario? alertScenario;

  const NavigationState({
    required this.status,
    this.route,
    this.currentManeuverIndex = 0,
    this.destinationLabel,
    this.alertMessage,
    this.alertSeverity,
    this.alertDismissible = true,
    this.alertScenario,
  });

  const NavigationState.idle()
      : status = NavigationStatus.idle,
        route = null,
        currentManeuverIndex = 0,
        destinationLabel = null,
        alertMessage = null,
        alertSeverity = null,
        alertDismissible = true,
        alertScenario = null;

  bool get isNavigating => status == NavigationStatus.navigating;

  bool get hasRoute => route != null && status != NavigationStatus.idle;

  bool get hasSafetyAlert => alertMessage != null;

  NavigationManeuver? get currentManeuver {
    if (route == null) return null;
    if (currentManeuverIndex < 0 || currentManeuverIndex >= route!.maneuvers.length) return null;
    return route!.maneuvers[currentManeuverIndex];
  }

  NavigationManeuver? get nextManeuver {
    if (route == null) return null;
    final nextIndex = currentManeuverIndex + 1;
    if (nextIndex >= route!.maneuvers.length) return null;
    return route!.maneuvers[nextIndex];
  }

  double get progress {
    if (route == null || route!.maneuvers.isEmpty) return 0.0;
    if (status == NavigationStatus.arrived) return 1.0;
    return (currentManeuverIndex / route!.maneuvers.length).clamp(0.0, 1.0);
  }

  NavigationState copyWith({
    NavigationStatus? status,
    NavigationRoute? route,
    int? currentManeuverIndex,
    String? destinationLabel,
    bool clearDestinationLabel = false,
    String? alertMessage,
    AlertSeverity? alertSeverity,
    bool? alertDismissible,
    SafetyScenario? alertScenario,
    bool clearAlert = false,
  }) {
    return NavigationState(
      status: status ?? this.status,
      route: route ?? this.route,
      currentManeuverIndex:
          currentManeuverIndex ?? this.currentManeuverIndex,
      destinationLabel: clearDestinationLabel
          ? null
          : (destinationLabel ?? this.destinationLabel),
      alertMessage: clearAlert ? null : (alertMessage ?? this.alertMessage),
      alertSeverity: clearAlert ? null : (alertSeverity ?? this.alertSeverity),
      alertDismissible:
          clearAlert ? true : (alertDismissible ?? this.alertDismissible),
      alertScenario: clearAlert ? null : (alertScenario ?? this.alertScenario),
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
        alertScenario,
      ];

  @override
  String toString() =>
      'NavigationState($status, maneuver=$currentManeuverIndex, alert=${alertMessage != null})';
}