// lib/navigation/route_follower.dart
//
// RouteFollower: Projects raw GPS position onto the active route polyline,
// enforces monotonic forward progression, applies heading filter, and
// detects off-route conditions.
//
// Uses GeoPosition from kalman_dr (speed in m/s, heading in degrees,
// double.nan when unknown).  All distance calculations use Haversine.

import 'dart:math' as math;

import 'package:kalman_dr/kalman_dr.dart' show GeoPosition;
import 'package:latlong2/latlong.dart';

// ---------------------------------------------------------------------------
// Public data types
// ---------------------------------------------------------------------------

/// The result of one RouteFollower.update() call.
class SnappedPosition {
  /// The projected point on the route polyline.
  final LatLng snappedLatLng;

  /// The raw GPS position as received from the location provider.
  final LatLng rawLatLng;

  /// Index of the route segment (into shape[i]→shape[i+1]) we are on.
  final int segmentIndex;

  /// Progress along the entire route: 0.0 at start, 1.0 at destination.
  final double progressFraction;

  /// Great-circle distance (metres) between rawLatLng and snappedLatLng.
  final double distanceFromRoute;

  /// True when distanceFromRoute > [RouteFollower.offRouteThresholdMetres].
  /// When true, the caller should display rawLatLng with an off-route indicator
  /// rather than snappedLatLng.
  final bool isOffRoute;

  const SnappedPosition({
    required this.snappedLatLng,
    required this.rawLatLng,
    required this.segmentIndex,
    required this.progressFraction,
    required this.distanceFromRoute,
    required this.isOffRoute,
  });

  @override
  String toString() => 'SnappedPosition('
      'snapped=$snappedLatLng, '
      'raw=$rawLatLng, '
      'seg=$segmentIndex, '
      'progress=${progressFraction.toStringAsFixed(4)}, '
      'dist=${distanceFromRoute.toStringAsFixed(1)} m, '
      'offRoute=$isOffRoute)';
}

// ---------------------------------------------------------------------------
// Pure geometry helpers
// ---------------------------------------------------------------------------

/// Haversine great-circle distance between two points expressed in degrees.
/// Returns metres.
double haversineMetres(LatLng a, LatLng b) {
  const double earthRadiusM = 6371000.0;

  final double dLat = _degToRad(b.latitude - a.latitude);
  final double dLon = _degToRad(b.longitude - a.longitude);

  final double sinHalfLat = math.sin(dLat / 2);
  final double sinHalfLon = math.sin(dLon / 2);

  final double h = sinHalfLat * sinHalfLat +
      math.cos(_degToRad(a.latitude)) *
          math.cos(_degToRad(b.latitude)) *
          sinHalfLon *
          sinHalfLon;

  return 2.0 * earthRadiusM * math.asin(math.sqrt(h));
}

/// Projects [point] onto the line segment [a]→[b].
///
/// Works in equirectangular (flat-Earth) coordinates, which is accurate
/// enough for segments up to ~1 km.  For longer segments Valhalla already
/// subdivides the polyline, so error is negligible.
///
/// Returns the nearest point on the **closed** segment (clamped to [a, b]).
LatLng projectPointToSegment(LatLng point, LatLng a, LatLng b) {
  // Convert to metres in a local flat coordinate system centred on [a].
  final double cosLat = math.cos(_degToRad(a.latitude));

  final double px = _degToRad(point.longitude - a.longitude) * cosLat * _earthR;
  final double py = _degToRad(point.latitude - a.latitude) * _earthR;

  final double bx = _degToRad(b.longitude - a.longitude) * cosLat * _earthR;
  final double by = _degToRad(b.latitude - a.latitude) * _earthR;

  final double segLenSq = bx * bx + by * by;

  if (segLenSq == 0.0) {
    // Degenerate segment (a == b); return the single point.
    return a;
  }

  // Parameter t ∈ [0, 1] along the segment.
  final double t = ((px * bx + py * by) / segLenSq).clamp(0.0, 1.0);

  // Convert back to degrees.
  final double projX = t * bx; // metres east
  final double projY = t * by; // metres north

  final double projLat = a.latitude + _radToDeg(projY / _earthR);
  final double projLon =
      a.longitude + _radToDeg(projX / (_earthR * cosLat));

  return LatLng(projLat, projLon);
}

/// Bearing (degrees, 0–360 clockwise from north) from [a] to [b].
double bearingDegrees(LatLng a, LatLng b) {
  final double dLon = _degToRad(b.longitude - a.longitude);
  final double lat1 = _degToRad(a.latitude);
  final double lat2 = _degToRad(b.latitude);

  final double y = math.sin(dLon) * math.cos(lat2);
  final double x =
      math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dLon);

  return (_radToDeg(math.atan2(y, x)) + 360.0) % 360.0;
}

