/// Abstract fleet provider — decouples FleetBloc from data source.
///
/// Same abstraction pattern as WeatherProvider, LocationProvider,
/// and RoutingEngine. The edge developer swaps SimulatedFleetProvider
/// for a real fleet data source without touching the BLoC.
///
/// Offline behavior: when fleet telemetry is unavailable, the `reports`
/// stream stops emitting new data. FleetBloc retains the last known state;
/// stale reports expire after a 15-minute TTL. The driver sees the last
/// known fleet positions until they age out. See [SimulatedFleetProvider]
/// for the reference implementation.
///
/// Part of the fleet consent gate pipeline.
library;

import '../models/fleet_report.dart';

abstract class FleetProvider {
  /// Stream of fleet report updates from nearby vehicles.
  Stream<FleetReport> get reports;

  /// Start receiving fleet reports.
  Future<void> startListening();

  /// Stop receiving fleet reports.
  Future<void> stopListening();

  /// Release all resources.
  void dispose();
}
