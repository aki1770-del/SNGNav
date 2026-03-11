/// Routing events — inputs to the RoutingBloc state machine.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

sealed class RoutingEvent extends Equatable {
  const RoutingEvent();

  @override
  List<Object?> get props => [];
}

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

class RouteClearRequested extends RoutingEvent {
  const RouteClearRequested();
}

class RoutingEngineCheckRequested extends RoutingEvent {
  const RoutingEngineCheckRequested();
}