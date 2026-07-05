/// Pre-trip ROUTE-BRIDGE caution provider: approximately how many mapped
/// bridge sites lie on HER route — because bridge decks freeze before the
/// road surface does, and knowing "about N bridges ahead" at the kitchen
/// table lets her slow down BEFORE the deck, not after the slide.
///
/// OPT-IN + ONE-SHOT PER DESTINATION EPOCH: the route polyline is fetched
/// once per destination epoch — at pre-trip initialization, and again exactly
/// once when the driver sets a NEW destination in-app — via the existing
/// `routing_engine` OSRM engine (consume-only; that package is
/// maintenance-mode), and only when the edge developer opted in via
/// `--dart-define=PRETRIP_ROUTE_OSRM_URL=<url>` AND the driver has set a
/// destination. No retries beyond the engine's own single timeout, no
/// polling, no re-fetch on rebuild — same discipline as the destination-area
/// read (`pretrip_screen.dart`: one-shot per HER action, no
/// Timer/Stream/poll).
///
/// HONEST DEGRADATION (binding, per the corridor module's contract): ANY
/// failure — no URL, no destination, network error, empty route shape,
/// missing/corrupt asset, or a route that LEAVES the dataset's own coverage
/// extent — means the feature is ABSENT: no bridge section, no error banner,
/// no substitute claim. Failures are logged via [debugPrint] only. The count
/// is APPROXIMATE BY CONSTRUCTION (30 m corridor on OSM data; see
/// `bridge_corridor_read.dart`); zero clusters means "nothing to say",
/// NEVER "no bridges exist".
///
/// Network/asset IO is injected as closures so this file is unit-testable
/// without a socket (the `pretrip_live_forecast.dart` idiom).
library;

import 'dart:convert' show utf8;
import 'dart:io' show gzip;
import 'dart:math' as math;
import 'dart:typed_data' show Uint8List;

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:latlong2/latlong.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:routing_engine/routing_engine.dart';

import '../services/bridge_corridor_read.dart';

/// The one-shot route-polyline fetch. May throw ([RoutingException] from the
/// engine, or anything else); the resolver treats every throw as "no route".
typedef RouteShapeFetch = Future<List<LatLng>> Function();

/// The bridge-dataset load, returning the DECODED CSV text. May throw; the
/// resolver treats every throw as "no data".
typedef BridgeCsvLoad = Future<String> Function();

/// Bundled Akita bridge dataset (© OpenStreetMap contributors, ODbL — see
/// `assets/bridges_akita.ATTRIBUTION.md`). Registered in `pubspec.yaml`.
const String bridgeAssetPath = 'assets/bridges_akita.csv.gz';

/// Departure-window temperature ceiling for the bridge caution, °C — bound to
/// the advisor's OWN radiative-frost envelope ceiling (+3.0 °C): a bridge deck
/// freezes by the same clear-sky radiative physics, only earlier than the
/// road, so the caution shares the calibrated envelope rather than invent one.
const double bridgeCautionTempCeilingCelsius =
    SnowAwarePretripAdvisor.radiativeFrostAmbientCeilingCelsius;

/// The compound-failure month band (Oct–Apr): with NO cold temperature
/// evidence the caution falls back to the season in which a frozen deck is
/// plausible — and stays silent the rest of the year. October is IN: the
/// inland basins and passes HER route crosses (Yokote basin, 矢立峠/仙岩峠
/// elevations) see first frost mid-to-late October, and bridge decks are —
/// by this feature's own physics — the FIRST surfaces to ice each season,
/// before the road-frost climatology. The band's evidence-less arm is
/// exactly the arm that cannot correct itself with data, so it leans
/// fail-toward-warning; the cry-wolf cost is one shoulder month.
const Set<int> _bridgeCautionMonths = {10, 11, 12, 1, 2, 3, 4};

/// Outward margin, in degrees, around the dataset's own site extent when
/// deciding whether a route stays inside coverage (~3 km of latitude). An
/// in-region route just past the outermost mapped bridge must not lose its
/// section; a cross-region route overshoots this margin by tens of km.
const double _coverageMarginDeg = 0.03;

String? _bridgeCsvCache;

