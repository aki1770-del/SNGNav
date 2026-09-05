/// Pure-Dart corridor match: which mapped bridge sites lie ON a route.
///
/// WHY this exists (the compound-failure worst case — the driver test):
/// bridge decks freeze before the road surface does. At pre-trip briefing
/// time the driver deserves to know approximately how many bridges lie on
/// her route so she can slow down BEFORE the deck, not after the slide.
///
/// HONEST SEMANTICS (binding on every consumer):
///   * The count is APPROXIMATE BY CONSTRUCTION — a 30 m corridor threshold,
///     undirected (mod-180) bearings, and OSM completeness all bound what
///     this module can know. The consumer MUST phrase the count as
///     approximate ("およそ〜箇所" class), never as an exact inventory.
///   * ZERO clusters means "nothing to say" — the briefing shows NO bridge
///     section. It NEVER means "no bridges exist" and MUST NOT be phrased
///     as an all-clear.
///   * A site with NO bearing is KEPT when it is within the corridor: an
///     extra caution is acceptable, a missed bridge is not.
///   * KNOWN ERROR DIRECTIONS (named so no consumer oversells the bias):
///     the count can OVER-count — there is no vertical discrimination, so a
///     drivable viaduct running PARALLEL to the route within the corridor
///     is counted even when the driver's road passes beneath/beside it and
///     she never touches its deck (an over-warn, bounded by the same
///     cry-wolf calibration as the advisor). It can also UNDER-count —
///     OSM completeness bounds the dataset, and near a sharp route turn the
///     nearest polyline segment can carry the PRE-turn bearing and
///     bearing-reject a real bridge at the intersection approach. The
///     "fail toward warning" rule above is therefore a design lean, not a
///     guarantee that no real bridge is ever missed.
///
/// This module is pure Dart (no Flutter imports). Asset/network loading and
/// UI phrasing live in later wiring layers; this file takes decoded data.
library;

import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// One mapped bridge way: a representative point plus, where OSM has one,
/// the way's undirected bearing folded to `[0, 180)`.
class BridgeSite {
  const BridgeSite({
    required this.wayId,
    required this.lat,
    required this.lon,
    this.bearingDeg,
  });

  /// OSM way id (provenance only — never shown to the driver).
  final int wayId;

  /// WGS84 latitude in `[-90, 90]`.
  final double lat;

  /// WGS84 longitude in `[-180, 180]`.
  final double lon;

  /// Undirected way bearing in whole degrees, folded to `[0, 179]`.
  /// `null` when the source data has no bearing — such a site is kept by
  /// the corridor match (fail toward warning).
  final int? bearingDeg;
}

/// The decoded bridge dataset: parsed sites plus the number of source rows
/// that were skipped as malformed (surfaced so the wiring layer can log an
/// honest data-quality signal instead of silently shrinking the dataset).
class BridgeCsvParseResult {
  const BridgeCsvParseResult({
    required this.sites,
    required this.skippedRowCount,
  });

  final List<BridgeSite> sites;
  final int skippedRowCount;
}

/// The corridor-match outcome. [clusterCount] is the number the driver may
/// see (phrased as approximate); [keptSiteCount] and [skippedRowCount] are
/// diagnostics for tests and honest logging.
class BridgeCorridorResult {
  const BridgeCorridorResult({
    required this.clusterCount,
    required this.keptSiteCount,
    required this.skippedRowCount,
  });

  /// Distinct bridge sites a driver experiences (120 m single-linkage
  /// clusters of kept ways), NOT raw OSM ways.
  final int clusterCount;

  /// Ways that survived the bbox + distance + bearing gates, pre-clustering.
  final int keptSiteCount;

  /// Malformed source rows skipped at parse time (threaded through from
  /// [parseBridgeCsv] by the caller; 0 when the caller did not parse CSV).
  final int skippedRowCount;
}

const String _expectedHeader = 'way_id,lat,lon,bearing_deg';

