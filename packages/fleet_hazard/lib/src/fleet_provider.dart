/// Abstract fleet provider - decouples consumers from the telemetry source.
library;

import 'fleet_report.dart';

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