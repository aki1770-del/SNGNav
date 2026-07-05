/// Dev-time generator for the offline Akita bridge asset.
///
/// Reads a raw Overpass API JSON response — drivable-class `bridge=yes` ways
/// in Akita prefecture downloaded with `out geom;` — and emits the compact
/// CSV the pre-trip briefing uses to estimate how many bridges lie on a
/// route (bridge decks freeze before the road surface does).
///
/// Usage:
///   `dart run tool/generate_bridge_asset.dart <overpass.json> <out.csv>`
///
/// CSV columns: `way_id,lat,lon,bearing_deg` — one row PER SAMPLE POINT (a
/// way longer than ~100 m of path emits several rows sharing its `way_id`,
/// which is provenance-only; the matcher's 120 m clustering merges them back
/// into one experienced site).
///   * `lat`/`lon`    — a point ON the way's polyline (arc-length sampled),
///                      5 dp. NOT the node-mean centroid: a curved deck's
///                      node-mean sits INSIDE the arc — for a loop/hairpin
///                      bridge near the circle CENTER, off the deck by more
///                      than the matcher's 30 m corridor — which silently
///                      DROPPED exactly the elevated, icing-prone curved
///                      class. An on-path sample is on the deck by
///                      construction.
///   * `bearing_deg`  — great-circle bearing from the way's first node to
///                      its last, folded to [0,180) as an integer. The fold
///                      makes it an undirected road bearing, so the route
///                      matcher can tell a bridge ON the route from an
///                      overpass CROSSING it. BLANK when the chord cannot
///                      honestly describe the deck: a closed/near-closed way
///                      (loop or roundabout deck — `atan2(0,0)` would
///                      FABRICATE a confident due-north bearing), or a
///                      CURVED way whose local segment bearings deviate from
///                      the chord beyond the matcher's own ±30° tolerance
///                      (the chord of a 90° sweeping viaduct matches no part
///                      of the deck). The matcher KEEPS bearing-less
///                      in-corridor sites (fail toward warning: an extra
///                      caution is acceptable, a missed bridge is not —
///                      `bridge_corridor_read.dart`).
///
/// The shipped `assets/bridges_akita.csv.gz` was regenerated with these
/// rules on 2026-07-05 from the sha256-verified raw retrieval documented in
/// `assets/bridges_akita.ATTRIBUTION.md` (5,931 ways → 6,813 sample rows,
/// 1,061 honest blank bearings).
///
/// The emitted DATA is © OpenStreetMap contributors, ODbL — it ships as a
/// separate asset file (never inlined into BSD-3 source) precisely to keep
/// that license boundary. This tool never runs in the vehicle; the app
/// ships only the gzipped CSV.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

double _degToRad(double deg) => deg * math.pi / 180.0;

const double _earthRadiusMeters = 6371000.0;
const double _metersPerDegreeLat = _earthRadiusMeters * math.pi / 180.0;

/// Minimum first-to-last chord length that can honestly define a way
/// direction. Below this (a closed loop/roundabout deck, or endpoints within
/// GPS noise of each other) the bearing field is emitted BLANK — the matcher
/// keeps bearing-less in-corridor sites, fail toward warning.
const double _minChordMeters = 10.0;

/// Maximum folded deviation of any local segment bearing from the chord
/// bearing before the way counts as CURVED and its bearing is emitted BLANK.
/// Deliberately equal to the matcher's own gate tolerance
/// (`bridge_corridor_read.dart` `_bearingToleranceDeg`): a chord that is
/// further than the gate's tolerance from some stretch of the deck can
/// bearing-reject that stretch.
const double _maxChordDeviationDeg = 30.0;

/// Segments shorter than this are ignored by the straightness check — a
/// couple of meters of node jitter must not blank an honestly straight way.
const double _minSegmentMeters = 3.0;

/// Arc-length sample spacing along a way's polyline. Under the matcher's
/// 120 m single-linkage cluster radius, so one long way's samples merge back
/// into one experienced site.
const double _sampleSpacingMeters = 100.0;

/// Initial great-circle bearing from (lat1,lon1) to (lat2,lon2), in [0,360).
double _initialBearingDeg(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = _degToRad(lat1);
  final phi2 = _degToRad(lat2);
  final dLambda = _degToRad(lon2 - lon1);
  final y = math.sin(dLambda) * math.cos(phi2);
  final x = math.cos(phi1) * math.sin(phi2) -
      math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  return (math.atan2(y, x) * 180.0 / math.pi + 360.0) % 360.0;
}

/// Equirectangular distance in meters — exact enough at bridge scale (tens
/// to hundreds of meters) for the degenerate-chord decision.
double _metersBetween(double lat1, double lon1, double lat2, double lon2) {
  final midLat = _degToRad((lat1 + lat2) / 2.0);
  final dx = (lon2 - lon1) * _metersPerDegreeLat * math.cos(midLat);
  final dy = (lat2 - lat1) * _metersPerDegreeLat;
  return math.sqrt(dx * dx + dy * dy);
}

/// Folded difference between two undirected bearings, in `[0, 90]`.
double _foldedBearingDiff(double a, double b) {
  final d = ((a - b) % 180.0 + 180.0) % 180.0;
  return math.min(d, 180.0 - d);
}

