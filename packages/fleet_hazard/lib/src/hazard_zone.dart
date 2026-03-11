/// Hazard zone - a geographic cluster of hazardous fleet reports.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

import 'fleet_report.dart';

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

  /// Fleet reports that form this zone.
  final List<FleetReport> reports;

  /// Zone severity.
  final HazardSeverity severity;

  /// Number of unique vehicles contributing to this zone.
  int get vehicleCount => reports.map((report) => report.vehicleId).toSet().length;

  /// Average confidence across all reports in the zone.
  double get averageConfidence {
    if (reports.isEmpty) return 0;
    return reports.fold<double>(0, (sum, report) => sum + report.confidence) /
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