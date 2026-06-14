/// DigitrafficVisibilityProvider — real measured road-network visibility for
/// the pre-trip "Before you drive" briefing (Finland).
///
/// The 2026-06-12 quantitative analysis confirmed a hard ceiling on the live
/// forecast wiring: 0/620 real winter forecast slots can ever reach the
/// severe hazard band, because the MET Norway compact product carries no
/// visibility and we refuse to estimate it from sky symbols. This provider
/// closes that ceiling with REAL sensors where they exist: Fintraffic's
/// Digitraffic road-weather network — measured 2026-06-12, 453 of 526
/// stations (86%) report a visibility sensor live.
///
/// Flow (one-shot, ~22 KB total):
/// 1. GET `/api/weather/v1/stations` (GeoJSON metadata, ~20 KB gzip) →
///    nearest GATHERING station to the requested point within
///    [maxDistanceKm].
/// 2. GET `/api/weather/v1/stations/{id}/data` (~2 KB) → the `NÄKYVYYS_M`
///    sensor (or `NÄKYVYYS_KM` × 1000), accepted only when `measuredTime`
///    is within [maxObservationAge].
///
/// Honesty rules, binding:
/// - An observation is a NOW measurement at a station up to [maxDistanceKm]
///   away — the caller applies it to the current hour only, never projects
///   it forward into forecast hours, and surfaces the station distance.
/// - No station in range / no fresh visibility sensor / any fetch failure →
///   `null`. Visibility is never estimated.
/// - Requests carry an identifying User-Agent; data © Fintraffic
///   (digitraffic.fi), CC BY 4.0 — the caller surfaces the attribution.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'visibility_observation.dart';

// The measured-visibility observation type and its departure-hour merge are
// source-neutral (shared with the JMA AMeDAS provider); re-exported so existing
// importers of this file keep resolving `VisibilityObservation` and
// `mergeObservedVisibility` unchanged.
export 'visibility_observation.dart';

/// Default Digitraffic road-weather API base.
const String kDigitrafficWeatherApiBase =
    'https://tie.digitraffic.fi/api/weather/v1';

/// Wall-clock budget per HTTP fetch.
const Duration _kFetchBudget = Duration(seconds: 30);

/// Hard cap on a response body. Metadata observed at ~21 KB download /
/// ~600 KB decoded JSON (526 stations, 2026-06-12); 8 MB bounds memory
/// while leaving headroom.
const int _kMaxResponseBytes = 8 * 1024 * 1024;

/// Fetches the nearest fresh measured visibility on the Finnish road network.
class DigitrafficVisibilityProvider {
  /// Constructs a provider that owns its own [http.Client].
  DigitrafficVisibilityProvider({
    this.apiBase = kDigitrafficWeatherApiBase,
    this.userAgent = 'sngnav_snow_scene github.com/aki1770-del/SNGNav',
    this.maxDistanceKm = 30,
    this.maxObservationAge = const Duration(minutes: 30),
  })  : _client = http.Client(),
        _ownsClient = true;

  /// Constructs a provider against a caller-supplied client (test injection).
  DigitrafficVisibilityProvider.withClient(
    http.Client client, {
    this.apiBase = kDigitrafficWeatherApiBase,
    this.userAgent = 'sngnav_snow_scene github.com/aki1770-del/SNGNav',
    this.maxDistanceKm = 30,
    this.maxObservationAge = const Duration(minutes: 30),
  })  : _client = client,
        _ownsClient = false;

  /// API base URL (no trailing slash).
  final String apiBase;

  /// Identifying User-Agent (Digitraffic asks integrations to identify).
  final String userAgent;

  /// A station farther than this from the requested point is not "near the
  /// route" — its visibility says little about hers. 30 km default.
  final double maxDistanceKm;

  /// An observation older than this is discarded, not served as current.
  final Duration maxObservationAge;

  final http.Client _client;
  final bool _ownsClient;