/// Parses the bridge-site CSV (`way_id,lat,lon,bearing_deg`; lat/lon
/// 5-decimal doubles; bearing optional). Malformed rows are skipped and
/// counted, never thrown on: a bad row must not sink the whole briefing.
BridgeCsvParseResult parseBridgeCsv(String csvText) {
  final sites = <BridgeSite>[];
  var skipped = 0;
  var headerSeen = false;
  for (final rawLine in csvText.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    if (!headerSeen) {
      headerSeen = true;
      if (line == _expectedHeader) continue;
      // No header — fall through and parse this line as a data row.
    }
    final site = _parseRow(line);
    if (site == null) {
      skipped++;
    } else {
      sites.add(site);
    }
  }
  return BridgeCsvParseResult(sites: sites, skippedRowCount: skipped);
}

BridgeSite? _parseRow(String line) {
  final fields = line.split(',');
  // 3 fields = bearing column absent entirely; 4 = bearing present or blank.
  if (fields.length < 3 || fields.length > 4) return null;
  final wayId = int.tryParse(fields[0].trim());
  final lat = double.tryParse(fields[1].trim());
  final lon = double.tryParse(fields[2].trim());
  if (wayId == null || lat == null || lon == null) return null;
  if (!lat.isFinite || lat < -90 || lat > 90) return null;
  if (!lon.isFinite || lon < -180 || lon > 180) return null;
  int? bearing;
  if (fields.length == 4) {
    final raw = fields[3].trim();
    if (raw.isNotEmpty) {
      bearing = int.tryParse(raw);
      if (bearing == null || bearing < 0 || bearing > 179) return null;
    }
  }
  return BridgeSite(wayId: wayId, lat: lat, lon: lon, bearingDeg: bearing);
}

/// Corridor distance: a site further than this from the route polyline is
/// not "on" the route.
const double _corridorMeters = 30.0;

/// Bbox prefilter expansion — generous relative to [_corridorMeters] so the
/// prefilter can never drop a site the distance gate would keep.
const double _bboxExpandMeters = 100.0;

/// Bearing gate: a bridge ON the route runs parallel to it; an overpass
/// CROSSING it is near-perpendicular and must NOT be counted.
const double _bearingToleranceDeg = 30.0;

/// Cluster radius: kept ways within this distance (single linkage) are the
/// same bridge site as the driver experiences it.
const double _clusterMeters = 120.0;

const double _earthRadiusMeters = 6371000.0;
const double _metersPerDegreeLat = _earthRadiusMeters * math.pi / 180.0;

/// Matches [sites] against the route polyline [routeShape] (the shape a
/// `RouteResult` already carries) and returns the clustered on-route count.
///
/// A route with fewer than 2 points has no polyline to match against: the
/// result is all-zero and the consumer shows NO bridge section (honest
/// degradation — no substitute claim).
BridgeCorridorResult countBridgeSitesOnRoute(
  List<BridgeSite> sites,
  List<LatLng> routeShape, {
  int skippedRowCount = 0,
}) {
  if (sites.isEmpty || routeShape.length < 2) {
    return BridgeCorridorResult(
      clusterCount: 0,
      keptSiteCount: 0,
      skippedRowCount: skippedRowCount,
    );
  }

  // Local equirectangular frame anchored at the route's first point. At
  // route scale (tens of km) this keeps the math on plain doubles with a
  // single cos(lat) factor — cheap and easily testable.
  final lat0 = routeShape.first.latitude;
  final lon0 = routeShape.first.longitude;
  final metersPerDegreeLon =
      _metersPerDegreeLat * math.cos(lat0 * math.pi / 180.0);

  (double, double) toXy(double lat, double lon) =>
      ((lon - lon0) * metersPerDegreeLon, (lat - lat0) * _metersPerDegreeLat);

  final route = <(double, double)>[
    for (final p in routeShape) toXy(p.latitude, p.longitude),
  ];

  // 1. bbox prefilter (in local meters, expanded by _bboxExpandMeters).
  var minX = double.infinity, maxX = double.negativeInfinity;
  var minY = double.infinity, maxY = double.negativeInfinity;
  for (final (x, y) in route) {
    minX = math.min(minX, x);
    maxX = math.max(maxX, x);
    minY = math.min(minY, y);
    maxY = math.max(maxY, y);
  }
  minX -= _bboxExpandMeters;
  maxX += _bboxExpandMeters;
  minY -= _bboxExpandMeters;
  maxY += _bboxExpandMeters;

  final kept = <(double, double)>[];
  for (final site in sites) {
    final (sx, sy) = toXy(site.lat, site.lon);
    if (sx < minX || sx > maxX || sy < minY || sy > maxY) continue;

    // 2. distance gate: nearest segment of the polyline.
    var bestDistSq = double.infinity;
    var bestSegment = -1;
    for (var i = 0; i < route.length - 1; i++) {
      final d = _pointToSegmentDistSq(sx, sy, route[i], route[i + 1]);
      if (d < bestDistSq) {
        bestDistSq = d;
        bestSegment = i;
      }
    }
    if (bestDistSq > _corridorMeters * _corridorMeters) continue;

    // 3. bearing gate on the LOCAL route segment; a bearing-less site (or a
    // degenerate zero-length segment) is KEPT — fail toward warning.
    final bearing = site.bearingDeg;
    if (bearing != null) {
      final segBearing = _segmentBearingDeg(route[bestSegment], route[bestSegment + 1]);
      if (segBearing != null && _foldedBearingDiff(bearing.toDouble(), segBearing) > _bearingToleranceDeg) {
        continue;
      }
    }
    kept.add((sx, sy));
  }

  return BridgeCorridorResult(
    clusterCount: _clusterCount(kept, _clusterMeters),
    keptSiteCount: kept.length,
    skippedRowCount: skippedRowCount,
  );
}

