/// Unit tests for the bridge-asset generator's row-emission rules
/// (`tool/generate_bridge_asset.dart` — dev-time only, never in the vehicle).
///
/// The load-bearing honesty rules under test:
///   * a CLOSED (or near-closed) way — first node == last node, e.g. a
///     loop/roundabout deck carrying `bridge=yes` — must emit a BLANK
///     bearing, never the fabricated `atan2(0,0)` == due-north 0° that the
///     corridor matcher would treat as real and bearing-REJECT on ~2/3 of
///     route orientations (an invisible missed-bridge, against the module's
///     own "a missed bridge is not acceptable" contract);
///   * a CURVED way (local bearings deviating from the chord beyond the
///     matcher's own ±30° gate) must also emit a BLANK bearing — the chord
///     of a sweeping viaduct matches no part of the deck;
///   * sample points lie ON the deck (arc-length sampling), never at the
///     node-mean centroid a curved deck pulls off the deck;
///   * a straight way still gets its honest chord bearing;
///   * a way without a usable line (< 2 nodes) is skipped entirely.
///
/// Every emitted row must round-trip through the REAL `parseBridgeCsv`, so
/// the generator can never drift from the app-side contract — and the
/// curved-way output is proven KEPT by the REAL corridor matcher (the class
/// the old node-mean + chord-bearing reduction silently dropped).
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_snow_scene/services/bridge_corridor_read.dart';

import '../../tool/generate_bridge_asset.dart';

/// An Overpass `out geom;` way element as the generator consumes it.
Map<String, dynamic> way(int id, List<(double, double)> nodes) => {
  'type': 'way',
  'id': id,
  'geometry': [
    for (final (lat, lon) in nodes) {'lat': lat, 'lon': lon},
  ],
};

/// Parses generator rows through the REAL app-side CSV parser (with header),
/// asserting nothing was skipped as malformed.
List<BridgeSite> roundTrip(List<String> rows) {
  final parsed = parseBridgeCsv(
    'way_id,lat,lon,bearing_deg\n${rows.join('\n')}\n',
  );
  expect(
    parsed.skippedRowCount,
    0,
    reason: 'every generator row must round-trip through parseBridgeCsv',
  );
  return parsed.sites;
}

