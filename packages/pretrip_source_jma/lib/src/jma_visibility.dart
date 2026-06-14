/// JmaVisibilityProvider — real measured surface visibility for the pre-trip
/// "Before you drive" briefing in Japan, from the Japan Meteorological Agency's
/// AMeDAS network.
///
/// Genchi-genbutsu (2026-06-14, live probe): the Japan pre-trip path closes a
/// real gap. The MET Norway compact base carries NO visibility, and the JMA
/// winter-WARNING merge (`jma_briefing_merge.dart`) deliberately never writes a
/// visibility number — a warning is not a measurement. So the Japanese
/// driver's briefing could reach the snow/ice ROAD bands but never the
/// measured-visibility WHITEOUT band. AMeDAS closes that, exactly as
/// Digitraffic does for Finland: of 1286 AMeDAS stations, 151 publish a live
/// `visibility` sensor (metres) — including 秋田/Akita (station 32402 @
/// 39.72,140.10, HER mother's anchor) and 17 across Tōhoku/Hokkaidō.
///
/// Flow (one-shot, ~0.44 MB total):
/// 1. GET `/bosai/amedas/data/latest_time.txt` → the snapshot timestamp.
/// 2. GET `/bosai/amedas/const/amedastable.json` (~188 KB) → station metadata
///    (lat/lon in degrees+minutes) → nearest stations within [maxDistanceKm].
/// 3. GET `/bosai/amedas/data/map/<TS>.json` (~250 KB) → the nearest station's
///    `visibility` value, accepted only when its QC flag is 0 (normal) and the
///    snapshot is newer than [maxObservationAge].
///
/// Honesty rules, binding (mirroring the Digitraffic visibility provider):
/// - An observation is a NOW measurement at a station up to [maxDistanceKm]
///   away — the caller applies it to the current hour only, never projects it
///   forward into forecast hours, and surfaces the station distance.
/// - Only a QC-flag-0 (normal) reading is accepted; any other flag, no station
///   in range, no fresh visibility, or any fetch failure → `null`. Visibility
///   is never estimated and a warning never produces one.
/// - The data is JMA open data, freely usable; the caller surfaces the
///   attribution (気象庁 / Japan Meteorological Agency).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

// The measured-visibility observation type and its departure-hour merge are
// source-neutral and owned by the published `pretrip_decision_advisor`
// contract package; re-exported so importers of this file resolve
// `VisibilityObservation` and `mergeObservedVisibility` directly, mirroring
// the app's `digitraffic_visibility.dart` / `jma_visibility.dart` providers.
export 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart'
    show VisibilityObservation, mergeObservedVisibility;

/// Default JMA bosai open-data base (same family the JMA advisory adapter uses).
const String kJmaBosaiApiBase = 'https://www.jma.go.jp/bosai';

/// Wall-clock budget per HTTP fetch.
const Duration _kFetchBudget = Duration(seconds: 30);

/// Hard cap on a response body. The station table is ~188 KB and the map
/// snapshot ~250 KB; 16 MB bounds memory with generous headroom.
const int _kMaxResponseBytes = 16 * 1024 * 1024;

/// Fetches the nearest fresh measured visibility on the JMA AMeDAS network.
class JmaVisibilityProvider {
  /// Constructs a provider that owns its own [http.Client].
  JmaVisibilityProvider({
    this.apiBase = kJmaBosaiApiBase,
    this.userAgent = 'sngnav_snow_scene github.com/aki1770-del/SNGNav',
    this.maxDistanceKm = 50,
    this.maxObservationAge = const Duration(minutes: 30),
  })  : _client = http.Client(),
        _ownsClient = true;

  /// Constructs a provider against a caller-supplied client (test injection).
  JmaVisibilityProvider.withClient(
    http.Client client, {
    this.apiBase = kJmaBosaiApiBase,
    this.userAgent = 'sngnav_snow_scene github.com/aki1770-del/SNGNav',
    this.maxDistanceKm = 50,
    this.maxObservationAge = const Duration(minutes: 30),
  })  : _client = client,
        _ownsClient = false;

  /// API base URL (no trailing slash).
  final String apiBase;

  /// Identifying User-Agent.
  final String userAgent;

  /// AMeDAS visibility stations are sparse (151 nationwide, ~50 km mean
  /// spacing); a station farther than this from the requested point says too
  /// little about her road to serve. 50 km default.
  final double maxDistanceKm;

  /// An observation older than this is discarded, not served as current.
  final Duration maxObservationAge;

  final http.Client _client;
  final bool _ownsClient;