/// Smallest absolute difference between two bearings (0–180°).
double bearingDifferenceDeg(double a, double b) {
  final double diff = ((a - b) % 360.0 + 360.0) % 360.0;
  return diff > 180.0 ? 360.0 - diff : diff;
}

// ---------------------------------------------------------------------------
// RouteFollower
// ---------------------------------------------------------------------------

/// Maintains a single piece of mutable state ([_currentSegmentIndex]) and
/// exposes one public method: [update].
///
/// Lifecycle:
///   1. Construct once per active route: `RouteFollower(shape: route.shape)`
///   2. Call `update(geoPosition)` on every GPS fix — typically 1 Hz.
///   3. Discard and reconstruct when a new route is calculated.
class RouteFollower {
  // ── Tuneable constants ────────────────────────────────────────────────────

  /// Metres beyond which we declare the user off-route.
  final double offRouteThresholdMetres;

  /// Monotonicity guard: how far backward (metres) we allow segment index
  /// to retreat before clamping.  Prevents GPS noise causing backward jumps.
  final double backtrackAllowanceMetres;

  /// Half-width of the forward search window in segment count.
  final int segmentWindowForward;
  final int segmentWindowBack;

  /// Speed threshold (km/h) above which heading data is used.
  final double headingSpeedThresholdKmh;

  /// Maximum angular deviation (°) between GPS heading and segment bearing
  /// before the segment is penalised in candidate selection.
  final double headingToleranceDeg;

  // ── Route geometry ────────────────────────────────────────────────────────

  final List<LatLng> _shape;

  /// Cumulative distances along the polyline.
  /// _cumDist[i] = distance from shape[0] to shape[i] in metres.
  late final List<double> _cumDist;

  /// Total route length in metres.
  late final double _totalLength;

  // ── Mutable state ─────────────────────────────────────────────────────────

  /// Index of the first vertex of the segment we currently consider
  /// ourselves on.  Segment i spans shape[i] → shape[i+1].
  int _currentSegmentIndex = 0;

  // ── Constructor ───────────────────────────────────────────────────────────

