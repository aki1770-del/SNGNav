/// Navigation events — inputs to the NavigationBloc state machine.
///
/// NavigationBloc manages the active navigation *session* — turn-by-turn
/// guidance, maneuver tracking, and safety alerts.
///
/// Domain separation:
///   RoutingBloc  → route *calculation* lifecycle
///   NavigationBloc → navigation *session* lifecycle
///
/// Events for the navigation session lifecycle.
library;

import 'package:equatable/equatable.dart';

import '../models/route_result.dart';

sealed class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => [];
}

/// Start a navigation session with a calculated route.
///
/// Dispatched by the widget when RoutingBloc produces a route.
/// Widget mediates — no direct BLoC-to-BLoC wiring.
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

/// Stop the current navigation session.
///
/// Dispatched when user cancels navigation or route is cleared.
class NavigationStopped extends NavigationEvent {
  const NavigationStopped();
}

/// Advance to the next maneuver in the route.
///
/// Dispatched by the widget (or a future proximity service) when the
/// driver passes a waypoint. NavigationBloc does not compute proximity
/// — it's a pure state machine. The external trigger keeps it testable.
class ManeuverAdvanced extends NavigationEvent {
  const ManeuverAdvanced();
}

/// Route deviation detected — driver is off-route.
///
/// Dispatched by the widget when position diverges from route geometry.
/// This event exists for testing; deviation detection
/// logic is deferred (requires position-to-route matching).
class RouteDeviationDetected extends NavigationEvent {
  final String? reason;

  const RouteDeviationDetected({this.reason});

  @override
  List<Object?> get props => [reason];
}

/// New route received after a reroute (deviation recovery).
///
/// Dispatched by the widget after RoutingBloc recalculates.
class RerouteCompleted extends NavigationEvent {
  final RouteResult newRoute;

  const RerouteCompleted({required this.newRoute});

  @override
  List<Object?> get props => [newRoute];
}

/// Safety alert received from weather or vehicle systems.
///
/// SafetyOverlay (Z=2) reads NavigationBloc state to display
/// safety-critical information above all other content.
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

/// Driver acknowledges and dismisses a safety alert.
class SafetyAlertDismissed extends NavigationEvent {
  const SafetyAlertDismissed();
}

/// Alert severity levels for SafetyOverlay rendering.
///
/// Maps to visual treatment in SafetyOverlay:
///   info     → blue indicator, auto-dismiss
///   warning  → amber banner, driver-dismissible
///   critical → red full-width, non-dismissible (TOR-level)
enum AlertSeverity {
  /// Informational — e.g., "Snow expected in 30 minutes"
  info,

  /// Warning — e.g., "Icy road conditions ahead"
  warning,

  /// Critical — e.g., "Visibility zero, pull over" (ASIL-B display)
  critical,
}
