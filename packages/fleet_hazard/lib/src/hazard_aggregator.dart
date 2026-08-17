/// Hazard aggregator - clusters hazardous fleet reports into geographic zones.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'fleet_aggregate.dart';
import 'fleet_report.dart';
import 'hazard_zone.dart';
import 'zone_observation.dart';

/// Clusters hazardous fleet reports into geographic [HazardZone]s.
class HazardAggregator {
  /// Maximum distance (meters) between two reports to be in the same cluster.
  static const double defaultClusterRadius = 3000;

  /// Minimum zone radius (meters) for a single-report zone.
  static const double minZoneRadius = 500;

  /// Maximum zone radius (meters) cap.
  static const double maxZoneRadius = 5000;

  /// Clusters hazard reports into zones.
  ///
  /// **This method cannot tell absence from an all-clear.** It returns an empty
  /// list in three different worlds, and gives you no way to distinguish them:
  ///
  /// * no reports were supplied — *nobody has driven this road*;
  /// * reports were supplied and all were dry/wet — *the fleet says it is fine*;
  /// * reports were supplied and all were [RoadCondition.unknown] — *the fleet
  ///   drove it and could not tell*.
  ///
  /// An empty result from this method therefore must **never** be rendered to a
  /// driver as a clear road. Reports carrying [RoadCondition.unknown] are
  /// dropped here without trace, because the hazard filter keeps only snowy and
  /// icy.
  ///
  /// **This method also applies no recency filter.** Every report is considered
  /// however old it is; a report from yesterday counts exactly as much as one
  /// from a minute ago.
  ///
  /// Use [aggregateWithProvenance] to get the counts that separate those worlds,
  /// and to enforce recency. This method's behavior is unchanged and will stay
  /// unchanged — existing callers are not affected.
  static List<HazardZone> aggregate(
    List<FleetReport> reports, {
    double clusterRadius = defaultClusterRadius,
  }) {
    final hazards = reports.where((report) => report.isHazard).toList();
    if (hazards.isEmpty) return const [];

    final assigned = <int>{};
    final zones = <HazardZone>[];

    for (var i = 0; i < hazards.length; i++) {
      if (assigned.contains(i)) continue;

      final cluster = <FleetReport>[hazards[i]];
      assigned.add(i);

      var expanded = true;
      while (expanded) {
        expanded = false;
        for (var j = 0; j < hazards.length; j++) {
          if (assigned.contains(j)) continue;
          for (final member in cluster) {
            if (_distanceMeters(member.position, hazards[j].position) <=
                clusterRadius) {
              cluster.add(hazards[j]);
              assigned.add(j);
              expanded = true;
              break;
            }
          }
        }
      }

      zones.add(_buildZone(cluster));
    }

    return zones;
  }

  /// Clusters hazard reports into zones **and reports what it was told**.
  ///
  /// Unlike [aggregate], the result distinguishes *nobody reported this road*
  /// from *the fleet reported it and found it clear* from *the fleet reported it
  /// and could not read it* — three worlds that [aggregate] collapses into the
  /// same empty list. See [FleetAggregate].
  ///
  /// ```dart
  /// // oracle:placeholders reports
  /// final result = HazardAggregator.aggregateWithProvenance(
  ///   reports,
  ///   maxAge: const Duration(minutes: 30),
  /// );
  ///
  /// if (result.isSilent) {
  ///   // No fresh reports at all. Say so. Do NOT render a clear road.
  /// } else if (result.isAllUnknown) {
  ///   // Vehicles drove it; none could tell. Also not a clear road.
  /// } else if (result.isMeasuredClear) {
  ///   // Vehicles drove it and found it fine. This one you may render as clear.
  /// }
  /// ```
  ///
  /// When [maxAge] is supplied, a report is considered only if
  /// [FleetReport.isRecent] accepts it at that age; the rest are counted in
  /// [FleetAggregate.staleCount] and excluded from clustering. When [maxAge] is
  /// `null` **no recency filter is applied at all** — every report counts, at
  /// any age. If your surface tells the driver something like "N vehicles
  /// reported in the last 30 minutes", you must pass the matching [maxAge]; the
  /// window is enforced here, never assumed.
  ///
  /// The clustering itself is identical to [aggregate] — this method runs the
  /// same algorithm over the reports that survive [maxAge].
  static FleetAggregate aggregateWithProvenance(
    List<FleetReport> reports, {
    double clusterRadius = defaultClusterRadius,
    Duration? maxAge,
  }) {
    final considered = maxAge == null
        ? List<FleetReport>.of(reports)
        : reports
              .where((report) => report.isRecent(maxAge: maxAge))
              .toList(growable: false);

    final staleCount = reports.length - considered.length;

    final unknownCount = considered
        .where((report) => report.condition == RoadCondition.unknown)
        .length;

    DateTime? freshestReportAt;
    for (final report in considered) {
      if (freshestReportAt == null ||
          report.timestamp.isAfter(freshestReportAt)) {
        freshestReportAt = report.timestamp;
      }
    }

    final zones = aggregate(considered, clusterRadius: clusterRadius);

    return FleetAggregate(
      zones: List.unmodifiable(zones),
      reportCount: considered.length,
      unknownCount: unknownCount,
      staleCount: staleCount,
      freshestReportAt: freshestReportAt,
    );
  }

  static HazardZone _buildZone(List<FleetReport> cluster) {
    final avgLat =
        cluster.fold<double>(
          0,
          (sum, report) => sum + report.position.latitude,
        ) /
        cluster.length;
    final avgLon =
        cluster.fold<double>(
          0,
          (sum, report) => sum + report.position.longitude,
        ) /
        cluster.length;
    final center = LatLng(avgLat, avgLon);

    var maxDist = 0.0;
    for (final report in cluster) {
      final distance = _distanceMeters(center, report.position);
      if (distance > maxDist) maxDist = distance;
    }

    final radius = (maxDist * 1.5).clamp(minZoneRadius, maxZoneRadius);
    final hasIcy = cluster.any(
      (report) => report.condition == RoadCondition.icy,
    );

    // Count unique vehicles BEFORE stripping the re-identification key, then
    // drop `vehicleId` by converting each report to an anonymized observation.
    // The retained zone is an anonymized aggregate, never a per-vehicle trail.
    final vehicleCount = cluster
        .map((report) => report.vehicleId)
        .toSet()
        .length;
    final observations = cluster
        .map(ZoneObservation.fromReport)
        .toList(growable: false);

    return HazardZone(
      center: center,
      radiusMeters: radius,
      reports: List.unmodifiable(observations),
      severity: hasIcy ? HazardSeverity.icy : HazardSeverity.snowy,
      vehicleCount: vehicleCount,
    );
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h =
        sinDLat * sinDLat +
        math.cos(_toRadians(a.latitude)) *
            math.cos(_toRadians(b.latitude)) *
            sinDLon *
            sinDLon;
    return 2 * earthRadius * math.asin(math.sqrt(h.clamp(0.0, 1.0)));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
