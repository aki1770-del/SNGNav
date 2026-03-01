/// Location state — 6-state quality machine for GPS signal.
///
/// State transitions:
///   uninitialized → acquiring (on start)
///   acquiring → fix (first position received, accuracy ≤ 50m)
///   acquiring → degraded (position received, accuracy > 50m)
///   acquiring → error (provider error)
///   fix → stale (no update within staleThreshold)
///   fix → degraded (accuracy degrades > 50m)
///   fix → error (provider error)
///   stale → fix (new position received, accuracy ≤ 50m)
///   stale → error (provider error)
///   degraded → fix (accuracy improves ≤ 50m)
///   degraded → stale (no update within staleThreshold)
///   degraded → error (provider error)
///   error → acquiring (restart requested)
///   any → uninitialized (stop requested)
///
/// The 50m threshold defines navigation-grade accuracy.
library;

import 'package:equatable/equatable.dart';

import '../models/geo_position.dart';

/// The 6 quality states of the location system.
enum LocationQuality {
  /// Location system not started.
  uninitialized,

  /// Started, waiting for first fix.
  acquiring,

  /// Good fix — accuracy ≤ 50m, recent update.
  fix,

  /// Fix has gone stale — no update within threshold.
  stale,

  /// Position available but accuracy > 50m.
  degraded,

  /// Provider error — no position available.
  error,
}

class LocationState extends Equatable {
  final LocationQuality quality;
  final GeoPosition? position;
  final String? errorMessage;

  /// Whether the current position is from dead reckoning (prediction)
  /// rather than a live GPS fix. When true, the UI should indicate
  /// estimated position (e.g., confidence circle, "DR" badge).
  ///
  /// Kalman filter awareness.
  final bool isDeadReckoning;

  const LocationState({
    required this.quality,
    this.position,
    this.errorMessage,
    this.isDeadReckoning = false,
  });

  const LocationState.uninitialized()
      : quality = LocationQuality.uninitialized,
        position = null,
        errorMessage = null,
        isDeadReckoning = false;

  const LocationState.acquiring()
      : quality = LocationQuality.acquiring,
        position = null,
        errorMessage = null,
        isDeadReckoning = false;

  /// Whether the system is actively tracking (any state except uninitialized).
  bool get isTracking => quality != LocationQuality.uninitialized;

  /// Whether a usable position is available (fix or degraded or stale).
  bool get hasPosition => position != null;

  /// Whether the current fix is navigation-grade.
  bool get isNavigationGrade =>
      quality == LocationQuality.fix && position != null;

  /// Confidence radius in metres — maps directly to GPS accuracy or
  /// Kalman covariance. Used by the UI to draw a confidence circle
  /// around the position dot.
  ///
  /// Returns 0.0 if no position is available.
  double get confidenceRadius => position?.accuracy ?? 0.0;

  LocationState copyWith({
    LocationQuality? quality,
    GeoPosition? position,
    String? errorMessage,
    bool? isDeadReckoning,
  }) {
    return LocationState(
      quality: quality ?? this.quality,
      position: position ?? this.position,
      errorMessage: errorMessage,
      isDeadReckoning: isDeadReckoning ?? this.isDeadReckoning,
    );
  }

  @override
  List<Object?> get props => [quality, position, errorMessage, isDeadReckoning];

  @override
  String toString() =>
      'LocationState($quality, pos=$position, dr=$isDeadReckoning)';
}
