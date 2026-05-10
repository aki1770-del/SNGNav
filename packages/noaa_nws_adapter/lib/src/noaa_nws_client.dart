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
import 'dart:io' show SocketException;

import 'package:http/http.dart' as http;

import 'winter_alert.dart';

/// Retry policy for transient network failures on the NWS endpoint.
///
/// Driver-facing loom: *"winter alert in publisher's exact wording,
/// even when the publisher's network briefly hiccups."* A single
/// transient failure (5xx, brief connection reset, brief DNS
/// hiccup) should not silently drop the alert reach for the driver
/// in unexpected snow. The retry policy is conservative on intent
/// (transient-only; never retries 4xx) and bounded on attempts
/// (3 retries max) so an integrator's logs remain honest about how
/// many calls actually went out.
///
/// 4xx responses are NOT retried — they signal client-class error
/// (bad point, missing User-Agent, malformed request) where retry
/// will produce the same failure and waste the publisher's quota.
class NoaaNwsRetryPolicy {
  /// Maximum number of retry attempts after the initial call.
  /// Default: 3. Total HTTP calls = 1 + maxRetries on full exhaust.
  final int maxRetries;

  /// Base delay before the first retry. Default: 1 second. Successive
  /// retries multiply this by 2^retryIndex (1s, 2s, 4s on default).
  final Duration baseDelay;

  /// HTTP status codes that count as transient (retryable). Default:
  /// 500, 502, 503, 504, 408 (Request Timeout), 429 (Too Many
  /// Requests). 429 follows the publisher's recommended ~5-second
  /// retry-after, but we cap at this policy's bounded backoff.
  final Set<int> retryableStatusCodes;

  const NoaaNwsRetryPolicy({
    this.maxRetries = 3,
    this.baseDelay = const Duration(seconds: 1),
    this.retryableStatusCodes = const <int>{408, 429, 500, 502, 503, 504},
  }) : assert(maxRetries >= 0);

  /// No-retry policy: zero retries; preserves the historical 0.0.1
  /// behavior where the caller decides backoff.
  static const NoaaNwsRetryPolicy none = NoaaNwsRetryPolicy(maxRetries: 0);

  /// Computes the delay before retry attempt [retryIndex] (0-indexed).
  /// 0 -> baseDelay; 1 -> baseDelay × 2; 2 -> baseDelay × 4.
  Duration delayForAttempt(int retryIndex) {
    assert(retryIndex >= 0);
    final factor = 1 << retryIndex; // 2^retryIndex
    return Duration(microseconds: baseDelay.inMicroseconds * factor);
  }

  /// True if [statusCode] is in the configured retryable set.
  bool isRetryableStatus(int statusCode) =>
      retryableStatusCodes.contains(statusCode);
}

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

  /// Retry policy applied to transient failures. Defaults to
  /// [NoaaNwsRetryPolicy.none] for backwards-compat with 0.0.1
  /// (caller decides backoff). Pass an explicit
  /// `NoaaNwsRetryPolicy()` to opt in to bounded retry-with-backoff.
  final NoaaNwsRetryPolicy retryPolicy;

  /// Sleep function — injectable for testing so tests can pass a
  /// no-wait stub instead of really sleeping the bounded backoff.
  final Future<void> Function(Duration) _sleep;

  /// Constructs a client. Throws [ArgumentError] if [userAgent] is
  /// empty, since the publisher will refuse anonymous requests.
  NoaaNwsClient({
    required this.userAgent,
    http.Client? client,
    this.apiBase = kDefaultNwsApiBase,
    this.acceptHeader = kDefaultAcceptHeader,
    this.retryPolicy = NoaaNwsRetryPolicy.none,
    Future<void> Function(Duration)? sleep,
  }) : _http = client ?? http.Client(),
       _sleep = sleep ?? Future<void>.delayed {
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
  /// Throws [NoaaNwsHttpException] on 4xx (no retry) or after retry
  /// exhaust on 5xx/transport failure.
  /// Throws [NoaaNwsParseException] on GeoJSON shape mismatch.
  ///
  /// **Retry behavior** (via [retryPolicy]; default is no retry for
  /// 0.0.1 back-compat): on a transient failure (5xx, 408, 429,
  /// transport-class), the call is retried with exponential backoff
  /// up to [NoaaNwsRetryPolicy.maxRetries] times. 4xx (other than
  /// 408 / 429) is NOT retried — these are client-class errors where
  /// retry produces the same failure and wastes the publisher's
  /// quota. After retry exhaust, the most recent failure surfaces as
  /// [NoaaNwsHttpException].
  Future<List<WinterAlert>> fetchActiveWinterAlerts({
    required double latitude,
    required double longitude,
    bool actualOnly = true,
  }) async {
    final uri = Uri.parse('$apiBase/alerts/active?point=$latitude,$longitude');
    final response = await _fetchWithRetry(uri);
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (e) {
      throw NoaaNwsParseException('NWS response was not valid JSON: $e');
    }
    return parseFeatureCollection(decoded, actualOnly: actualOnly);
  }

  /// Performs a GET on [uri] with the configured headers and applies
  /// [retryPolicy]. Returns a 2xx response or throws
  /// [NoaaNwsHttpException] on non-retryable failure / retry exhaust.
  Future<http.Response> _fetchWithRetry(Uri uri) async {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': acceptHeader,
    };
    int attempt = 0;
    NoaaNwsHttpException lastException = NoaaNwsHttpException(
      'No attempt was made (internal logic error).',
      uri: uri,
    );
    while (true) {
      http.Response? response;
      try {
        response = await _http.get(uri, headers: headers);
      } on SocketException catch (e) {
        lastException = NoaaNwsHttpException(
          'Transport failure contacting NWS: $e',
          uri: uri,
        );
      } catch (e) {
        // Other transport-class failures (TlsException, http.ClientException
        // wrapping a connection-reset). Treated as transient.
        lastException = NoaaNwsHttpException(
          'Transport failure contacting NWS: $e',
          uri: uri,
        );
      }
      if (response != null) {
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }
        lastException = NoaaNwsHttpException(
          'NWS returned non-2xx',
          statusCode: response.statusCode,
          uri: uri,
        );
        if (!retryPolicy.isRetryableStatus(response.statusCode)) {
          throw lastException; // 4xx — do not retry; caller's bug.
        }
      }
      // At this point we have a transient failure: response==null
      // (transport-class) OR a retryable status code.
      if (attempt >= retryPolicy.maxRetries) {
        throw lastException;
      }
      await _sleep(retryPolicy.delayForAttempt(attempt));
      attempt += 1;
    }
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
        // Use fromFeature to also pick up the typed `area` from the
        // feature's top-level geometry. fromFeature delegates to
        // fromProperties for the field-level extraction; back-compat
        // is preserved for callers using fromProperties directly.
        alert = WinterAlert.fromFeature(feature);
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
