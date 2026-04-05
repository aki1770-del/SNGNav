import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import 'package:fleet_hazard/fleet_hazard.dart';

/// A waypoint generated to route around a [HazardZone].
///
/// Produced by [DetourPlanner]. The calling code passes these waypoints to a
/// [RoutingEngine] to build a candidate alternative route.
///
/// Two waypoints are generated per hazard: [DetourSide.left] and
/// [DetourSide.right] relative to the direction of travel. The routing engine
/// decides which produces a shorter detour.
class DetourWaypoint extends Equatable {
  /// The geographic position of the detour waypoint.
  final LatLng position;

  /// The hazard zone this waypoint bypasses.
  final HazardZone sourceZone;

  /// Which side of the original route this waypoint sits on.
  final DetourSide side;

  /// Offset distance from the hazard zone centre (metres).
  final double offsetMeters;

  const DetourWaypoint({
    required this.position,
    required this.sourceZone,
    required this.side,
    required this.offsetMeters,
  });

  @override
  List<Object?> get props => [position, sourceZone, side, offsetMeters];

  @override
  String toString() =>
      'DetourWaypoint(${side.name}, '
      '${position.latitude.toStringAsFixed(4)}, '
      '${position.longitude.toStringAsFixed(4)}, '
      'offset=${offsetMeters.toStringAsFixed(0)}m)';
}

enum DetourSide { left, right }
