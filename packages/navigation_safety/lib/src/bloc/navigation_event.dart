/// Navigation events - inputs to the navigation session state machine.
library;

import 'package:equatable/equatable.dart';

import 'package:navigation_safety_core/navigation_safety_core.dart';



sealed class NavigationEvent extends Equatable {
  const NavigationEvent();

  @override
  List<Object?> get props => [];
}

class NavigationStarted extends NavigationEvent {
  final NavigationRoute route;
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
  final NavigationRoute newRoute;

  const RerouteCompleted({required this.newRoute});

  @override
  List<Object?> get props => [newRoute];
}

class SafetyAlertReceived extends NavigationEvent {
  final String message;
  final AlertSeverity severity;
  final bool dismissible;

  /// Optional scenario coordinate — identifies the type of road hazard.
  ///
  /// When set, downstream subscribers can filter or aggregate by
  /// [SafetyScenario.namespace] without parsing the human-readable [message].
  ///
  /// Swarm composability: multiple independent packages emitting alerts with
  /// the same [scenario] id contribute independent observations of the same
  /// condition — the aggregator treats them additively.
  ///
  /// Null means the alert has no structured scenario context (legacy callers
  /// unaffected — this field is optional and defaults to null).
  final SafetyScenario? scenario;

  /// Optional road-surface condition for action-coupled rendering.
  ///
  /// When set together with the bloc's [DriverProfile], the bloc resolves
  /// the per-(condition, profile) action string via
  /// `AlertExplainer.forConditionAndProfile` and uses that as the
  /// rendered alert message instead of the free-form [message] field.
  /// The free-form [message] remains the fallback when [condition] is
  /// null OR the bloc has no driver profile configured (back-compat).
  final RoadSurfaceCondition? condition;

  /// Optional caller-supplied identifier of the active threshold context
  /// (e.g. `"icy_road_30km"`). Surfaced into telemetry records when the
  /// bloc has a `LoomFitTelemetry` instance configured. Pass null when
  /// no specific named threshold applies.
  final String? ambientThreshold;

  const SafetyAlertReceived({
    required this.message,
    required this.severity,
    this.dismissible = true,
    this.scenario,
    this.condition,
    this.ambientThreshold,
  });

  @override
  List<Object?> get props =>
      [message, severity, dismissible, scenario, condition, ambientThreshold];
}

class SafetyAlertDismissed extends NavigationEvent {
  const SafetyAlertDismissed();
}