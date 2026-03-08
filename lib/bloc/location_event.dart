/// Location events — inputs to the LocationBloc state machine.
///
/// Events feed the LocationBloc data pipeline.
library;

import 'package:equatable/equatable.dart';

import 'package:kalman_dr/kalman_dr.dart';

sealed class LocationEvent extends Equatable {
  const LocationEvent();

  @override
  List<Object?> get props => [];
}

/// User requests location tracking to start.
class LocationStartRequested extends LocationEvent {
  const LocationStartRequested();
}

/// User requests location tracking to stop.
class LocationStopRequested extends LocationEvent {
  const LocationStopRequested();
}

/// A new position was received from the provider.
class LocationPositionReceived extends LocationEvent {
  final GeoPosition position;

  const LocationPositionReceived(this.position);

  @override
  List<Object?> get props => [position];
}

/// The position fix has gone stale (no update within threshold).
class LocationStaleTimeout extends LocationEvent {
  const LocationStaleTimeout();
}

/// The provider reported an error.
class LocationErrorOccurred extends LocationEvent {
  final String message;

  const LocationErrorOccurred(this.message);

  @override
  List<Object?> get props => [message];
}
