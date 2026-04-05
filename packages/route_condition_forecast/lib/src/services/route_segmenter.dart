import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import '../models/route_segment.dart';

/// Splits a [RouteResult] into [RouteSegment] objects.
///
/// The default strategy ([byManeuver]) produces one segment per maneuver step.
/// Each segment runs from the maneuver's position to the next maneuver's
/// position (or the route's last shape point for the final step).
///
/// This aligns segments with driver decision points — the natural unit for
/// "what will conditions be when I reach this turn?"
class RouteSegmenter {
  const RouteSegmenter._();

  /// Splits [route] into one segment per maneuver step.
  ///
  /// Returns an empty list if the route has no maneuvers.
  /// Segments are ordered in travel sequence.
  static List<RouteSegment> byManeuver(RouteResult route) {
    if (route.maneuvers.isEmpty) return const [];

    final maneuvers = route.maneuvers;
    final shape = route.shape;
    final segments = <RouteSegment>[];

    for (int i = 0; i < maneuvers.length; i++) {
      final maneuver = maneuvers[i];
      final isLast = i == maneuvers.length - 1;

      final end = isLast
          ? (shape.isNotEmpty ? shape.last : maneuver.position)
          : maneuvers[i + 1].position;

      segments.add(RouteSegment(
        index: i,
        start: maneuver.position,
        end: end,
        distanceKm: maneuver.lengthKm,
        maneuver: maneuver,
      ));
    }

    return segments;
  }

  /// Splits [route] into segments of at most [maxKm] km each.
  ///
  /// Long maneuver segments (e.g., a 40 km highway stretch) are subdivided
  /// into equal pieces so that weather queries stay geographically relevant.
  /// Maneuver metadata is preserved on the first sub-segment; subsequent
  /// sub-segments carry a null maneuver.
  static List<RouteSegment> byDistance(
    RouteResult route, {
    double maxKm = 5.0,
  }) {
    if (route.maneuvers.isEmpty) return const [];
    assert(maxKm > 0, 'maxKm must be positive');

    final raw = byManeuver(route);
    final result = <RouteSegment>[];
    int nextIndex = 0;

    for (final seg in raw) {
      if (seg.distanceKm <= maxKm) {
        result.add(RouteSegment(
          index: nextIndex++,
          start: seg.start,
          end: seg.end,
          distanceKm: seg.distanceKm,
          maneuver: seg.maneuver,
        ));
        continue;
      }

      final parts = (seg.distanceKm / maxKm).ceil();
      final partKm = seg.distanceKm / parts;

      for (int p = 0; p < parts; p++) {
        final t0 = p / parts;
        final t1 = (p + 1) / parts;
        final partStart = p == 0 ? seg.start : _lerp(seg.start, seg.end, t0);
        final partEnd = p == parts - 1 ? seg.end : _lerp(seg.start, seg.end, t1);

        result.add(RouteSegment(
          index: nextIndex++,
          start: partStart,
          end: partEnd,
          distanceKm: partKm,
          maneuver: p == 0 ? seg.maneuver : null,
        ));
      }
    }

    return result;
  }

  static LatLng _lerp(LatLng a, LatLng b, double t) => LatLng(
        a.latitude + (b.latitude - a.latitude) * t,
        a.longitude + (b.longitude - a.longitude) * t,
      );
}
