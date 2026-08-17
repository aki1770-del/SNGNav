import 'dart:math' as math;
import 'package:latlong2/latlong.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import '../models/adaptive_reroute_config.dart';
import '../models/detour_waypoint.dart';

/// Generates bypass waypoints for a list of hazard zones.
///
/// For each zone, two waypoints are produced — one on each side of the
/// zone centre, offset by [AdaptiveRerouteConfig.detourOffsetMeters] plus
/// the zone's own radius. Pass both to the routing engine; the engine selects
/// whichever fits the network better.
///
/// The offset direction is computed from the bearing of the approach vector
/// (origin → hazard centre), then rotated ±90°.
class DetourPlanner {
  const DetourPlanner({this.config = const AdaptiveRerouteConfig()});

  final AdaptiveRerouteConfig config;

  /// Produces left + right [DetourWaypoint] pairs for each zone in [zones].
  ///
  /// [approachBearing] is the bearing (degrees, clockwise from north) of the
  /// vehicle's direction of travel at the hazard approach point.
  List<DetourWaypoint> plan(
    List<HazardZone> zones, {
    required double approachBearing,
  }) {
    if (zones.isEmpty) return const [];

    final waypoints = <DetourWaypoint>[];
    for (final zone in zones) {
      final offset = zone.radiusMeters + config.detourOffsetMeters;
      waypoints.addAll(_waypointsForZone(zone, approachBearing, offset));
    }
    return waypoints;
  }

  List<DetourWaypoint> _waypointsForZone(
    HazardZone zone,
    double approachBearing,
    double offsetMeters,
  ) {
    return [
      DetourWaypoint(
        position: _offsetPosition(zone.center, approachBearing - 90, offsetMeters),
        sourceZone: zone,
        side: DetourSide.left,
        offsetMeters: offsetMeters,
      ),
      DetourWaypoint(
        position: _offsetPosition(zone.center, approachBearing + 90, offsetMeters),
        sourceZone: zone,
        side: DetourSide.right,
        offsetMeters: offsetMeters,
      ),
    ];
  }

  /// Projects [center] by [distanceMeters] in direction [bearingDegrees].
  ///
  /// Uses spherical Earth approximation (WGS-84 R=6371 km).
  static LatLng _offsetPosition(
    LatLng center,
    double bearingDegrees,
    double distanceMeters,
  ) {
    const r = 6371000.0; // Earth radius in metres
    final d = distanceMeters / r;
    final lat1 = center.latitude * math.pi / 180;
    final lng1 = center.longitude * math.pi / 180;
    final b = bearingDegrees * math.pi / 180;

    final sinLat2 = (math.sin(lat1) * math.cos(d) +
            math.cos(lat1) * math.sin(d) * math.cos(b))
        .clamp(-1.0, 1.0); // guard asin domain
    final lat2 = math.asin(sinLat2);
    final lng2 = lng1 +
        math.atan2(
          math.sin(b) * math.sin(d) * math.cos(lat1),
          math.cos(d) - math.sin(lat1) * math.sin(lat2),
        );

    return LatLng(lat2 * 180 / math.pi, lng2 * 180 / math.pi);
  }
}
