/// Unit tests for the pre-trip ROUTE-BRIDGE caution provider: the one-shot
/// resolve's honest-absence arms (including the coverage gate), the cold gate
/// (window-min-temp ≤ the advisor's +3.0 °C radiative-frost ceiling at EITHER
/// endpoint arms it; warm point evidence falls through to the season band),
/// and the REAL bundled asset (gunzip + parse round-trip).
///
/// Network/asset IO is injected as STUB closures — no real sockets (the
/// pretrip_live_forecast_test idiom). Only the bundled-asset test touches the
/// real `assets/bridges_akita.csv.gz` via rootBundle.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:sngnav_snow_scene/providers/pretrip_route_bridges.dart';
import 'package:sngnav_snow_scene/services/bridge_corridor_read.dart';

/// A ~2.2 km due-north route in Akita (39.72 N, 140.10 E).
final List<LatLng> _route = [
  const LatLng(39.72000, 140.10000),
  const LatLng(39.74000, 140.10000),
];

/// Two bridge sites ON the route, ~1.1 km apart (> the 120 m cluster radius),
/// both bearing 0 (parallel to the north-heading route) ⇒ 2 clusters.
const String _csvTwoBridges = 'way_id,lat,lon,bearing_deg\n'
    '1,39.72500,140.10000,0\n'
    '2,39.73500,140.10000,0\n';

WeatherForecast _forecastCovering(DateTime departure, double temp) =>
    WeatherForecast(
      issuedAt: departure,
      hourly: [
        HourlyForecast(hour: departure, tempCelsius: temp),
        HourlyForecast(
            hour: departure.add(const Duration(hours: 1)), tempCelsius: temp),
      ],
    );

