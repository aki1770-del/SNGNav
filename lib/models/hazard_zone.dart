/// Hazard zone — a geographic cluster of hazardous fleet reports.
///
/// Produced by [HazardAggregator] from individual [FleetReport]s.
/// Rendered by [HazardZoneLayer] as a translucent circle on the map.
///
/// See [HazardAggregator] for the clustering algorithm.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'fleet_report.dart';

/// Severity of a hazard zone, derived from its constituent reports.
enum HazardSeverity {
  /// At least one icy report — highest severity.
  icy,

  /// Snowy reports only — moderate severity.
  snowy,
}

class HazardZone extends Equatable {
  /// Geographic center of the zone (average of report positions).
  final LatLng center;

  /// Radius in meters — based on the spread of reports in the cluster.
  /// Minimum 500m (single report), capped at 5000m.
  final double radiusMeters;

  /// Fleet reports that form this zone.
  final List<FleetReport> reports;

  /// Zone severity — icy if any report is icy, snowy otherwise.
  final HazardSeverity severity;

  /// Number of unique vehicles contributing to this zone.
  int get vehicleCount =>
      reports.map((r) => r.vehicleId).toSet().length;

  /// Average confidence across all reports in the zone.
  double get averageConfidence {
    if (reports.isEmpty) return 0;
    return reports.fold<double>(0, (sum, r) => sum + r.confidence) /
        reports.length;
  }

  const HazardZone({
    required this.center,
    required this.radiusMeters,
    required this.reports,
    required this.severity,
  });

  @override
  List<Object?> get props => [center, radiusMeters, reports, severity];

  @override
  String toString() =>
      'HazardZone(${severity.name}, ${reports.length} reports, '
      '$vehicleCount vehicles, ${radiusMeters.toStringAsFixed(0)}m)';
}
