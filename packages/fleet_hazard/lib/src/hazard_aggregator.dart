/// Hazard aggregator - clusters hazardous fleet reports into geographic zones.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

import 'fleet_report.dart';
import 'hazard_zone.dart';

/// Clusters hazardous fleet reports into geographic [HazardZone]s.
class HazardAggregator {
  /// Maximum distance (meters) between two reports to be in the same cluster.
  static const double defaultClusterRadius = 3000;

  /// Minimum zone radius (meters) for a single-report zone.
  static const double minZoneRadius = 500;

  /// Maximum zone radius (meters) cap.
  static const double maxZoneRadius = 5000;

  /// Clusters hazard reports into zones.
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

  static HazardZone _buildZone(List<FleetReport> cluster) {
    final avgLat =
        cluster.fold<double>(0, (sum, report) => sum + report.position.latitude) /
            cluster.length;
    final avgLon =
        cluster.fold<double>(0, (sum, report) => sum + report.position.longitude) /
            cluster.length;
    final center = LatLng(avgLat, avgLon);

    var maxDist = 0.0;
    for (final report in cluster) {
      final distance = _distanceMeters(center, report.position);
      if (distance > maxDist) maxDist = distance;
    }

    final radius = (maxDist * 1.5).clamp(minZoneRadius, maxZoneRadius);
    final hasIcy = cluster.any((report) => report.condition == RoadCondition.icy);

    return HazardZone(
      center: center,
      radiusMeters: radius,
      reports: List.unmodifiable(cluster),
      severity: hasIcy ? HazardSeverity.icy : HazardSeverity.snowy,
    );
  }

  static double _distanceMeters(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
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