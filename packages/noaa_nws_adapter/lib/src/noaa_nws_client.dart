/// HTTP client around the NOAA / NWS `/alerts/active` endpoint.
///
/// Smallest-slice: ONE endpoint
/// (`GET https://api.weather.gov/alerts/active?point={lat},{lon}`),
/// ONE alert class focus (the catalogued winter event types in
/// [kNwsWinterEventTypes]).
///
/// The publisher requires every request to carry a `User-Agent` header
/// of the form `(myappname.com, contact@email.com)`. The adapter does
/// NOT default a User-Agent; constructing the client without one is a
/// programmer error and surfaces an [ArgumentError] up-front rather
/// than letting the request 403/blocklist later.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'winter_alert.dart';

/// Default API base. Exposed for testing or for the rare case of
/// pointing at a staging NWS endpoint.
const String kDefaultNwsApiBase = 'https://api.weather.gov';

/// Default `Accept` value — GeoJSON. The endpoint also speaks
/// `application/cap+xml`, `application/ld+json`, `application/atom+xml`,
/// `application/vnd.noaa.dwml+xml`, and `application/vnd.noaa.obs+xml`,
/// but this smallest-slice client uses GeoJSON only.
const String kDefaultAcceptHeader = 'application/geo+json';

/// Thrown when an HTTP call to `api.weather.gov` returns a non-2xx
/// status code OR fails at the transport layer.
class NoaaNwsHttpException implements Exception {
  /// Human-readable description.
  final String message;

  /// Status code if the failure was an HTTP-class failure; null if
  /// transport-class.
  final int? statusCode;

  /// The URI that was being requested.
  final Uri? uri;

  const NoaaNwsHttpException(this.message, {this.statusCode, this.uri});

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (status $statusCode)';
    final u = uri == null ? '' : ' [$uri]';
    return 'NoaaNwsHttpException: $message$code$u';
  }
}

/// Thin, stateless client around the NWS `/alerts/active` endpoint.
///
/// Stateless = no polling, no stream, no cache. A consumer that wants
/// periodic refresh wraps this in their own [Timer.periodic] or
/// `Stream.periodic`. Keeping the client stateless preserves
/// composability with the eventual `condition_aggregator` interface
/// where multiple meteorological-feed adapters are scheduled together.
class NoaaNwsClient {
  /// HTTP client — injectable for testing.
  final http.Client _http;

  /// Mandatory User-Agent identifying the calling application. Format:
  /// `(myappname.com, contact@email.com)`. The publisher uses this
  /// only for rate-limit accounting and security contact; no API key.
  final String userAgent;

  /// Override of [kDefaultNwsApiBase]; useful for tests.
  final String apiBase;

  /// `Accept` header value. Defaults to GeoJSON.
  final String acceptHeader;

  /// Constructs a client. Throws [ArgumentError] if [userAgent] is
  /// empty, since the publisher will refuse anonymous requests.
  NoaaNwsClient({
    required this.userAgent,
    http.Client? client,
    this.apiBase = kDefaultNwsApiBase,
    this.acceptHeader = kDefaultAcceptHeader,
  }) : _http = client ?? http.Client() {
    if (userAgent.trim().isEmpty) {
      throw ArgumentError.value(
        userAgent,
        'userAgent',
        'NWS API requires a User-Agent of the form '
            '(myappname.com, contact@email.com); refusing to send '
            'anonymous request.',
      );
    }
  }

  /// Releases the underlying HTTP client. Call when finished.
  void close() => _http.close();

  /// Fetches active alerts for `(latitude, longitude)`, filtered to the
  /// 14 winter event types in [kNwsWinterEventTypes] and (by default)
  /// to `status: Actual` only.
  ///
  /// Returns an empty list when the point has no active winter alerts —
  /// this is the common case at most points most of the time.
  ///
  /// Throws [NoaaNwsHttpException] on 4xx/5xx or transport failure.
  /// Throws [NoaaNwsParseException] on GeoJSON shape mismatch.
  ///
  /// On 429, this client does NOT auto-retry; the caller decides
  /// whether to back off (the publisher recommends ~5 seconds).
  /// Keeping retry policy in the caller keeps this client honest about
  /// what it actually did.
  Future<List<WinterAlert>> fetchActiveWinterAlerts({
    required double latitude,
    required double longitude,
    bool actualOnly = true,
  }) async {
    final uri = Uri.parse(
      '$apiBase/alerts/active?point=$latitude,$longitude',
    );

    final http.Response response;
    try {
      response = await _http.get(uri, headers: <String, String>{
        'User-Agent': userAgent,
        'Accept': acceptHeader,
      });
    } catch (e) {
      throw NoaaNwsHttpException(
        'Transport failure contacting NWS: $e',
        uri: uri,
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw NoaaNwsHttpException(
        'NWS returned non-2xx',
        statusCode: response.statusCode,
        uri: uri,
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw NoaaNwsParseException('NWS response was not valid JSON: $e');
    }
    return parseFeatureCollection(decoded, actualOnly: actualOnly);
  }

  /// Parses one GeoJSON `FeatureCollection` payload into a winter-only
  /// alert list. Visible for testing — allows unit-testing the parser
  /// without HTTP.
  ///
  /// Filtering applied:
  /// 1. `event` must be in [kNwsWinterEventTypes].
  /// 2. If [actualOnly] is true (default), `status` must be `Actual`.
  static List<WinterAlert> parseFeatureCollection(
    Object? decoded, {
    bool actualOnly = true,
  }) {
    if (decoded is! Map<String, dynamic>) {
      throw const NoaaNwsParseException(
        'Top-level GeoJSON payload was not a JSON object.',
      );
    }
    final type = decoded['type'];
    if (type != 'FeatureCollection') {
      throw NoaaNwsParseException(
        "Top-level 'type' was '$type', expected 'FeatureCollection'.",
      );
    }
    final featuresRaw = decoded['features'];
    if (featuresRaw is! List) {
      throw const NoaaNwsParseException(
        "'features' was missing or not a JSON array.",
      );
    }
    final out = <WinterAlert>[];
    for (final feature in featuresRaw) {
      if (feature is! Map<String, dynamic>) continue;
      final propsRaw = feature['properties'];
      if (propsRaw is! Map<String, dynamic>) continue;
      final WinterAlert alert;
      try {
        alert = WinterAlert.fromProperties(propsRaw);
      } on NoaaNwsParseException {
        // One malformed feature does not poison the whole batch. Skip
        // it and keep going; the publisher occasionally ships features
        // missing `event` (per CAP `messageType: Cancel` patterns).
        continue;
      }
      if (!alert.isWinterEvent) continue;
      if (actualOnly && !alert.isActual) continue;
      out.add(alert);
    }
    return out;
  }
}
