/// JmaAdvisoryProvider — `AdvisoryProvider` adapter for the JMA
/// **windowless per-prefecture warning JSON**.
///
/// 0.2.0 resolves the caller's lat/lon to one of the catalogued
/// snow-zone prefecture (office) codes, fetches the single small
/// `warning/{areacode}.json`, parses the current in-force warnings,
/// filters to the snow / blizzard / icing classes, and maps each to a
/// source-neutral `Advisory`.
///
/// ## Why the warning JSON (replaces the 0.1.x atom-feed path)
///
/// Through 0.1.x the adapter read the JMA disaster-info atom feed
/// (`extra.xml`) and walked each linked per-prefecture report XML. An
/// independent safety audit found a **window / scroll-off
/// false-negative**: the atom feed is a recent-publication *window*, so
/// a still-in-force warning that was last re-issued before the window
/// opens scrolls off and is silently missed — a false-negative for a
/// snow-WARNING package. The windowless `warning/{areacode}.json`
/// always reflects the *current in-force* state with no window to
/// scroll off (and is ~7 KB vs ~0.6 MB for the atom feed).
///
/// Construction discipline (per condition_aggregator interface
/// contract):
/// - configuration is constructor-injected;
/// - `init()` is invoked exactly once before any
///   `fetchActiveAdvisoriesAtPoint` call;
/// - configuration change → new adapter instance.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:http/http.dart' as http;

import 'jma_advisory_mapper.dart';

/// Base URL for the JMA windowless per-prefecture warning JSON. The
/// provider appends `{areacode}.json` (e.g. `050000.json` for Akita).
///
/// This endpoint always reflects the prefecture's CURRENT in-force
/// warning state — there is no publication window to scroll off, which
/// is the false-negative the 0.1.x atom-feed path could not avoid.
const String kJmaWarningJsonBaseUrl =
    'https://www.jma.go.jp/bosai/warning/data/warning/';

/// Hard caps applied to network I/O so a runaway publisher response
/// cannot exhaust integrator memory or stall the driver-facing UI.
const Duration kJmaFetchWallClockBudget = Duration(seconds: 30);

/// Per-prefecture warning JSON byte cap. The live response is tiny
/// (Akita observed 2026-06-26 at 7,424 bytes); 256 KiB gives ample
/// headroom for a prefecture under many simultaneous warnings while
/// still bounding a runaway response. This is ~16x smaller than the
/// old atom-feed cap — the windowless JSON is per-prefecture, not a
/// national feed of every recent report.
const int kJmaWarningJsonMaxBytes = 256 * 1024;

/// Thrown when the provider cannot reach the JMA endpoint, the
/// response exceeds a documented byte cap, or the wall-clock budget
/// is exhausted before a successful parse.
class JmaAdvisoryFetchException implements Exception {
  final String message;
  final Uri? uri;
  final int? statusCode;
  const JmaAdvisoryFetchException(this.message, {this.uri, this.statusCode});

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (status $statusCode)';
    final u = uri == null ? '' : ' [$uri]';
    return 'JmaAdvisoryFetchException: $message$code$u';
  }
}

/// Adapter implementing [AdvisoryProvider] against the JMA windowless
/// per-prefecture warning JSON.
class JmaAdvisoryProvider implements AdvisoryProvider {
  /// Base URL for the per-prefecture warning JSON. Default points at
  /// the public JMA bosai endpoint; injectable for testing or for an
  /// integrator-side mirror.
  final String warningJsonBaseUrl;

  /// User-Agent string. JMA does not require auth, but a contactable
  /// User-Agent is best practice so the publisher can reach the
  /// integrator if a request shape misbehaves at scale.
  final String userAgent;

  /// HTTP client — injectable for testing.
  final http.Client _http;

  /// Whether [init] has been called.
  bool _initialized = false;

  JmaAdvisoryProvider({
    this.warningJsonBaseUrl = kJmaWarningJsonBaseUrl,
    this.userAgent =
        '(sngnav-class app, https://github.com/aki1770-del/sngnav)',
    http.Client? client,
  }) : _http = client ?? http.Client();

  /// Releases the underlying HTTP client. Safe to call once after the
  /// provider's last fetch.
  void close() => _http.close();

  @override
  AdvisorySource get source => AdvisorySource.jmaJapan;

  @override
  Future<void> init() async {
    if (userAgent.trim().isEmpty) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.jmaJapan,
        message:
            'JmaAdvisoryProvider requires a non-empty User-Agent so the '
            'publisher can reach the integrator if a request misbehaves.',
      );
    }
    _initialized = true;
  }

  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.jmaJapan,
        message:
            'JmaAdvisoryProvider.fetchActiveAdvisoriesAtPoint called before '
            'init(); the AdvisoryProvider contract requires init exactly '
            'once before any fetch.',
      );
    }

    final prefectureCode = prefectureCodeForPoint(
      latitude: latitude,
      longitude: longitude,
    );
    if (prefectureCode == null) {
      // The point is outside the Japan bounding-box catalog the
      // adapter ships (6 snow-zone prefectures). Return empty — the
      // aggregator's other providers (e.g. NWS) cover points outside
      // the catalog at this layer.
      return const <Advisory>[];
    }

    final uri = Uri.parse('$warningJsonBaseUrl$prefectureCode.json');
    return _fetchAndParse(uri, prefectureCode).timeout(
      kJmaFetchWallClockBudget,
      onTimeout: () {
        final seconds = kJmaFetchWallClockBudget.inSeconds;
        throw JmaAdvisoryFetchException(
          'Wall-clock budget $seconds seconds exhausted before fetch '
          'completed.',
          uri: uri,
        );
      },
    );
  }

  Future<List<Advisory>> _fetchAndParse(
    Uri uri,
    String prefectureCode,
  ) async {
    final body = await _httpGet(uri, kJmaWarningJsonMaxBytes);
    final List<JmaWarningRecord> records;
    try {
      records = parseJmaWarningJson(body, prefectureCode: prefectureCode);
    } on FormatException catch (e) {
      throw JmaAdvisoryFetchException(
        'JMA warning JSON parse failed: $e',
        uri: uri,
      );
    }
    return records.map(mapJmaWarningToAdvisory).toList();
  }

  Future<String> _httpGet(Uri uri, int maxBytes) async {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': 'application/json',
    };
    http.Response response;
    try {
      response = await _http.get(uri, headers: headers);
    } on SocketException catch (e) {
      throw JmaAdvisoryFetchException(
        'Transport failure contacting JMA: $e',
        uri: uri,
      );
    } catch (e) {
      throw JmaAdvisoryFetchException(
        'Transport failure contacting JMA: $e',
        uri: uri,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JmaAdvisoryFetchException(
        'JMA returned non-2xx',
        uri: uri,
        statusCode: response.statusCode,
      );
    }
    if (response.bodyBytes.length > maxBytes) {
      throw JmaAdvisoryFetchException(
        'JMA response exceeded $maxBytes-byte cap '
        '(${response.bodyBytes.length} bytes received).',
        uri: uri,
      );
    }
    // The warning JSON is utf-8. `response.body` defaults to latin-1
    // unless the Content-Type carries an explicit charset; explicitly
    // decode utf-8 to preserve JA characters across HTTP layers that
    // strip the charset hint.
    return utf8.decode(response.bodyBytes, allowMalformed: false);
  }
}