void main() {
  group('resolvePretripRouteBridges (honest-absence arms)', () {
    test('route fetch throws (RoutingException) → null, no throw', () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async =>
            throw const RoutingException('OSRM network error: down'),
        loadBridgeCsv: () async => _csvTwoBridges,
      );
      expect(r, isNull);
    });

    test('empty route shape (no usable geometry) → null', () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => <LatLng>[],
        loadBridgeCsv: () async => _csvTwoBridges,
      );
      expect(r, isNull);
    });

    test('single-point shape (< 2 points) → null', () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => [const LatLng(39.72, 140.10)],
        loadBridgeCsv: () async => _csvTwoBridges,
      );
      expect(r, isNull);
    });

    test('bridge data load throws → null', () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => throw Exception('asset missing'),
      );
      expect(r, isNull);
    });

    test('bridge data parses to zero sites → null', () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => 'way_id,lat,lon,bearing_deg\n',
      );
      expect(r, isNull);
    });

    test('good path: 2 on-route sites ⇒ 2 clusters', () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => _csvTwoBridges,
      );
      expect(r, isNotNull);
      expect(r!.clusterCount, 2);
      expect(r.keptSiteCount, 2);
      expect(r.skippedRowCount, 0);
    });

    test('sites far from the route ⇒ result with clusterCount 0 (not null)',
        () async {
      // Two sites BRACKETING the route (so the route stays inside the data's
      // coverage extent) but both kilometres off the 30 m corridor: a real
      // resolve with nothing to say — NOT the coverage-gate arm.
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => 'way_id,lat,lon,bearing_deg\n'
            '8,39.71000,140.05000,0\n'
            '9,39.75000,140.15000,0\n',
      );
      expect(r, isNotNull);
      expect(r!.clusterCount, 0);
    });

    test('route leaving the data coverage extent → null (honest absence, '
        'never a truncated count)', () async {
      // A cross-prefecture shape (toward Morioka): the second point sits far
      // east of the sites' own extent. Counting only the in-extent half would
      // ship a systematically wrong "about N" — the section must be ABSENT.
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => [
          const LatLng(39.72000, 140.10000),
          const LatLng(39.70000, 141.15000),
        ],
        loadBridgeCsv: () async => _csvTwoBridges,
      );
      expect(r, isNull);
    });

    test('malformed rows are skipped, counted, and threaded through',
        () async {
      final r = await resolvePretripRouteBridges(
        fetchRouteShape: () async => _route,
        loadBridgeCsv: () async => 'way_id,lat,lon,bearing_deg\n'
            '1,39.72500,140.10000,0\n'
            'garbage,row,here\n',
      );
      expect(r, isNotNull);
      expect(r!.clusterCount, 1);
      expect(r.skippedRowCount, 1);
    });
  });

  group('shouldShowBridgeCaution (cold gate)', () {
    final departure = DateTime(2026, 7, 15, 7, 15); // a WARM month on purpose
    const window = Duration(minutes: 30);

    test('clusterCount 0 → never shown (never an implied all-clear)', () {
      expect(
        shouldShowBridgeCaution(
          clusterCount: 0,
          liveForecast: _forecastCovering(departure, -10),
          departure: departure,
          window: window,
          now: DateTime(2026, 1, 15),
        ),
        isFalse,
      );
    });

    test('live window min ≤ +3.0 °C → shown (even in a warm month: evidence '
        'beats season)', () {
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: _forecastCovering(departure, 3.0), // ceiling inclusive
          departure: departure,
          window: window,
          now: departure,
        ),
        isTrue,
      );
    });

    test('live window warm (+10 °C) in January → STILL shown (a warm point '
        'reading is not corridor evidence; the season band is a floor)', () {
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: _forecastCovering(departure, 10),
          departure: departure,
          window: window,
          now: DateTime(2026, 1, 15),
        ),
        isTrue,
        reason: 'warm origin evidence must never suppress the winter band — '
            'the decks are elsewhere on the route',
      );
    });

    test('live window warm (+10 °C) in July → hidden (warm evidence + '
        'off-season: quiet)', () {
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: _forecastCovering(departure, 10),
          departure: departure,
          window: window,
          now: DateTime(2026, 7, 15),
        ),
        isFalse,
      );
    });

    test('only slots COVERING the window count (a freezing slot elsewhere in '
        'the timeseries must not fire the gate)', () {
      final f = WeatherForecast(
        issuedAt: departure,
        hourly: [
          // Covers the 07:15–07:45 window: warm.
          HourlyForecast(hour: departure, tempCelsius: 12),
          // Freezing, but 6 hours later — outside the window.
          HourlyForecast(
              hour: departure.add(const Duration(hours: 6)), tempCelsius: -5),
        ],
      );
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: f,
          departure: departure,
          window: window,
          // July, so the season band cannot mask a window-min fabrication:
          // only the -5 °C slot OUTSIDE the window could wrongly fire this.
          now: DateTime(2026, 7, 15),
        ),
        isFalse,
      );
    });

    test('freezing DESTINATION window arms the caution even when the origin '
        'is warm (cold at either endpoint counts)', () {
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: _forecastCovering(departure, 10),
          destForecast: _forecastCovering(departure, -2),
          departure: departure,
          window: window,
          // July: the band cannot be the cause — this is pure far-endpoint
          // evidence.
          now: DateTime(2026, 7, 15),
        ),
        isTrue,
        reason: 'the destination read is already on the same screen; a '
            'freezing far endpoint is corridor-relevant cold evidence',
      );
    });

    test('warm at BOTH endpoints outside the season band → hidden', () {
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: _forecastCovering(departure, 10),
          destForecast: _forecastCovering(departure, 8),
          departure: departure,
          window: window,
          now: DateTime(2026, 7, 15),
        ),
        isFalse,
      );
    });

    test('live forecast with NO slot covering the window → season band '
        '(no temperature evidence, no fabricated min)', () {
      final f = WeatherForecast(
        issuedAt: departure,
        hourly: [
          HourlyForecast(
              hour: departure.add(const Duration(hours: 6)), tempCelsius: -5),
        ],
      );
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: f,
          departure: departure,
          window: window,
          now: DateTime(2026, 1, 15),
        ),
        isTrue,
        reason: 'January + no evidence → season band keeps the caution',
      );
      expect(
        shouldShowBridgeCaution(
          clusterCount: 2,
          liveForecast: f,
          departure: departure,
          window: window,
          now: DateTime(2026, 7, 15),
        ),
        isFalse,
        reason: 'July + no evidence → quiet',
      );
    });

    test('no forecast: Oct–Apr shown, May–Sep hidden (full month sweep)', () {
      for (final month in const [10, 11, 12, 1, 2, 3, 4]) {
        expect(
          shouldShowBridgeCaution(
            clusterCount: 1,
            liveForecast: null,
            departure: departure,
            window: window,
            now: DateTime(2026, month, 15),
          ),
          isTrue,
          reason: 'month $month is in the compound-failure band '
              '(October: inland-Akita first-deck-ice month)',
        );
      }
      for (final month in const [5, 6, 7, 8, 9]) {
        expect(
          shouldShowBridgeCaution(
            clusterCount: 1,
            liveForecast: null,
            departure: departure,
            window: window,
            now: DateTime(2026, month, 15),
          ),
          isFalse,
          reason: 'month $month is outside the band',
        );
      }
    });
  });

  group('bundled asset (the REAL assets/bridges_akita.csv.gz)', () {
    test('loads via rootBundle, gunzips, and parses cleanly', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final csv = await loadBridgeCsvAsset();
      final parsed = parseBridgeCsv(csv);
      // 6,813 on-deck sample rows from 5,931 drivable-class bridge ways —
      // the generator's verified count (see
      // assets/bridges_akita.ATTRIBUTION.md; retrieval 2026-07-05,
      // curvature-aware regeneration same day). Update alongside any asset
      // regeneration.
      expect(parsed.sites.length, 6813);
      expect(parsed.skippedRowCount, 0);
      // Spot-check the first row matches the generated data shape.
      expect(parsed.sites.first.wayId, 38872082);
      expect(parsed.sites.first.bearingDeg, inInclusiveRange(0, 179));
      // The honest blank-bearing class (closed/curved ways) must be present
      // and parse as null — the matcher keeps these, fail toward warning.
      expect(parsed.sites.where((s) => s.bearingDeg == null).length, 1061);
    });
  });
}