double _pointToSegmentDistSq(
  double px,
  double py,
  (double, double) a,
  (double, double) b,
) {
  final (ax, ay) = a;
  final (bx, by) = b;
  final dx = bx - ax;
  final dy = by - ay;
  final lengthSq = dx * dx + dy * dy;
  double qx, qy;
  if (lengthSq == 0) {
    qx = ax;
    qy = ay;
  } else {
    final t = (((px - ax) * dx + (py - ay) * dy) / lengthSq).clamp(0.0, 1.0);
    qx = ax + t * dx;
    qy = ay + t * dy;
  }
  final ex = px - qx;
  final ey = py - qy;
  return ex * ex + ey * ey;
}

/// Undirected segment bearing folded to `[0, 180)`, or `null` for a
/// zero-length segment (no direction to compare against).
double? _segmentBearingDeg((double, double) a, (double, double) b) {
  final dx = b.$1 - a.$1;
  final dy = b.$2 - a.$2;
  if (dx == 0 && dy == 0) return null;
  final deg = math.atan2(dx, dy) * 180.0 / math.pi; // 0 = north, 90 = east.
  return ((deg % 180.0) + 180.0) % 180.0;
}

/// Angular difference between two undirected bearings, in `[0, 90]`.
double _foldedBearingDiff(double a, double b) {
  final d = ((a - b) % 180.0 + 180.0) % 180.0;
  return math.min(d, 180.0 - d);
}

/// Single-linkage clustering: connected components of the "within
/// [radiusMeters]" graph. Site counts are small post-gate (a route crosses
/// tens of bridges, not thousands), so O(n²) is fine.
int _clusterCount(List<(double, double)> points, double radiusMeters) {
  if (points.isEmpty) return 0;
  final radiusSq = radiusMeters * radiusMeters;
  final clusterOf = List<int>.filled(points.length, -1);
  var clusters = 0;
  for (var i = 0; i < points.length; i++) {
    if (clusterOf[i] != -1) continue;
    clusterOf[i] = clusters;
    // Breadth-first flood over the within-radius graph.
    final queue = <int>[i];
    while (queue.isNotEmpty) {
      final current = queue.removeLast();
      for (var j = 0; j < points.length; j++) {
        if (clusterOf[j] != -1) continue;
        final dx = points[current].$1 - points[j].$1;
        final dy = points[current].$2 - points[j].$2;
        if (dx * dx + dy * dy <= radiusSq) {
          clusterOf[j] = clusters;
          queue.add(j);
        }
      }
    }
    clusters++;
  }
  return clusters;
}
