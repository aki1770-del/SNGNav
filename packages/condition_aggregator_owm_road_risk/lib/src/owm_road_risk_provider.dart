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
  ///
  /// Discards the completeness signal; see [fetchPointRead] to learn whether
  /// part of the publisher's answer could not be read.
  Future<List<OwmRoadRiskAlert>> fetchPoint({
    required double latitude,
    required double longitude,
    DateTime? at,
  }) async {
    final read = await fetchPointRead(
      latitude: latitude,
      longitude: longitude,
      at: at,
    );
    return read.alerts;
  }

  /// Fetches alerts for a single point, keeping what could not be read.
  Future<OwmRoadRiskRead> fetchPointRead({
    required double latitude,
    required double longitude,
    DateTime? at,
  }) async {
    final ts = (at ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
    return fetchTrackRead([
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
  ///
  /// Discards the completeness signal; see [fetchTrackRead], which returns the
  /// same alerts together with a count of the entries that could not be read.
  /// A caller that only uses this method cannot distinguish "the publisher
  /// reported nothing" from "the publisher reported something unreadable",
  /// except that the wholly-unreadable case throws rather than returning an
  /// empty list.
  Future<List<OwmRoadRiskAlert>> fetchTrack(
    List<OwmRoadRiskWaypoint> track,
  ) async {
    final read = await fetchTrackRead(track);
    return read.alerts;
  }

  /// Fetches alerts along a multi-waypoint track, keeping what could not be
  /// read alongside what could.
  ///
  /// Throws [OwmRoadRiskParseException] when the response carried entries and
  /// none of them could be read. Returning an empty list there would assert
  /// that the publisher reported no road risk, which is a measurement this
  /// adapter did not take.
  Future<OwmRoadRiskRead> fetchTrackRead(
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

    // Every `continue` below used to discard an entry silently, so a response
    // whose only content was unreadable came back as an empty list — which the
    // AdvisoryProvider contract defines as "nothing is active at this point".
    // The discards are now counted and carried.
    final alerts = <OwmRoadRiskAlert>[];
    final causes = <String>[];
    for (final item in decoded) {
      if (item is! Map<String, dynamic>) {
        causes.add('track entry was ${_shapeOf(item)}, expected an object');
        continue;
      }
      final perWaypointAlerts = item['alerts'];
      // A track entry with no `alerts` key at all is a well-formed "nothing
      // active here" answer, not an unreadable entry.
      if (perWaypointAlerts == null) continue;
      if (perWaypointAlerts is! List) {
        causes.add(
          "'alerts' was ${_shapeOf(perWaypointAlerts)}, expected an array",
        );
        continue;
      }
      for (final raw in perWaypointAlerts) {
        if (raw is! Map<String, dynamic>) {
          causes.add('alert entry was ${_shapeOf(raw)}, expected an object');
          continue;
        }
        try {
          alerts.add(OwmRoadRiskAlert.fromJson(raw));
        } on Object catch (e) {
          // An alert object this adapter cannot turn into a record is an
          // unread entry, not an absent hazard. Field-level absence is handled
          // inside fromJson and does not reach here.
          causes.add('alert entry could not be parsed: $e');
        }
      }
    }

    if (alerts.isEmpty && causes.isNotEmpty) {
      // Nothing readable, and something was there. An empty list here would be
      // a false all-clear.
      throw OwmRoadRiskParseException(
        'the publisher returned ${causes.length} '
        '${causes.length == 1 ? 'entry' : 'entries'} and none could be read, '
        'so no conclusion about road risk at this point is available. '
        'Causes: ${causes.join('; ')}.',
      );
    }

    return OwmRoadRiskRead(
      alerts: alerts,
      unreadableEntries: causes.length,
      unreadableCauses: List.unmodifiable(causes),
    );
  }

  /// Names the JSON shape of an unexpected value for the cause strings, without
  /// echoing publisher content into a message that may end up in a log.
  static String _shapeOf(Object? v) {
    if (v == null) return 'null';
    if (v is String) return 'a string';
    if (v is num) return 'a number';
    if (v is bool) return 'a boolean';
    if (v is List) return 'an array';
    if (v is Map) return 'an object';
    return v.runtimeType.toString();
  }

  /// Releases the HTTP client. Call from the consuming app's lifecycle
  /// teardown when the adapter is no longer needed.
  void close() => httpClient.close();
}

/// `AdvisoryProvider` implementation backed by [OwmRoadRiskClient].
///
/// Uses [AdvisorySource.other] because the umbrella enum
/// `condition_aggregator` has no dedicated OpenWeatherMap source value.
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

  /// Fetches active advisories at a point.
  ///
  /// Returns an empty list only when the publisher answered and reported
  /// nothing. When part of the answer could not be read, the readable
  /// advisories are returned together with a clearly-marked, low-severity
  /// incomplete-read notice
  /// (`Advisory.eventClass == kOwmRoadRiskIncompleteReadEventClass`) so the
  /// partial read is never presented as a complete one. When nothing in a
  /// non-empty answer could be read, this throws rather than reporting an
  /// all-clear it did not measure.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    final read = await _client.fetchPointRead(
      latitude: latitude,
      longitude: longitude,
    );
    final advisories = OwmRoadRiskMapper.toAdvisoryList(
      alerts: read.alerts,
      latitude: latitude,
      longitude: longitude,
    );
    if (!read.isComplete) {
      advisories.add(
        OwmRoadRiskMapper.buildIncompleteReadNotice(
          read: read,
          latitude: latitude,
          longitude: longitude,
        ),
      );
    }
    return advisories;
  }

  /// Releases the underlying HTTP client.
  void close() => _client.close();
}
