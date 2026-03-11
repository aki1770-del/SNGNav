/// Fleet report - a single vehicle's road condition observation.
///
/// The atomic unit of fleet telemetry. Each report represents one vehicle's
/// observation at a point in time and space.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// Road surface condition reported by a fleet vehicle.
enum RoadCondition {
  /// Normal dry road.
  dry,

  /// Wet road surface.
  wet,

  /// Snow-covered road.
  snowy,

  /// Ice on road surface - highest hazard level.
  icy,

  /// Unknown or sensor unavailable.
  unknown,
}

class FleetReport extends Equatable {
  /// Unique vehicle identifier.
  final String vehicleId;

  /// Position where the observation was made.
  final LatLng position;

  /// When the observation was made.
  final DateTime timestamp;

  /// Observed road surface condition.
  final RoadCondition condition;

  /// Confidence in the observation (0.0-1.0).
  final double confidence;

  const FleetReport({
    required this.vehicleId,
    required this.position,
    required this.timestamp,
    required this.condition,
    this.confidence = 0.8,
  });

  /// Whether this report indicates a hazard (snowy or icy).
  bool get isHazard =>
      condition == RoadCondition.snowy || condition == RoadCondition.icy;

  /// Whether this report is recent relative to [maxAge].
  bool isRecent({Duration maxAge = const Duration(minutes: 15)}) =>
      DateTime.now().difference(timestamp) < maxAge;

  @override
  List<Object?> get props =>
      [vehicleId, position, timestamp, condition, confidence];

  @override
  String toString() =>
      'FleetReport($vehicleId, ${condition.name}, '
      '${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)}, '
      'conf=${confidence.toStringAsFixed(2)})';
}