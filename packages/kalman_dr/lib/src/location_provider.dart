/// Abstract location provider interface.
///
/// Implement this to supply GPS positions from any platform
/// (GeoClue2, Android, iOS, simulated).
library;

import 'geo_position.dart';

abstract class LocationProvider {
  /// Stream of position updates.
  Stream<GeoPosition> get positions;

  /// Start receiving location updates.
  Future<void> start();

  /// Stop receiving location updates.
  Future<void> stop();

  /// Release all resources.
  Future<void> dispose();
}
