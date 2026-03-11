/// Fleet events — inputs to the FleetBloc state machine.
///
/// FleetBloc manages fleet telemetry reception and hazard aggregation:
///   start listening → receive reports → stop listening
///
/// Same sealed-class pattern as WeatherEvent and LocationEvent.
///
/// Fleet data flow is gated by user consent.
library;

import 'package:equatable/equatable.dart';
import 'package:fleet_hazard/fleet_hazard.dart';

sealed class FleetEvent extends Equatable {
  const FleetEvent();

  @override
  List<Object?> get props => [];
}

/// Start listening for fleet reports.
///
/// Dispatched when the user grants fleet consent and the app is active.
class FleetListenStarted extends FleetEvent {
  const FleetListenStarted();
}

/// Stop listening for fleet reports.
///
/// Dispatched when the user revokes fleet consent or app backgrounds.
class FleetListenStopped extends FleetEvent {
  const FleetListenStopped();
}

/// A new fleet report was received from the provider.
///
/// Internal event — dispatched by FleetBloc when the provider stream emits.
class FleetReportReceived extends FleetEvent {
  final FleetReport report;

  const FleetReportReceived(this.report);

  @override
  List<Object?> get props => [report];
}

/// The fleet provider reported an error.
class FleetErrorOccurred extends FleetEvent {
  final String message;

  const FleetErrorOccurred(this.message);

  @override
  List<Object?> get props => [message];
}
