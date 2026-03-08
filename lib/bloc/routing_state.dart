/// Routing state — 4-state machine for route lifecycle.
///
/// State transitions:
///   idle → loading (route requested)
///   loading → routeActive (route calculated successfully)
///   loading → error (engine error)
///   routeActive → idle (route cleared)
///   routeActive → loading (new route requested, replaces active)
///   error → loading (retry / new route requested)
///   error → idle (error dismissed)
///
/// State is engine-agnostic; any RoutingEngine implementation can be injected.
library;

import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';

enum RoutingStatus {
  /// No route active, engine may or may not be available.
  idle,

  /// Calculating a route.
  loading,

  /// Route is active and displayed.
  routeActive,

  /// Routing engine error.
  error,
}

class RoutingState extends Equatable {
  final RoutingStatus status;
  final RouteResult? route;
  final String? destinationLabel;
  final String? errorMessage;
  final bool engineAvailable;

  const RoutingState({
    required this.status,
    this.route,
    this.destinationLabel,
    this.errorMessage,
    this.engineAvailable = false,
  });

  const RoutingState.idle({this.engineAvailable = false})
      : status = RoutingStatus.idle,
        route = null,
        destinationLabel = null,
        errorMessage = null;

  /// Whether a route is currently displayed.
  bool get hasRoute => route != null && status == RoutingStatus.routeActive;

  /// Whether the BLoC is busy calculating.
  bool get isLoading => status == RoutingStatus.loading;

  RoutingState copyWith({
    RoutingStatus? status,
    RouteResult? route,
    String? destinationLabel,
    String? errorMessage,
    bool? engineAvailable,
  }) {
    return RoutingState(
      status: status ?? this.status,
      route: route ?? this.route,
      destinationLabel: destinationLabel ?? this.destinationLabel,
      errorMessage: errorMessage,
      engineAvailable: engineAvailable ?? this.engineAvailable,
    );
  }

  @override
  List<Object?> get props =>
      [status, route, destinationLabel, errorMessage, engineAvailable];

  @override
  String toString() => 'RoutingState($status, route=$route)';
}
