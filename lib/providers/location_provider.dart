/// Abstract location provider — decouples LocationBloc from GeoClue2.
///
/// The edge developer can swap GeoClue2 for Android, iOS, or mock
/// providers without touching the BLoC.
///
/// Offline behavior: when the location source is unavailable, the
/// `positions` stream stops emitting. LocationBloc transitions to
/// [LocationQuality.stale] after a timeout, then [LocationQuality.error].
/// The driver sees the last fix with a degraded quality indicator.
/// Dead reckoning provides fallback during GPS loss.
library;

import '../models/geo_position.dart';

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
