import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';

/// A portion of a route between two waypoints.
///
/// Segments are produced by [RouteSegmenter] — one per maneuver step.
/// Each segment carries its geometry (start/end), distance, and the
/// maneuver that begins it.
class RouteSegment extends Equatable {
  final int index;
  final LatLng start;
  final LatLng end;
  final double distanceKm;

  /// The maneuver that opens this segment, if available.
  final RouteManeuver? maneuver;

  const RouteSegment({
    required this.index,
    required this.start,
    required this.end,
    required this.distanceKm,
    this.maneuver,
  });

  /// Geometric midpoint — used as the representative query location
  /// for weather and hazard lookups.
  LatLng get midpoint => LatLng(
        (start.latitude + end.latitude) / 2,
        (start.longitude + end.longitude) / 2,
      );

  @override
  List<Object?> get props => [index, start, end, distanceKm, maneuver];

  @override
  String toString() =>
      'RouteSegment($index: ${distanceKm.toStringAsFixed(2)}km '
      '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)} → '
      '${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)})';
}