void main() {
  const latAkita = 39.7;
  const lonAkita = 140.1;
  // ~1 degree of latitude in meters / ~1 degree of longitude at 39.7 N.
  const mPerDegLat = 111194.9;
  final mPerDegLon = mPerDegLat * 0.7694; // cos(39.7°)

  test(
    'straight short east-west way → ONE on-deck sample, chord bearing 90',
    () {
      final rows = csvRowsForWay(
        way(1, [(latAkita, lonAkita), (latAkita, lonAkita + 60 / mPerDegLon)]),
      );
      final sites = roundTrip(rows);
      expect(sites, hasLength(1));
      expect(sites.single.bearingDeg, 90);
      // The sample sits ON the deck (here: the path midpoint).
      expect(sites.single.lat, closeTo(latAkita, 1e-5));
      expect(sites.single.lon, closeTo(lonAkita + 30 / mPerDegLon, 1e-4));
    },
  );

  test('straight long way (~200 m) → multiple samples inside the 120 m '
      'cluster radius, all with the honest chord bearing', () {
    final rows = csvRowsForWay(
      way(6, [(latAkita, lonAkita), (latAkita, lonAkita + 200 / mPerDegLon)]),
    );
    final sites = roundTrip(rows);
    expect(sites, hasLength(2));
    for (final site in sites) {
      expect(site.bearingDeg, 90);
      expect(site.lat, closeTo(latAkita, 1e-5));
    }
    // Samples at 50 m and 150 m: 100 m apart — the matcher clusters them
    // back into ONE experienced site.
    final gapMeters = (sites[1].lon - sites[0].lon).abs() * mPerDegLon;
    expect(gapMeters, closeTo(100, 2));
  });

  test('CURVED way (90° L-shape) → BLANK bearing + samples ON the legs '
      '(not the off-deck node-mean), and the REAL matcher KEEPS it', () {
    final dLat = 100 / mPerDegLat;
    final dLon = 100 / mPerDegLon;
    // East 100 m, then north 100 m: chord bearing ~45°, each leg ~45° off it.
    final curved = way(7, [
      (latAkita, lonAkita),
      (latAkita, lonAkita + dLon),
      (latAkita + dLat, lonAkita + dLon),
    ]);
    final sites = roundTrip(csvRowsForWay(curved));
    expect(sites, hasLength(2));
    for (final site in sites) {
      expect(
        site.bearingDeg,
        isNull,
        reason: 'a 45°-off chord could bearing-reject the deck itself',
      );
    }
    // Samples at path 50 m / 150 m: midpoints of the two legs.
    expect(sites[0].lat, closeTo(latAkita, 1e-5));
    expect(sites[0].lon, closeTo(lonAkita + 50 / mPerDegLon, 1e-4));
    expect(sites[1].lat, closeTo(latAkita + 50 / mPerDegLat, 1e-5));
    expect(sites[1].lon, closeTo(lonAkita + dLon, 1e-4));

    // The matcher keeps the curved bridge for a route driving ALONG it —
    // the class the old node-mean centroid (33 m off both legs, outside the
    // 30 m corridor) silently dropped.
    final route = <LatLng>[
      LatLng(latAkita, lonAkita),
      LatLng(latAkita, lonAkita + dLon),
      LatLng(latAkita + dLat, lonAkita + dLon),
    ];
    final result = countBridgeSitesOnRoute(sites, route);
    expect(result.keptSiteCount, 2);
    expect(
      result.clusterCount,
      1,
      reason: 'one curved bridge, experienced once — samples merge',
    );
  });

  test('CLOSED way (first node == last node) → BLANK bearing, site kept', () {
    // A ~square loop deck, ~100 m sides, returning to its first node.
    final dLat = 100 / mPerDegLat;
    final dLon = 100 / mPerDegLon;
    final rows = csvRowsForWay(
      way(2, [
        (latAkita, lonAkita),
        (latAkita, lonAkita + dLon),
        (latAkita + dLat, lonAkita + dLon),
        (latAkita + dLat, lonAkita),
        (latAkita, lonAkita), // closed
      ]),
    );
    final sites = roundTrip(rows);
    expect(sites, isNotEmpty);
    for (final site in sites) {
      expect(
        site.bearingDeg,
        isNull,
        reason:
            'a closed way has no chord direction — a fabricated 0° '
            'would let the matcher bearing-reject a real bridge',
      );
      // Each sample sits ON the loop's rim, never at its interior mean
      // (center ≈ (+50 m, +50 m), which sits ~50 m off every side — outside
      // the matcher's 30 m corridor).
      final northMeters = (site.lat - latAkita) * mPerDegLat;
      final eastMeters = (site.lon - lonAkita) * mPerDegLon;
      final centerDist = math.sqrt(
        math.pow(northMeters - 50, 2).toDouble() +
            math.pow(eastMeters - 50, 2).toDouble(),
      );
      expect(
        centerDist,
        greaterThan(40),
        reason: 'an interior-mean point would be off the deck',
      );
    }
  });

  test('NEAR-closed way (endpoints ~5 m apart, U-shape) → BLANK bearing', () {
    final dLat = 80 / mPerDegLat;
    final rows = csvRowsForWay(
      way(3, [
        (latAkita, lonAkita),
        (latAkita + dLat, lonAkita),
        (latAkita + dLat, lonAkita + 60 / mPerDegLon),
        (latAkita + 5 / mPerDegLat, lonAkita), // back next to the start
      ]),
    );
    final sites = roundTrip(rows);
    expect(sites, isNotEmpty);
    for (final site in sites) {
      expect(
        site.bearingDeg,
        isNull,
        reason: 'a ~5 m chord cannot honestly define a deck direction',
      );
    }
  });

  test(
    'way with < 2 geometry nodes → skipped entirely (no half-honest row)',
    () {
      expect(csvRowsForWay(way(4, [(latAkita, lonAkita)])), isEmpty);
      expect(csvRowsForWay(way(5, [])), isEmpty);
    },
  );
}
