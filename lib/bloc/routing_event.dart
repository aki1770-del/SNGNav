/// Routing events — inputs to the RoutingBloc state machine.
///
/// Events feed the RoutingBloc data pipeline.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

sealed class RoutingEvent extends Equatable {
  const RoutingEvent();

  @override
  List<Object?> get props => [];
}

/// User requests a route between two points.
class RouteRequested extends RoutingEvent {
  final LatLng origin;
  final LatLng destination;
  final String? destinationLabel;
  final String costing;

  const RouteRequested({
    required this.origin,
    required this.destination,
    this.destinationLabel,
    this.costing = 'auto',
  });

  @override
  List<Object?> get props => [origin, destination, destinationLabel, costing];
}

/// User clears the active route.
class RouteClearRequested extends RoutingEvent {
  const RouteClearRequested();
}

/// Check engine availability.
class RoutingEngineCheckRequested extends RoutingEvent {
  const RoutingEngineCheckRequested();
}
