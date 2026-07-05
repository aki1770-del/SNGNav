import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:sngnav_snow_scene/services/bridge_corridor_read.dart';

void main() {
  group('parseBridgeCsv', () {
    test('happy path: header + rows, 5-decimal lat/lon, bearing parsed', () {
      const csv = 'way_id,lat,lon,bearing_deg\n'
          '123456,39.70018,140.11000,90\n'
          '345678,39.71234,140.09876,175\n';
      final result = parseBridgeCsv(csv);
      expect(result.skippedRowCount, 0);
      expect(result.sites, hasLength(2));
      expect(result.sites[0].wayId, 123456);
      expect(result.sites[0].lat, closeTo(39.70018, 1e-9));
      expect(result.sites[0].lon, closeTo(140.11000, 1e-9));
      expect(result.sites[0].bearingDeg, 90);
      expect(result.sites[1].bearingDeg, 175);
    });

    test('blank bearing and missing bearing column both parse as null', () {
      const csv = 'way_id,lat,lon,bearing_deg\n'
          '1,39.70009,140.10600,\n'
          '2,39.70011,140.10700\n';
      final result = parseBridgeCsv(csv);
      expect(result.skippedRowCount, 0);
      expect(result.sites, hasLength(2));
      expect(result.sites[0].bearingDeg, isNull);
      expect(result.sites[1].bearingDeg, isNull);
    });

    test('malformed rows are skipped and counted, valid rows survive', () {
      const csv = 'way_id,lat,lon,bearing_deg\n'
          '1,39.70000,140.10000,90\n'
          'not_a_number,39.70000,140.10000,90\n'
          '2,91.50000,140.10000,90\n' // lat out of range
          '3,39.70000,140.10000,250\n' // bearing out of [0,179]
          '4,39.70000\n' // too few fields
          '5,39.70001,140.10001,45\n';
      final result = parseBridgeCsv(csv);
      expect(result.skippedRowCount, 4);
      expect(result.sites.map((s) => s.wayId), [1, 5]);
    });

    test('tolerates CRLF endings and blank lines without counting them', () {
      const csv = 'way_id,lat,lon,bearing_deg\r\n'
          '1,39.70000,140.10000,90\r\n'
          '\r\n'
          '2,39.70001,140.10001,\r\n';
      final result = parseBridgeCsv(csv);
      expect(result.skippedRowCount, 0);
      expect(result.sites, hasLength(2));
    });

    test('empty input parses to zero sites, zero skipped, no throw', () {
      final result = parseBridgeCsv('');
      expect(result.sites, isEmpty);
      expect(result.skippedRowCount, 0);
    });
  });

  group('countBridgeSitesOnRoute', () {
    // Synthetic straight west→east route near Akita (39.7N, 140.1E) so the
    // equirectangular math runs with a real cos(lat) factor (~0.769).
    const latAkita = 39.7;
    const lonAkita = 140.1;
    final mPerDegLat = 6371000.0 * math.pi / 180.0;
    final mPerDegLon = mPerDegLat * math.cos(latAkita * math.pi / 180.0);
    double latAt(double metersNorth) => latAkita + metersNorth / mPerDegLat;
    double lonAt(double metersEast) => lonAkita + metersEast / mPerDegLon;

    // ~2 km due east: local segment bearing 90°, folded 90.
    final route = <LatLng>[
      for (var m = 0.0; m <= 2000.0; m += 400.0) LatLng(latAkita, lonAt(m)),
    ];

    BridgeSite site(int id, double north, double east, {int? bearing}) =>
        BridgeSite(
          wayId: id,
          lat: latAt(north),
          lon: lonAt(east),
          bearingDeg: bearing,
        );

    test('(a) parallel bridge within 30 m of route is counted', () {
      final result =
          countBridgeSitesOnRoute([site(1, 20, 1000, bearing: 90)], route);
      expect(result.keptSiteCount, 1);
      expect(result.clusterCount, 1);
    });

    test('(b) perpendicular overpass within 10 m is NOT counted', () {
      final result =
          countBridgeSitesOnRoute([site(2, 10, 600, bearing: 0)], route);
      expect(result.keptSiteCount, 0);
      expect(result.clusterCount, 0);
    });

    test('(c) parallel bridge 80 m away is NOT counted', () {
      final result =
          countBridgeSitesOnRoute([site(3, 80, 1400, bearing: 90)], route);
      expect(result.keptSiteCount, 0);
      expect(result.clusterCount, 0);
    });

    test('(d) bearing-less bridge within 30 m IS counted (fail toward warning)',
        () {
      final result = countBridgeSitesOnRoute([site(4, -15, 300)], route);
      expect(result.keptSiteCount, 1);
      expect(result.clusterCount, 1);
    });

    test('(e) two on-route ways 50 m apart cluster to ONE site', () {
      final result = countBridgeSitesOnRoute(
        [site(5, 5, 1000, bearing: 90), site(6, 5, 1050, bearing: 90)],
        route,
      );
      expect(result.keptSiteCount, 2);
      expect(result.clusterCount, 1);
    });

    test('(f) two sites 500 m apart stay TWO clusters', () {
      final result = countBridgeSitesOnRoute(
        [site(7, 5, 200, bearing: 90), site(8, 5, 700, bearing: 90)],
        route,
      );
      expect(result.keptSiteCount, 2);
      expect(result.clusterCount, 2);
    });

    test('(g) empty route and empty sites both give zero, no throw', () {
      expect(
        countBridgeSitesOnRoute([site(9, 0, 0, bearing: 90)], const []),
        isA<BridgeCorridorResult>()
            .having((r) => r.clusterCount, 'clusterCount', 0)
            .having((r) => r.keptSiteCount, 'keptSiteCount', 0),
      );
      final empty = countBridgeSitesOnRoute(const [], route);
      expect(empty.clusterCount, 0);
      expect(empty.keptSiteCount, 0);
    });

    test('single-point route has no polyline: zero, no throw', () {
      final result = countBridgeSitesOnRoute(
        [site(10, 0, 0, bearing: 90)],
        [LatLng(latAkita, lonAkita)],
      );
      expect(result.clusterCount, 0);
      expect(result.keptSiteCount, 0);
    });

    test('site far outside the expanded route bbox is dropped', () {
      final result =
          countBridgeSitesOnRoute([site(11, 10000, 1000, bearing: 90)], route);
      expect(result.keptSiteCount, 0);
      expect(result.clusterCount, 0);
    });

    test('bearing gate folds across the 0/180 seam', () {
      // Route heading slightly west of due north: folded bearing ~178.
      final northRoute = <LatLng>[
        LatLng(latAkita, lonAkita),
        LatLng(latAt(222), lonAt(-8.6)),
      ];
      // A site bearing of 3 differs by ~5° once folded — parallel, kept.
      final kept = countBridgeSitesOnRoute(
        [
          BridgeSite(
            wayId: 12,
            lat: latAt(111),
            lon: lonAt(-4.3),
            bearingDeg: 3,
          ),
        ],
        northRoute,
      );
      expect(kept.keptSiteCount, 1);
      // A site bearing of 88 is near-perpendicular to the same segment.
      final dropped = countBridgeSitesOnRoute(
        [
          BridgeSite(
            wayId: 13,
            lat: latAt(111),
            lon: lonAt(-4.3),
            bearingDeg: 88,
          ),
        ],
        northRoute,
      );
      expect(dropped.keptSiteCount, 0);
    });

    test('skippedRowCount from parsing threads through unchanged', () {
      final result = countBridgeSitesOnRoute(
        [site(14, 5, 1000, bearing: 90)],
        route,
        skippedRowCount: 7,
      );
      expect(result.skippedRowCount, 7);
      expect(result.clusterCount, 1);
    });

    test('chained clustering: 3 ways at 100 m spacing single-link to ONE', () {
      final result = countBridgeSitesOnRoute(
        [
          site(15, 5, 800, bearing: 90),
          site(16, 5, 900, bearing: 90),
          site(17, 5, 1000, bearing: 90),
        ],
        route,
      );
      expect(result.keptSiteCount, 3);
      expect(result.clusterCount, 1,
          reason: 'single linkage chains 100 m gaps into one experienced site');
    });

    // BOUNDARY PAIRS: pin each calibrated constant just inside AND just
    // outside, in BOTH directions — the loose brackets above (20/80 m,
    // 5°/88°, 100/500 m) would let a silent NARROWING (e.g. corridor 30→25 m,
    // dropping real bridges — the fail-toward-silence direction the module's
    // own contract forbids) ship green.

    test('corridor boundary: 28 m kept, 33 m dropped (pins 30 m both ways)',
        () {
      expect(
        countBridgeSitesOnRoute([site(20, 28, 1000, bearing: 90)], route)
            .keptSiteCount,
        1,
        reason: 'a narrowed corridor would silently drop this real bridge',
      );
      expect(
        countBridgeSitesOnRoute([site(21, 33, 1000, bearing: 90)], route)
            .keptSiteCount,
        0,
        reason: 'a widened corridor would over-count neighbouring roads',
      );
    });

    test('bearing boundary: 29° diff kept, 31° dropped (pins ±30° both ways)',
        () {
      // Route segment bearing 90; site bearings 61 / 121 → folded diffs
      // 29 / 31.
      expect(
        countBridgeSitesOnRoute([site(22, 5, 1000, bearing: 61)], route)
            .keptSiteCount,
        1,
        reason: 'a narrowed gate would drop a slightly-skewed real bridge',
      );
      expect(
        countBridgeSitesOnRoute([site(23, 5, 1000, bearing: 121)], route)
            .keptSiteCount,
        0,
        reason: 'a widened gate would start counting skewed overpasses',
      );
    });

    test('cluster boundary: 110 m gap → ONE site, 130 m gap → TWO '
        '(pins 120 m both ways)', () {
      final one = countBridgeSitesOnRoute(
        [site(24, 5, 1000, bearing: 90), site(25, 5, 1110, bearing: 90)],
        route,
      );
      expect(one.keptSiteCount, 2);
      expect(one.clusterCount, 1);
      final two = countBridgeSitesOnRoute(
        [site(26, 5, 1000, bearing: 90), site(27, 5, 1130, bearing: 90)],
        route,
      );
      expect(two.keptSiteCount, 2);
      expect(two.clusterCount, 2);
    });
  });
}