/// TOP-LEVEL [compute] entry: gunzip + UTF-8 decode of the bundled bridge
/// dataset. Runs OFF the UI isolate — inflating ~50 KB of gzip into ~220 KB
/// of text is real work that has no business on the frame thread.
String _gunzipBridgeCsv(Uint8List gzippedBytes) =>
    utf8.decode(gzip.decode(gzippedBytes));

/// Loads + gunzips + decodes the bundled bridge CSV. Lazy, and cached after
/// the first SUCCESSFUL load (the decoded text is ~220 KB; a failed load is
/// not cached, so a later pre-trip init may still succeed). The asset bytes
/// are read on the UI isolate (rootBundle needs the binding); the gunzip +
/// decode runs off it via [compute] (plain bytes in, plain text out).
///
/// GZIP CHOICE (honest): the repo has no `GZipCodec` precedent and
/// `package:archive` is not a dependency (pubspec.lock, read 2026-07-05: zero
/// hits), so this uses `dart:io`'s [gzip] codec — matching the app layer's
/// existing `dart:io` usage (`main.dart`, `snow_scene.dart`,
/// `saved_place_store.dart`). This app targets desktop / Android / embedded
/// ARM, not web (where `dart:io` is absent).
Future<String> loadBridgeCsvAsset([String path = bridgeAssetPath]) async {
  final cached = _bridgeCsvCache;
  if (cached != null && path == bridgeAssetPath) return cached;
  final data = await rootBundle.load(path);
  final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  final text =
      await compute(_gunzipBridgeCsv, bytes, debugLabel: 'bridgeCsvGunzip');
  if (path == bridgeAssetPath) _bridgeCsvCache = text;
  return text;
}

/// Fetches the route polyline ONCE via the existing OSRM engine (consume-only
/// — `routing_engine` is maintenance-mode) and releases the engine's HTTP
/// client. Throws on any routing failure ([RoutingException]); the resolver
/// below owns the honest-absence handling.
Future<List<LatLng>> fetchOsrmRouteShape({
  required String baseUrl,
  required double originLat,
  required double originLon,
  required double destLat,
  required double destLon,
}) async {
  final engine = OsrmRoutingEngine(baseUrl: baseUrl);
  try {
    final result = await engine.calculateRoute(RouteRequest(
      origin: LatLng(originLat, originLon),
      destination: LatLng(destLat, destLon),
    ));
    return result.shape;
  } finally {
    await engine.dispose();
  }
}

/// Plain-data arguments for [_matchBridgeCorridorEntry]. [compute] crosses an
/// isolate boundary, so the route travels as a FLAT primitive list —
/// `[lat0, lon0, lat1, lon1, …]` — and the CSV as text; no latlong2 objects
/// on the seam.
class _BridgeCorridorComputeArgs {
  const _BridgeCorridorComputeArgs({
    required this.csvText,
    required this.routeFlat,
  });

  final String csvText;
  final List<double> routeFlat;
}

/// Plain-data outcome of [_matchBridgeCorridorEntry]. Carries exactly what
/// the resolver's honest-absence mapping + logging needs — the resolver (UI
/// isolate) owns the null-vs-result decision and the [debugPrint]s.
class _BridgeCorridorComputeOutcome {
  const _BridgeCorridorComputeOutcome({
    required this.siteCount,
    required this.skippedRowCount,
    required this.leftCoverage,
    required this.clusterCount,
    required this.keptSiteCount,
  });

  /// Parsed site count (0 ⇒ the dataset is empty — the no-data arm).
  final int siteCount;
  final int skippedRowCount;

  /// The route left the dataset's own coverage extent (the truncated-count
  /// arm; see the coverage-gate comment in [_matchBridgeCorridorEntry]).
  final bool leftCoverage;
  final int clusterCount;
  final int keptSiteCount;
}

