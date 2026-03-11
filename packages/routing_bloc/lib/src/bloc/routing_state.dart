/// Routing state — 4-state machine for route lifecycle.
library;

import 'package:equatable/equatable.dart';
import 'package:routing_engine/routing_engine.dart';

const _noChange = Object();

enum RoutingStatus {
  idle,
  loading,
  routeActive,
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

  bool get hasRoute => route != null && status == RoutingStatus.routeActive;

  bool get isLoading => status == RoutingStatus.loading;

  RoutingState copyWith({
    RoutingStatus? status,
    Object? route = _noChange,
    Object? destinationLabel = _noChange,
    Object? errorMessage = _noChange,
    bool? engineAvailable,
  }) {
    return RoutingState(
      status: status ?? this.status,
      route: identical(route, _noChange)
          ? this.route
          : route as RouteResult?,
      destinationLabel: identical(destinationLabel, _noChange)
          ? this.destinationLabel
          : destinationLabel as String?,
      errorMessage: identical(errorMessage, _noChange)
          ? this.errorMessage
          : errorMessage as String?,
      engineAvailable: engineAvailable ?? this.engineAvailable,
    );
  }

  @override
  List<Object?> get props =>
      [status, route, destinationLabel, errorMessage, engineAvailable];
}