  RouteFollower({
    required List<LatLng> shape,
    this.offRouteThresholdMetres = 50.0,
    this.backtrackAllowanceMetres = 50.0,
    this.segmentWindowForward = 20,
    this.segmentWindowBack = 20,
    this.headingSpeedThresholdKmh = 3.0,
    this.headingToleranceDeg = 45.0,
  })  : assert(shape.length >= 2, 'Route must have at least 2 points'),
        _shape = List.unmodifiable(shape) {
    _buildCumulativeDistances();
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Current segment index (read-only, exposed for testing / debug UI).
  int get currentSegmentIndex => _currentSegmentIndex;

  /// Total route length in metres.
  double get totalLengthMetres => _totalLength;

  /// Reset internal state when re-using the same instance.
  void reset() => _currentSegmentIndex = 0;

  /// Main entry point.  Call once per GPS fix.
  ///
  /// Returns a [SnappedPosition] that is always valid.  When off-route,
  /// [SnappedPosition.isOffRoute] is true and the caller should display
  /// [SnappedPosition.rawLatLng] with an off-route indicator.
  SnappedPosition update(GeoPosition pos) {
    assert(_shape.length >= 2);

    final LatLng raw = LatLng(pos.latitude, pos.longitude);

    // GeoPosition.speedKmh returns double.nan if speed unknown.
    final double speedKmh = pos.speedKmh.isNaN ? 0.0 : pos.speedKmh;
    final bool headingKnown = !pos.heading.isNaN;

    // ── 1. Determine search window ─────────────────────────────────────────
    final int segCount = _shape.length - 1;
    final int windowStart =
        (_currentSegmentIndex - segmentWindowBack).clamp(0, segCount - 1);
    final int windowEnd =
        (_currentSegmentIndex + segmentWindowForward).clamp(0, segCount - 1);

    // ── 2. Evaluate all candidate segments ────────────────────────────────
    _Candidate? best;

    final bool useHeading = headingKnown && speedKmh >= headingSpeedThresholdKmh;

    for (int i = windowStart; i <= windowEnd; i++) {
      final LatLng a = _shape[i];
      final LatLng b = _shape[i + 1];

      final LatLng proj = projectPointToSegment(raw, a, b);
      final double dist = haversineMetres(raw, proj);

      // Penalise (rather than hard-reject) segments opposing our heading so
      // we degrade gracefully at U-turns or when heading data is stale.
      double headingPenalty = 0.0;
      if (useHeading) {
        final double segBearing = bearingDegrees(a, b);
        final double diff = bearingDifferenceDeg(pos.heading, segBearing);
        if (diff > headingToleranceDeg) {
          headingPenalty = 1000.0; // metres — dominates dist for wrong dir
        }
      }

      final double score = dist + headingPenalty;

      if (best == null || score < best.score) {
        final double t = _segmentParameter(raw, a, b);
        final double distAlongRoute = _cumDist[i] + t * haversineMetres(a, b);

        best = _Candidate(
          segmentIndex: i,
          projectedPoint: proj,
          distFromRoute: dist,
          distAlongRoute: distAlongRoute,
          score: score,
        );
      }
    }

    // best is non-null: windowStart <= windowEnd is guaranteed (segCount >= 1).
    final _Candidate winner = best!;

    // ── 3. Monotonicity guard ─────────────────────────────────────────────
    final double currentSegStart = _cumDist[_currentSegmentIndex];
    final double minAllowedDist =
        (currentSegStart - backtrackAllowanceMetres).clamp(0.0, _totalLength);

    final int resolvedSegIndex;
    final LatLng resolvedPoint;
    final double resolvedDistAlong;

    if (winner.distAlongRoute >= minAllowedDist) {
      resolvedSegIndex = winner.segmentIndex;
      resolvedPoint = winner.projectedPoint;
      resolvedDistAlong = winner.distAlongRoute;
      _currentSegmentIndex = winner.segmentIndex;
    } else {
      // GPS noise dragged us backward beyond allowance: stay put.
      final LatLng ca = _shape[_currentSegmentIndex];
      final LatLng cb = _shape[_currentSegmentIndex + 1];
      resolvedPoint = projectPointToSegment(raw, ca, cb);
      resolvedSegIndex = _currentSegmentIndex;
      final double t = _segmentParameter(raw, ca, cb);
      resolvedDistAlong =
          _cumDist[_currentSegmentIndex] + t * haversineMetres(ca, cb);
    }

    // ── 4. Progress fraction ──────────────────────────────────────────────
    final double progress =
        _totalLength > 0 ? (resolvedDistAlong / _totalLength).clamp(0.0, 1.0) : 0.0;

    // ── 5. Off-route detection ────────────────────────────────────────────
    final double rawDist = haversineMetres(raw, resolvedPoint);
    final bool offRoute = rawDist > offRouteThresholdMetres;

    return SnappedPosition(
      snappedLatLng: resolvedPoint,
      rawLatLng: raw,
      segmentIndex: resolvedSegIndex,
      progressFraction: progress,
      distanceFromRoute: rawDist,
      isOffRoute: offRoute,
    );
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  void _buildCumulativeDistances() {
    final List<double> cum = List.filled(_shape.length, 0.0);
    for (int i = 1; i < _shape.length; i++) {
      cum[i] = cum[i - 1] + haversineMetres(_shape[i - 1], _shape[i]);
    }
    _cumDist = List.unmodifiable(cum);
    _totalLength = cum.last;
  }

  double _segmentParameter(LatLng point, LatLng a, LatLng b) {
    final double cosLat = math.cos(_degToRad(a.latitude));

    final double px = _degToRad(point.longitude - a.longitude) * cosLat * _earthR;
    final double py = _degToRad(point.latitude - a.latitude) * _earthR;
    final double bx = _degToRad(b.longitude - a.longitude) * cosLat * _earthR;
    final double by = _degToRad(b.latitude - a.latitude) * _earthR;

    final double segLenSq = bx * bx + by * by;
    if (segLenSq == 0.0) return 0.0;
    return ((px * bx + py * by) / segLenSq).clamp(0.0, 1.0);
  }
}

// ---------------------------------------------------------------------------
// Internal types
// ---------------------------------------------------------------------------

class _Candidate {
  final int segmentIndex;
  final LatLng projectedPoint;
  final double distFromRoute;
  final double distAlongRoute;
  final double score; // dist + heading penalty; used for selection

  const _Candidate({
    required this.segmentIndex,
    required this.projectedPoint,
    required this.distFromRoute,
    required this.distAlongRoute,
    required this.score,
  });
}

// ---------------------------------------------------------------------------
// Math utilities (file-private)
// ---------------------------------------------------------------------------

const double _earthR = 6371000.0;

double _degToRad(double deg) => deg * math.pi / 180.0;
double _radToDeg(double rad) => rad * 180.0 / math.pi;
