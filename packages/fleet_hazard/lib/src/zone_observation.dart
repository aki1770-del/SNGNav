/// Anonymized observation retained inside a [HazardZone].
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'fleet_report.dart';

/// A single road-condition observation retained inside a `HazardZone`,
/// stripped of the per-vehicle re-identification key.
///
/// Unlike [FleetReport] — the *input atom* to aggregation — a
/// `ZoneObservation` carries **no `vehicleId`**. It keeps only what map
/// rendering needs: [position], [condition], [timestamp], and [confidence].
///
/// This is the anonymization boundary. Once reports are clustered into a zone,
/// the per-vehicle re-identification trail (a `vehicleId` mapped to its
/// sequence of `position` + `timestamp`) is dropped and cannot be
/// reconstructed from the retained zone. Two observations with the same
/// position/condition/timestamp/confidence are indistinguishable — by design,
/// because the key that would distinguish them (the vehicle) is gone.
class ZoneObservation extends Equatable {
  /// Position where the observation was made.
  final LatLng position;

  /// Observed road surface condition.
  final RoadCondition condition;

  /// When the observation was made.
  final DateTime timestamp;

  /// Confidence in the observation (0.0-1.0).
  final double confidence;

  const ZoneObservation({
    required this.position,
    required this.condition,
    required this.timestamp,
    required this.confidence,
  });

  /// Builds an anonymized observation from a [FleetReport], dropping its
  /// `vehicleId` while keeping the renderable fields.
  factory ZoneObservation.fromReport(FleetReport report) => ZoneObservation(
    position: report.position,
    condition: report.condition,
    timestamp: report.timestamp,
    confidence: report.confidence,
  );

  @override
  List<Object?> get props => [position, condition, timestamp, confidence];

  @override
  String toString() =>
      'ZoneObservation(${condition.name}, '
      '${position.latitude.toStringAsFixed(4)},${position.longitude.toStringAsFixed(4)}, '
      'conf=${confidence.toStringAsFixed(2)})';
}
