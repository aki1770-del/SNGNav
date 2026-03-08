/// Navigation state — 4-state machine for active navigation session.
///
/// State transitions:
///   idle → navigating (navigation started with route)
///   navigating → navigating (maneuver advanced, index++)
///   navigating → deviated (route deviation detected)
///   navigating → arrived (last maneuver reached)
///   deviated → navigating (reroute completed)
///   arrived → idle (navigation stopped)
///   any → idle (navigation stopped)
///
/// Safety alerts overlay independently — they don't change the
/// navigation status, only the alert fields.
///
/// SafetyOverlay (Z=2) renders safety-critical alerts above all content.
library;

import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';
import 'navigation_event.dart'; // AlertSeverity

enum NavigationStatus {
  /// No active navigation session.
  idle,

  /// Actively navigating with turn-by-turn guidance.
  navigating,

  /// Driver has deviated from the route, awaiting reroute.
  deviated,

  /// Destination reached.
  arrived,
}

class NavigationState extends Equatable {
  final NavigationStatus status;
  final RouteResult? route;
  final int currentManeuverIndex;
  final String? destinationLabel;

  // Safety alert fields — read by SafetyOverlay (Z=2)
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

  // ---------------------------------------------------------------------------
  // Convenience getters
  // ---------------------------------------------------------------------------

  /// True when actively navigating (not idle, deviated, or arrived).
  bool get isNavigating => status == NavigationStatus.navigating;

  /// True when a route is present and navigation is active.
  bool get hasRoute =>
      route != null && status != NavigationStatus.idle;

  /// True when a safety alert is active.
  bool get hasSafetyAlert => alertMessage != null;

  /// Current maneuver (if navigating and route has maneuvers).
  RouteManeuver? get currentManeuver {
    if (route == null) return null;
    if (currentManeuverIndex >= route!.maneuvers.length) return null;
    return route!.maneuvers[currentManeuverIndex];
  }

  /// Next maneuver after the current one (null if at end).
  RouteManeuver? get nextManeuver {
    if (route == null) return null;
    final nextIdx = currentManeuverIndex + 1;
    if (nextIdx >= route!.maneuvers.length) return null;
    return route!.maneuvers[nextIdx];
  }

  /// Navigation progress as 0.0–1.0 based on maneuver index.
  ///
  /// Returns 0.0 when no route is active.
  /// Returns 1.0 when arrived (or at last maneuver).
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
      'NavigationState($status, maneuver=$currentManeuverIndex, '
      'alert=${alertMessage != null})';
}
