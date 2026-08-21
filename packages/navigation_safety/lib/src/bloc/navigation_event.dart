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

  const NavigationStarted({required this.route, this.destinationLabel});

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
  List<Object?> get props => [
    message,
    severity,
    dismissible,
    scenario,
    condition,
    ambientThreshold,
  ];
}

/// The active alert should go away. Two callers, kept distinct by
/// [conditionCleared]:
///
/// * `SafetyAlertDismissed()` — the DRIVER saying "stop showing me
///   this". Refused for non-dismissible alerts — a driver cannot wave
///   away "visibility zero - pull over immediately". This is the only
///   behavior that existed before 0.9.5 and it is unchanged.
/// * `SafetyAlertDismissed(conditionCleared: true)` — the HAZARD OWNER,
///   the same data source or condition pipeline that raised the alert,
///   reporting the condition no longer holds. When the hazard has
///   genuinely passed, keeping the screen modal is itself a hazard, so
///   this clears any alert, including non-dismissible ones.
///
/// Only the component that raised (or monitors) the condition should
/// add the event with `conditionCleared: true`. Wiring that flag to a
/// driver-facing dismiss control defeats the non-dismissible contract.
class SafetyAlertDismissed extends NavigationEvent {
  const SafetyAlertDismissed({this.conditionCleared = false});

  /// True when the hazard owner reports the alerted condition has
  /// passed (added in 0.9.5). Clears the alert regardless of its
  /// `dismissible` flag. False — the default — is driver dismissal,
  /// still refused for non-dismissible alerts.
  final bool conditionCleared;

  @override
  List<Object?> get props => [conditionCleared];
}