  /// Returns the nearest fresh visibility observation, or `null` when no
  /// station within [maxDistanceKm] has a visibility value newer than
  /// [maxObservationAge] (evaluated against [now], injectable for tests).
  /// Throws [DigitrafficVisibilityException] on HTTP/parse failure.
  Future<VisibilityObservation?> fetchNearestVisibility({
    required double latitude,
    required double longitude,
    DateTime? now,
  }) async {
    final stations = await _fetchJson('$apiBase/stations');
    final nearest = _nearestStations(stations, latitude, longitude);
    if (nearest.isEmpty) return null;

    final clock = now ?? DateTime.now();
    // Try the closest few stations: the very nearest may be GATHERING but
    // missing a visibility sensor (measured 2026-06-12: 14% are).
    for (final (id, name, distKm) in nearest.take(3)) {
      final data = await _fetchJson('$apiBase/stations/$id/data');
      final obs = _extractVisibility(data, clock);
      if (obs == null) continue;
      final (meters, measuredAt) = obs;
      return VisibilityObservation(
        meters: meters,
        stationId: id,
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

  Future<Map<String, dynamic>> _fetchJson(String url) async {
    final response = await _client.get(Uri.parse(url), headers: {
      'User-Agent': userAgent,
      'Accept': 'application/json',
      // Digitraffic returns 406 without an explicit gzip accept-encoding.
      'Accept-Encoding': 'gzip',
    }).timeout(
      _kFetchBudget,
      onTimeout: () => throw DigitrafficVisibilityException(
        'Wall-clock budget ${_kFetchBudget.inSeconds}s exhausted: $url',
      ),
    );
    if (response.statusCode != 200) {
      throw DigitrafficVisibilityException(
        'Digitraffic fetch failed: HTTP ${response.statusCode} for $url',
      );
    }
    if (response.bodyBytes.length > _kMaxResponseBytes) {
      throw DigitrafficVisibilityException(
        'Digitraffic response exceeded $_kMaxResponseBytes-byte cap '
        '(${response.bodyBytes.length} bytes) for $url',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw DigitrafficVisibilityException(
        'Digitraffic response is not valid JSON (${e.message}) for $url',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const DigitrafficVisibilityException(
        'Digitraffic response is not a JSON object.',
      );
    }
    return decoded;
  }

  /// GATHERING stations within [maxDistanceKm], nearest first, as
  /// (id, name, distanceKm).
  List<(int, String, double)> _nearestStations(
    Map<String, dynamic> metadata,
    double lat,
    double lon,
  ) {
    final features = metadata['features'];
    if (features is! List) return const [];
    final hits = <(int, String, double)>[];
    for (final f in features) {
      if (f is! Map<String, dynamic>) continue;
      final id = f['id'];
      if (id is! int) continue;
      final props = f['properties'];
      if (props is! Map<String, dynamic>) continue;
      if (props['collectionStatus'] != 'GATHERING') continue;
      final geometry = f['geometry'];
      if (geometry is! Map<String, dynamic>) continue;
      final coords = geometry['coordinates'];
      if (coords is! List || coords.length < 2) continue;
      final sLon = _readNum(coords[0]);
      final sLat = _readNum(coords[1]);
      if (sLon == null || sLat == null) continue;
      final d = _haversineKm(lat, lon, sLat, sLon);
      if (d > maxDistanceKm) continue;
      final name = props['name'];
      hits.add((id, name is String ? name : '$id', d));
    }
    hits.sort((a, b) => a.$3.compareTo(b.$3));
    return hits;
  }

  /// (meters, measuredAt) from a station-data payload, or null when no
  /// fresh visibility sensor is present. Prefers NÄKYVYYS_M; falls back to
  /// NÄKYVYYS_KM × 1000.
  (double, DateTime)? _extractVisibility(
    Map<String, dynamic> data,
    DateTime now,
  ) {
    final values = data['sensorValues'];
    if (values is! List) return null;
    (double, DateTime)? meters;
    (double, DateTime)? km;
    for (final v in values) {
      if (v is! Map<String, dynamic>) continue;
      final name = v['name'];
      final value = _readNum(v['value']);
      final measuredAt = _parseIsoOrNull(v['measuredTime']);
      if (name is! String || value == null || measuredAt == null) continue;
      if (now.difference(measuredAt) > maxObservationAge) continue;
      if (name == 'NÄKYVYYS_M') meters = (value, measuredAt);
      if (name == 'NÄKYVYYS_KM') km = (value * 1000, measuredAt);
    }
    return meters ?? km;
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

/// Raised on HTTP or parse failure of a Digitraffic fetch.
class DigitrafficVisibilityException implements Exception {
  const DigitrafficVisibilityException(this.message);

  /// Human-readable description of the failure.
  final String message;

  @override
  String toString() => 'DigitrafficVisibilityException: $message';
}