/// TOP-LEVEL [compute] entry: CSV parse → coverage-extent check → corridor
/// match, byte-for-byte the resolver's former inline steps — moved OFF the
/// UI isolate because parsing ~6,800 rows and matching them against a route
/// polyline is real work at frame time.
_BridgeCorridorComputeOutcome _matchBridgeCorridorEntry(
    _BridgeCorridorComputeArgs args) {
  final parsed = parseBridgeCsv(args.csvText);
  if (parsed.sites.isEmpty) {
    return _BridgeCorridorComputeOutcome(
      siteCount: 0,
      skippedRowCount: parsed.skippedRowCount,
      leftCoverage: false,
      clusterCount: 0,
      keptSiteCount: 0,
    );
  }
  final shape = <LatLng>[
    for (var i = 0; i + 1 < args.routeFlat.length; i += 2)
      LatLng(args.routeFlat[i], args.routeFlat[i + 1]),
  ];
  // COVERAGE GATE (honest scope): the bundled dataset covers ONE region —
  // today Akita prefecture (Overpass query area JP-05; see
  // assets/bridges_akita.ATTRIBUTION.md). A route that leaves that coverage
  // would get a systematically TRUNCATED count ("about N" computed from
  // half-covered data is a wrong claim, not an approximate one — and the
  // uncounted half of a cross-prefecture route is the mountain-pass side,
  // where decks ice first), so the feature is ABSENT for such routes: no
  // section, never a truncated number. The extent is measured from the sites
  // themselves (data-driven: a regenerated asset carries its own coverage)
  // plus a small outward margin ([_coverageMarginDeg]). A border sliver of a
  // NEIGHBOUR region can still sit inside this box (a bbox overstates a
  // prefecture); the UI string scopes the claim to the region for that
  // residue.
  var minLat = double.infinity, maxLat = double.negativeInfinity;
  var minLon = double.infinity, maxLon = double.negativeInfinity;
  for (final site in parsed.sites) {
    minLat = math.min(minLat, site.lat);
    maxLat = math.max(maxLat, site.lat);
    minLon = math.min(minLon, site.lon);
    maxLon = math.max(maxLon, site.lon);
  }
  for (final p in shape) {
    if (p.latitude < minLat - _coverageMarginDeg ||
        p.latitude > maxLat + _coverageMarginDeg ||
        p.longitude < minLon - _coverageMarginDeg ||
        p.longitude > maxLon + _coverageMarginDeg) {
      return _BridgeCorridorComputeOutcome(
        siteCount: parsed.sites.length,
        skippedRowCount: parsed.skippedRowCount,
        leftCoverage: true,
        clusterCount: 0,
        keptSiteCount: 0,
      );
    }
  }
  final result = countBridgeSitesOnRoute(
    parsed.sites,
    shape,
    skippedRowCount: parsed.skippedRowCount,
  );
  return _BridgeCorridorComputeOutcome(
    siteCount: parsed.sites.length,
    skippedRowCount: result.skippedRowCount,
    leftCoverage: false,
    clusterCount: result.clusterCount,
    keptSiteCount: result.keptSiteCount,
  );
}

