/// HTTP client + AdvisoryProvider implementation for OpenWeatherMap
/// Road Risk.
///
/// Endpoint: `POST https://api.openweathermap.org/data/2.5/roadrisk`
/// (per https://openweathermap.org/api/road-risk).
///
/// Auth: `?appid=<API_KEY>` query parameter. The user supplies the
/// API key at construction time; this package does NOT bundle a
/// publisher API key — operators register at openweathermap.org and
/// pass their own key.
///
/// Body shape: `{"track": [{"lat": ..., "lon": ..., "dt": <unix>}, ...]}`.
/// The `AdvisoryProvider.fetchActiveAdvisoriesAtPoint` interface is
/// point-based, so a single-waypoint track is constructed per call;
/// [OwmRoadRiskClient.fetchTrack] is the lower-level multi-waypoint
/// API for forward-route queries.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:http/http.dart' as http;

import 'owm_road_risk_mapper.dart';
import 'owm_road_risk_models.dart';

/// Default base URL for the publisher.
const String kOwmRoadRiskDefaultBaseUrl = 'https://api.openweathermap.org';

/// Path component of the road-risk endpoint at the default base.
const String kOwmRoadRiskPath = '/data/2.5/roadrisk';

/// Lower-level HTTP client around the publisher's road-risk endpoint.
/// Returns the raw alert list from the response; consumers needing
/// the source-neutral [Advisory] view use [OwmRoadRiskProvider]
/// instead.
class OwmRoadRiskClient {
  /// Publisher API key. Required; this package does not bundle one.
  final String apiKey;

  /// Base URL for the publisher. Defaults to
  /// [kOwmRoadRiskDefaultBaseUrl]; tests inject a local mock URL.
  final String baseUrl;

  /// HTTP client. Tests inject `MockClient` from
  /// `package:http/testing.dart`.
  final http.Client httpClient;

  OwmRoadRiskClient({
    required this.apiKey,
    this.baseUrl = kOwmRoadRiskDefaultBaseUrl,
    http.Client? httpClient,
  }) : httpClient = httpClient ?? http.Client(),
       assert(apiKey != '', 'OWM Road Risk: apiKey must be non-empty.');

  /// Fetches alerts for a single point.
  Future<List<OwmRoadRiskAlert>> fetchPoint({
    required double latitude,
    required double longitude,
    DateTime? at,
  }) async {
    final ts = (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
    return fetchTrack([
      OwmRoadRiskWaypoint(
        latitude: latitude,
        longitude: longitude,
        unixTime: ts,
      ),
    ]);
  }

  /// Fetches alerts along a multi-waypoint track. Returns a flat list
  /// of alerts (the publisher's response can attach alerts at the
  /// track level rather than per-waypoint, depending on issuer).
  Future<List<OwmRoadRiskAlert>> fetchTrack(
    List<OwmRoadRiskWaypoint> track,
  ) async {
    if (track.isEmpty) {
      throw ArgumentError.value(
        track,
        'track',
        'OWM Road Risk: track must contain at least one waypoint.',
      );
    }

    final uri = Uri.parse('$baseUrl$kOwmRoadRiskPath?appid=$apiKey');
    final body = jsonEncode(<String, dynamic>{
      'track': [for (final w in track) w.toJson()],
    });

    http.Response response;
    try {
      response = await httpClient.post(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
    } on SocketException catch (e) {
      throw OwmRoadRiskHttpException(
        statusCode: 0,
        responseBody: 'SocketException: ${e.message}',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final truncated = response.body.length > 500
          ? '${response.body.substring(0, 500)}...'
          : response.body;
      throw OwmRoadRiskHttpException(
        statusCode: response.statusCode,
        responseBody: truncated,
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (e) {
      throw OwmRoadRiskParseException(
        'response body is not JSON: ${e.message}',
      );
    }

    if (decoded is! List) {
      throw const OwmRoadRiskParseException(
        'expected top-level JSON array; publisher returns one item per '
        'track waypoint.',
      );
    }

    final alerts = <OwmRoadRiskAlert>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) continue;
      final perWaypointAlerts = item['alerts'];
      if (perWaypointAlerts is! List) continue;
      for (final raw in perWaypointAlerts) {
        if (raw is Map<String, dynamic>) {
          alerts.add(OwmRoadRiskAlert.fromJson(raw));
        }
      }
    }
    return alerts;
  }

  /// Releases the HTTP client. Call from the consuming app's lifecycle
  /// teardown when the adapter is no longer needed.
  void close() => httpClient.close();
}

/// `AdvisoryProvider` implementation backed by [OwmRoadRiskClient].
///
/// Uses [AdvisorySource.other] in 0.1.0 because the umbrella enum
/// `condition_aggregator` 0.0.3 does not yet name OpenWeatherMap as a
/// dedicated source; a forward-additive enum bump in
/// `condition_aggregator` 0.0.4+ will introduce a dedicated value and
/// this provider will graduate to it without consumer-side breakage.
class OwmRoadRiskProvider implements AdvisoryProvider {
  final OwmRoadRiskClient _client;

  /// Constructs the provider directly. Tests typically inject a
  /// pre-built [OwmRoadRiskClient] with a `MockClient` HTTP backend.
  OwmRoadRiskProvider({required OwmRoadRiskClient client}) : _client = client;

  /// Convenience constructor: builds an internal [OwmRoadRiskClient]
  /// from `apiKey` + optional `baseUrl` + optional `httpClient`.
  factory OwmRoadRiskProvider.withApiKey({
    required String apiKey,
    String baseUrl = kOwmRoadRiskDefaultBaseUrl,
    http.Client? httpClient,
  }) {
    return OwmRoadRiskProvider(
      client: OwmRoadRiskClient(
        apiKey: apiKey,
        baseUrl: baseUrl,
        httpClient: httpClient,
      ),
    );
  }

  @override
  AdvisorySource get source => AdvisorySource.other;

  @override
  Future<void> init() async {
    // No init action required; the publisher accepts requests
    // immediately given a valid `appid`.
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    final alerts = await _client.fetchPoint(
      latitude: latitude,
      longitude: longitude,
    );
    return OwmRoadRiskMapper.toAdvisoryList(
      alerts: alerts,
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();
}
