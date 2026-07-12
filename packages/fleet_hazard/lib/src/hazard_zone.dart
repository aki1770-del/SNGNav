/// Hazard zone - a geographic cluster of hazardous fleet reports.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'zone_observation.dart';

/// Severity of a hazard zone, derived from its constituent reports.
enum HazardSeverity {
  /// At least one icy report - highest severity.
  icy,

  /// Snowy reports only - moderate severity.
  snowy,
}

class HazardZone extends Equatable {
  /// Geographic center of the zone.
  final LatLng center;

  /// Radius in meters.
  final double radiusMeters;

  /// Anonymized observations that form this zone.
  ///
  /// These are [ZoneObservation]s — they carry **no `vehicleId`**. The
  /// per-vehicle re-identification key is dropped at aggregation time, so a
  /// retained zone is genuinely an anonymized aggregate, not a re-identifiable
  /// per-vehicle trail. See [ZoneObservation].
  final List<ZoneObservation> reports;

  /// Zone severity.
  final HazardSeverity severity;

  /// Number of unique vehicles that contributed to this zone.
  ///
  /// Computed at aggregation time from the input reports' `vehicleId`s (before
  /// they are stripped) and stored. It can no longer be *derived* from
  /// [reports], which carry no `vehicleId` — that is the point: the count is
  /// preserved for honest "N vehicles reported" rendering without retaining the
  /// re-identification key that would let the trail be reconstructed.
  final int vehicleCount;

  /// Average confidence across all observations in the zone, or `null` when there
  /// are no observations.
  ///
  /// `null` means NOT KNOWN. It never means "zero confidence".
  ///
  /// Up to and including 0.5.0 this returned `0` for an empty zone — a NUMBER,
  /// indistinguishable from observations that genuinely carried zero confidence.
  /// A consumer could not tell "nobody has reported this road" apart from "everyone
  /// who reported it was certain of nothing". Those are different facts and a driver
  /// deserves them kept apart.
  double? get averageConfidence {
    if (reports.isEmpty) return null;
    return reports.fold<double>(
          0,
          (sum, observation) => sum + observation.confidence,
        ) /
        reports.length;
  }

  const HazardZone({
    required this.center,
    required this.radiusMeters,
    required this.reports,
    required this.severity,
    required this.vehicleCount,
  });

  @override
  List<Object?> get props => [
    center,
    radiusMeters,
    reports,
    severity,
    vehicleCount,
  ];

  @override
  String toString() =>
      'HazardZone(${severity.name}, ${reports.length} reports, '
      '$vehicleCount vehicles, ${radiusMeters.toStringAsFixed(0)}m)';
}