/// Resolves the once-per-destination-epoch bridge corridor match: route shape
/// → bundled sites → clustered on-route count. Never throws. Null ⇒ the
/// feature is ABSENT (no route, no usable geometry, no data, or a route that
/// leaves the dataset's coverage extent) and the briefing shows NO bridge
/// section — never a substitute claim. A non-null result with
/// `clusterCount == 0` is equally "nothing to say" (the UI gate hides it);
/// it is NEVER an all-clear.
///
/// The CSV parse + coverage gate + corridor match run OFF the UI isolate via
/// [compute] ([_matchBridgeCorridorEntry]); the decisions and log lines are
/// unchanged.
Future<BridgeCorridorResult?> resolvePretripRouteBridges({
  required RouteShapeFetch fetchRouteShape,
  required BridgeCsvLoad loadBridgeCsv,
}) async {
  List<LatLng> shape;
  try {
    shape = await fetchRouteShape();
  } catch (e) {
    debugPrint('pretrip route bridges: route fetch failed ($e) — '
        'no bridge section');
    return null;
  }
  if (shape.length < 2) {
    debugPrint('pretrip route bridges: no usable route geometry — '
        'no bridge section');
    return null;
  }
  String csvText;
  try {
    csvText = await loadBridgeCsv();
  } catch (e) {
    debugPrint('pretrip route bridges: bridge data unavailable ($e) — '
        'no bridge section');
    return null;
  }
  _BridgeCorridorComputeOutcome outcome;
  try {
    outcome = await compute(
      _matchBridgeCorridorEntry,
      _BridgeCorridorComputeArgs(
        csvText: csvText,
        routeFlat: [
          for (final p in shape) ...[p.latitude, p.longitude],
        ],
      ),
      debugLabel: 'bridgeCorridorMatch',
    );
  } catch (e) {
    // An isolate failure is a data-pipeline failure like any other: honest
    // absence, never a partial claim.
    debugPrint('pretrip route bridges: corridor match failed ($e) — '
        'no bridge section');
    return null;
  }
  if (outcome.siteCount == 0) {
    debugPrint('pretrip route bridges: bridge data empty — no bridge section');
    return null;
  }
  if (outcome.skippedRowCount > 0) {
    // Honest data-quality signal: the dataset shrank at parse time. The
    // remaining sites are still real; the count stays approximate either way.
    debugPrint('pretrip route bridges: skipped ${outcome.skippedRowCount} '
        'malformed data row(s)');
  }
  if (outcome.leftCoverage) {
    debugPrint('pretrip route bridges: route leaves the bridge data\'s '
        'coverage extent — no bridge section (a truncated count would be '
        'a false claim)');
    return null;
  }
  return BridgeCorridorResult(
    clusterCount: outcome.clusterCount,
    keptSiteCount: outcome.keptSiteCount,
    skippedRowCount: outcome.skippedRowCount,
  );
}

/// Whether the bridge caution line is shown for a resolved [clusterCount].
///
/// Cold gate, so the line appears when a frozen deck is PLAUSIBLE and stays
/// quiet otherwise (a caution that fires in August cries wolf by December):
///   * COLD evidence ARMS the caution: the minimum temperature over the
///     departure window's slots (same slot-coverage rule as the advisor) —
///     taken across the ORIGIN's live forecast AND, when available, the
///     DESTINATION-area forecast the same briefing already fetched — at or
///     below [bridgeCautionTempCeilingCelsius] shows the line, in any month.
///   * WARM evidence may NOT suppress the season band: the bridges sit along
///     the whole route, hours and possibly 100+ km from either forecast
///     POINT (elevation lapse alone puts a pass deck 3–4 °C below a coastal
///     origin), so a warm 30-minute point reading is not evidence about the
///     corridor — it falls through to the month band exactly like NO
///     evidence. Nothing here ever REMOVES a caution the band would show.
///   * With no covering slot at all, [now]'s month decides (the
///     compound-failure band). The demo forecast is NEVER consulted —
///     computing a freezing gate for a REAL route from simulated
///     temperatures would be a fabricated claim.
///
/// `clusterCount < 1` is always hidden: zero means "nothing to say", and this
/// gate must never convert it into an implied all-clear.
bool shouldShowBridgeCaution({
  required int clusterCount,
  required WeatherForecast? liveForecast,
  WeatherForecast? destForecast,
  required DateTime departure,
  required Duration window,
  required DateTime now,
}) {
  if (clusterCount < 1) return false;
  final end = departure.add(window);
  double? minTemp;
  for (final forecast in [liveForecast, destForecast]) {
    if (forecast == null) continue;
    for (final slot in forecast.hourly) {
      // Slot [H, H+1h) overlaps the departure window — the advisor's own
      // coverage rule (snow_aware_pretrip_advisor.dart `_slotsCovering`).
      final covers = slot.hour.isBefore(end) &&
          slot.hour.add(const Duration(hours: 1)).isAfter(departure);
      if (!covers) continue;
      if (minTemp == null || slot.tempCelsius < minTemp) {
        minTemp = slot.tempCelsius;
      }
    }
  }
  // Cold at EITHER endpoint: evidence beats season (even in a warm month).
  if (minTemp != null && minTemp <= bridgeCautionTempCeilingCelsius) {
    return true;
  }
  // Warm point evidence or no evidence: the season band decides (winter
  // keeps the caution, summer stays quiet). Caution-add-only by design.
  return _bridgeCautionMonths.contains(now.month);
}
