/// Hazard aggregator — clusters hazardous fleet reports into geographic zones.
///
/// Pure function (no state). Takes a list of [FleetReport]s and returns
/// a list of [HazardZone]s by clustering nearby hazard reports.
///
/// Algorithm: simple distance-based clustering. Two hazard reports within
/// [clusterRadiusMeters] of each other belong to the same zone. This is
/// a greedy single-linkage approach — adequate for the 5-vehicle simulation
/// and extensible for larger fleets.
///
/// Fleet hazard aggregation.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import '../models/fleet_report.dart';
import '../models/hazard_zone.dart';

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
  /// Only processes reports where [FleetReport.isHazard] is true.
  /// Non-hazard reports are ignored.
  ///
  /// Returns an empty list if no hazard reports are present.
  static List<HazardZone> aggregate(
    List<FleetReport> reports, {
    double clusterRadius = defaultClusterRadius,
  }) {
    // Filter to hazard reports only.
    final hazards = reports.where((r) => r.isHazard).toList();
    if (hazards.isEmpty) return const [];

    // Track which reports have been assigned to a cluster.
    final assigned = <int>{};
    final zones = <HazardZone>[];

    for (var i = 0; i < hazards.length; i++) {
      if (assigned.contains(i)) continue;

      // Start a new cluster with this report.
      final cluster = <FleetReport>[hazards[i]];
      assigned.add(i);

      // Find all unassigned reports within clusterRadius of any report
      // already in this cluster (single-linkage).
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

  /// Builds a [HazardZone] from a cluster of reports.
  static HazardZone _buildZone(List<FleetReport> cluster) {
    // Center = average position.
    final avgLat =
        cluster.fold<double>(0, (s, r) => s + r.position.latitude) /
            cluster.length;
    final avgLon =
        cluster.fold<double>(0, (s, r) => s + r.position.longitude) /
            cluster.length;
    final center = LatLng(avgLat, avgLon);

    // Radius = max distance from center to any report, clamped.
    var maxDist = 0.0;
    for (final r in cluster) {
      final d = _distanceMeters(center, r.position);
      if (d > maxDist) maxDist = d;
    }
    // Add padding (50%) so the zone visually covers reports at the edge.
    final radius = (maxDist * 1.5).clamp(minZoneRadius, maxZoneRadius);

    // Severity = icy if any report is icy, snowy otherwise.
    final hasIcy = cluster.any((r) => r.condition == RoadCondition.icy);

    return HazardZone(
      center: center,
      radiusMeters: radius,
      reports: List.unmodifiable(cluster),
      severity: hasIcy ? HazardSeverity.icy : HazardSeverity.snowy,
    );
  }

  /// Approximate distance in meters between two LatLng points.
  ///
  /// Uses the Haversine formula. Accurate enough for clustering at
  /// the 500m–5000m scale.
  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0; // meters
    final dLat = _toRadians(b.latitude - a.latitude);
    final dLon = _toRadians(b.longitude - a.longitude);
    final sinDLat = math.sin(dLat / 2);
    final sinDLon = math.sin(dLon / 2);
    final h = sinDLat * sinDLat +
        math.cos(_toRadians(a.latitude)) *
            math.cos(_toRadians(b.latitude)) *
            sinDLon *
            sinDLon;
    return 2 * earthRadius * math.asin(math.sqrt(h));
  }

  static double _toRadians(double degrees) => degrees * math.pi / 180;
}