/// Emits the CSV row(s) for ONE Overpass way element, or the empty list when
/// the way has no usable geometry (< 2 nodes — a point without a line would
/// be a substitute claim). Public + pure so the emission rules (on-path
/// sampling, degenerate-chord + curved-way blank bearing, honest folding)
/// are unit-testable.
List<String> csvRowsForWay(Map<String, dynamic> way) {
  final geometry =
      ((way['geometry'] as List?) ?? const []).cast<Map<String, dynamic>>();
  if (geometry.length < 2) return const [];

  final lats = <double>[
    for (final node in geometry) (node['lat'] as num).toDouble(),
  ];
  final lons = <double>[
    for (final node in geometry) (node['lon'] as num).toDouble(),
  ];

  // Cumulative arc length along the polyline, in meters.
  final cum = List<double>.filled(lats.length, 0.0);
  for (var i = 1; i < lats.length; i++) {
    cum[i] = cum[i - 1] +
        _metersBetween(lats[i - 1], lons[i - 1], lats[i], lons[i]);
  }
  final pathLen = cum.last;

  // --- Bearing: honest chord, or an honest BLANK -------------------------
  final chordMeters =
      _metersBetween(lats.first, lons.first, lats.last, lons.last);
  String bearingField;
  if (chordMeters < _minChordMeters) {
    // Closed or near-closed way: no chord, no direction — an honest BLANK,
    // never a fabricated atan2(0,0) == due-north.
    bearingField = '';
  } else {
    final chordBearing = _initialBearingDeg(
            lats.first, lons.first, lats.last, lons.last) %
        180.0;
    // Straightness check against the matcher's own tolerance: if any local
    // stretch of the deck deviates from the chord beyond what the gate
    // accepts, the chord bearing could bearing-REJECT a bridge the driver is
    // ON — blank it instead (kept, fail toward warning). A way made only of
    // sub-jitter segments cannot be certified straight either.
    var certifiedStraight = false;
    var curved = false;
    for (var i = 1; i < lats.length && !curved; i++) {
      if (_metersBetween(lats[i - 1], lons[i - 1], lats[i], lons[i]) <
          _minSegmentMeters) {
        continue;
      }
      final segBearing = _initialBearingDeg(
              lats[i - 1], lons[i - 1], lats[i], lons[i]) %
          180.0;
      if (_foldedBearingDiff(segBearing, chordBearing) >
          _maxChordDeviationDeg) {
        curved = true;
      } else {
        certifiedStraight = true;
      }
    }
    if (curved || !certifiedStraight) {
      bearingField = '';
    } else {
      // Fold to undirected [0,180): round AFTER the fold, then fold the
      // rounding artifact 180 back to 0 (179.6° rounds to 180° == 0°).
      bearingField = '${chordBearing.round() % 180}';
    }
  }

  // --- Position(s): arc-length samples ON the deck -----------------------
  // n equal arcs, one sample at each arc's midpoint. Spacing ≤ 100 m keeps
  // the samples inside the matcher's 120 m cluster radius (one experienced
  // site); the midpoint of a straight short way coincides with its centroid.
  (double, double) pointAt(double d) {
    if (pathLen <= 0) return (lats.first, lons.first);
    var i = 1;
    while (i < cum.length - 1 && cum[i] < d) {
      i++;
    }
    final segLen = cum[i] - cum[i - 1];
    final t = segLen <= 0 ? 0.0 : ((d - cum[i - 1]) / segLen).clamp(0.0, 1.0);
    return (
      lats[i - 1] + t * (lats[i] - lats[i - 1]),
      lons[i - 1] + t * (lons[i] - lons[i - 1]),
    );
  }

  final sampleCount =
      pathLen <= 0 ? 1 : math.max(1, (pathLen / _sampleSpacingMeters).ceil());
  final rows = <String>[];
  for (var s = 0; s < sampleCount; s++) {
    final (lat, lon) = pointAt(pathLen * (s + 0.5) / sampleCount);
    rows.add('${way['id']},${lat.toStringAsFixed(5)},'
        '${lon.toStringAsFixed(5)},$bearingField');
  }
  return rows;
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
        'Usage: dart run tool/generate_bridge_asset.dart <overpass.json> <out.csv>');
    exit(64);
  }
  final input = File(args[0]);
  if (!input.existsSync()) {
    stderr.writeln('Input not found: ${args[0]}');
    exit(66);
  }

  final root = json.decode(input.readAsStringSync()) as Map<String, dynamic>;
  final elements = (root['elements'] as List).cast<Map<String, dynamic>>();

  final ways = elements.where((e) => e['type'] == 'way').toList()
    ..sort((a, b) => (a['id'] as int).compareTo(b['id'] as int));

  final rows = <String>[];
  var skipped = 0;
  for (final way in ways) {
    final wayRows = csvRowsForWay(way);
    if (wayRows.isEmpty) {
      // No usable line (< 2 nodes): a centroid without a bearing would be a
      // substitute claim, so the way is dropped rather than emitted
      // half-honest.
      skipped++;
      continue;
    }
    rows.addAll(wayRows);
  }

  final out = File(args[1]);
  out.writeAsStringSync('way_id,lat,lon,bearing_deg\n${rows.join('\n')}\n');

  stdout.writeln('elements=${elements.length} ways=${ways.length} '
      'rows=${rows.length} skipped=$skipped -> ${args[1]}');
  exit(0);
}