  /// Returns the nearest fresh visibility observation, or `null` when no
  /// station within [maxDistanceKm] has a QC-flag-0 visibility value in a
  /// snapshot newer than [maxObservationAge] (evaluated against [now],
  /// injectable for tests). Throws [JmaVisibilityException] on HTTP/parse
  /// failure.
  Future<VisibilityObservation?> fetchNearestVisibility({
    required double latitude,
    required double longitude,
    DateTime? now,
  }) async {
    final timestamp = await _fetchText('$apiBase/amedas/data/latest_time.txt');
    final measuredAt = _parseIsoOrNull(timestamp.trim());
    if (measuredAt == null) return null;
    final clock = now ?? DateTime.now();
    if (clock.difference(measuredAt) > maxObservationAge) return null;

    final mapName = _mapFileName(timestamp.trim());
    if (mapName == null) return null;

    final table = await _fetchJson('$apiBase/amedas/const/amedastable.json');
    final nearest = _nearestStations(table, latitude, longitude);
    if (nearest.isEmpty) return null;

    final map = await _fetchJson('$apiBase/amedas/data/map/$mapName.json');

    // Try the closest few stations: the nearest may not carry a visibility
    // sensor (only 151 of 1286 stations do).
    for (final (code, name, distKm) in nearest.take(5)) {
      final meters = _visibilityFor(map[code]);
      if (meters == null) continue;
      return VisibilityObservation(
        meters: meters,
        stationId: int.parse(code),
        stationName: name,
        measuredAt: measuredAt,
        distanceKm: distKm,
      );
    }
    return null;
  }

  /// Releases the underlying client if this provider constructed it.
  void close() {
    if (_ownsClient) _client.close();
  }

  /// `YYYYMMDDHHMMSS` map-file stem from a JMA latest_time string (e.g.
  /// `2026-06-14T18:30:00+09:00` → `20260614183000`), or null if malformed.
  String? _mapFileName(String isoTimestamp) {
    final beforeTz = isoTimestamp.split(RegExp(r'[+Z]')).first;
    final digits = beforeTz.replaceAll(RegExp(r'\D'), '');
    return digits.length == 14 ? digits : null;
  }

  /// The QC-flag-0 visibility value (metres) for a station's map entry, or null
  /// when the entry has no visibility sensor or its QC flag is not 0 (normal).
  double? _visibilityFor(Object? stationEntry) {
    if (stationEntry is! Map<String, dynamic>) return null;
    final vis = stationEntry['visibility'];
    if (vis is! List || vis.length < 2) return null;
    final meters = _readNum(vis[0]);
    final flag = _readNum(vis[1]);
    if (meters == null || flag != 0) return null; // only normal readings
    return meters;
  }

  Future<String> _fetchText(String url) async {
    final response = await _get(url, accept: 'text/plain');
    return utf8.decode(response.bodyBytes);
  }

  Future<Map<String, dynamic>> _fetchJson(String url) async {
    final response = await _get(url, accept: 'application/json');
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw JmaVisibilityException(
        'JMA response is not valid JSON (${e.message}) for $url',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const JmaVisibilityException('JMA response is not a JSON object.');
    }
    return decoded;
  }

  Future<http.Response> _get(String url, {required String accept}) async {
    final response = await _client.get(Uri.parse(url), headers: {
      'User-Agent': userAgent,
      'Accept': accept,
      'Accept-Encoding': 'gzip',
    }).timeout(
      _kFetchBudget,
      onTimeout: () => throw JmaVisibilityException(
        'Wall-clock budget ${_kFetchBudget.inSeconds}s exhausted: $url',
      ),
    );
    if (response.statusCode != 200) {
      throw JmaVisibilityException(
        'JMA fetch failed: HTTP ${response.statusCode} for $url',
      );
    }
    if (response.bodyBytes.length > _kMaxResponseBytes) {
      throw JmaVisibilityException(
        'JMA response exceeded $_kMaxResponseBytes-byte cap '
        '(${response.bodyBytes.length} bytes) for $url',
      );
    }
    return response;
  }

  /// AMeDAS stations within [maxDistanceKm], nearest first, as
  /// (code, romanised-name, distanceKm).
  List<(String, String, double)> _nearestStations(
    Map<String, dynamic> table,
    double lat,
    double lon,
  ) {
    final hits = <(String, String, double)>[];
    for (final entry in table.entries) {
      final code = entry.key;
      final props = entry.value;
      if (props is! Map<String, dynamic>) continue;
      final sLat = _dms(props['lat']);
      final sLon = _dms(props['lon']);
      if (sLat == null || sLon == null) continue;
      final d = _haversineKm(lat, lon, sLat, sLon);
      if (d > maxDistanceKm) continue;
      final name = props['enName'];
      hits.add((code, name is String && name.isNotEmpty ? name : code, d));
    }
    hits.sort((a, b) => a.$3.compareTo(b.$3));
    return hits;
  }

  /// Decimal degrees from a JMA `[degrees, minutes]` pair, or null if malformed.
  double? _dms(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final deg = _readNum(raw[0]);
    final min = _readNum(raw[1]);
    if (deg == null || min == null) return null;
    return deg + min / 60.0;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLon / 2) * sin(dLon / 2);
    return 2 * r * atan2(sqrt(a), sqrt(1 - a));
  }

  double _rad(double deg) => deg * pi / 180;
}

double? _readNum(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

DateTime? _parseIsoOrNull(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toLocal();
  } on FormatException {
    return null;
  }
}

/// Raised on HTTP or parse failure of a JMA AMeDAS fetch.
class JmaVisibilityException implements Exception {
  const JmaVisibilityException(this.message);

  /// Human-readable description of the failure.
  final String message;

  @override
  String toString() => 'JmaVisibilityException: $message';
}
