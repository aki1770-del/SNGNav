/// JmaAdvisoryProvider — `AdvisoryProvider` adapter for the JMA
/// disaster-info XML feed via direct-Dart-XML-parse.
///
/// 0.1.0 deploys without a jmaxml typed-binding in transit. The
/// provider fetches the atom feed (`extra_l.xml` by default), filters
/// to the 気象警報・注意報 prefecture report family (`VPWW54`),
/// fetches each linked per-prefecture report XML, parses for
/// `<Item><Kind><Name>` events that match a snow / blizzard / icing
/// advisory class, and maps to source-neutral `Advisory`. The
/// caller's lat/lon picks the prefecture (bounding-box approximate
/// resolution; broader region resolution is composition-time work).
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

/// Default atom feed URL — the long-form 随時 (extra_l) feed where
/// 気象警報・注意報 prefecture reports surface.
///
/// The 定時 (regular_l) feed carries periodic forecasts, NOT live
/// advisories — so we default to extra_l and let integrators override
/// at construction time if they need a different feed shape.
const String kDefaultJmaAtomFeedUrl =
    'https://www.data.jma.go.jp/developer/xml/feed/extra_l.xml';

/// Atom-entry title strings that signal a prefecture-class warning /
/// advisory report containing per-area `<Item><Kind>` events. Other
/// title strings (大雨危険度通知, 季節予報, etc.) carry different
/// payload shapes and are out of scope at deploy 0.1.0.
const Set<String> kJmaPrefectureWarningReportTitles = <String>{
  '気象警報・注意報（Ｈ２７）',
  '気象特別警報・警報・注意報',
};

/// Hard caps applied to network I/O so a runaway publisher response
/// cannot exhaust integrator memory or stall the driver-facing UI.
const Duration kJmaFetchWallClockBudget = Duration(seconds: 30);
// Atom feed lists ALL recent JMA reports across Japan (not per-point),
// so the response is publisher-wide rather than caller-scoped. Observed
// at ~1.6 MB during normal cadence; busy weather days run larger. 4 MB
// gives generous headroom while still preventing a runaway publisher
// response from exhausting integrator memory.
const int kJmaAtomFeedMaxBytes = 4 * 1024 * 1024;
const int kJmaReportXmlMaxBytes = 200 * 1024;

/// Thrown when the provider cannot reach the JMA endpoint, the
/// response exceeds a documented byte cap, or the wall-clock budget
/// is exhausted before a successful parse.
class JmaAdvisoryFetchException implements Exception {
  final String message;
  final Uri? uri;
  final int? statusCode;
  const JmaAdvisoryFetchException(
    this.message, {
    this.uri,
    this.statusCode,
  });

  @override
  String toString() {
    final code = statusCode == null ? '' : ' (status $statusCode)';
    final u = uri == null ? '' : ' [$uri]';
    return 'JmaAdvisoryFetchException: $message$code$u';
  }
}

/// Adapter implementing [AdvisoryProvider] against the JMA
/// disaster-info atom feed via direct-Dart-XML-parse.
class JmaAdvisoryProvider implements AdvisoryProvider {
  /// Atom feed URL. Default points at the public JMA extra_l feed.
  final String atomFeedUrl;

  /// User-Agent string. JMA does not require auth, but a contactable
  /// User-Agent is best practice so the publisher can reach the
  /// integrator if a request shape misbehaves at scale.
  final String userAgent;

  /// HTTP client — injectable for testing.
  final http.Client _http;

  /// Whether [init] has been called.
  bool _initialized = false;

  JmaAdvisoryProvider({
    this.atomFeedUrl = kDefaultJmaAtomFeedUrl,
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
      // adapter ships at 0.1.0 (6 snow-zone prefectures). Return
      // empty — the aggregator's other providers (e.g. NWS) cover
      // points outside the catalog at this layer.
      return const <Advisory>[];
    }

    final feedUri = Uri.parse(atomFeedUrl);
    return _fetchAndParse(feedUri, prefectureCode).timeout(
      kJmaFetchWallClockBudget,
      onTimeout: () {
        final seconds = kJmaFetchWallClockBudget.inSeconds;
        throw JmaAdvisoryFetchException(
          'Wall-clock budget $seconds seconds exhausted before fetch '
          'completed.',
          uri: feedUri,
        );
      },
    );
  }

  Future<List<Advisory>> _fetchAndParse(
    Uri feedUri,
    String prefectureCode,
  ) async {
    final feedBody = await _httpGet(feedUri, kJmaAtomFeedMaxBytes);
    final List<JmaAtomEntry> atomEntries;
    try {
      atomEntries = parseJmaAtomFeed(feedBody);
    } on Exception catch (e) {
      throw JmaAdvisoryFetchException(
        'Atom feed parse failed: $e',
        uri: feedUri,
      );
    }

    final out = <Advisory>[];
    for (final entry in atomEntries) {
      // Only the prefecture-class warning report families carry
      // per-area `<Item><Kind>` events.
      if (!kJmaPrefectureWarningReportTitles.contains(entry.title)) continue;

      // The atom-entry id+href pattern encodes the publisher area
      // code at the end of the filename, e.g.
      // `..._VPWW54_200000.xml` → 200000 (Nagano). Filter to the
      // caller's prefecture before any per-report fetch.
      if (!entry.reportUrl.contains('_$prefectureCode.xml')) continue;

      final reportBody =
          await _httpGet(Uri.parse(entry.reportUrl), kJmaReportXmlMaxBytes);
      final List<JmaForecastRecord> records;
      try {
        records = parseJmaReportXml(reportBody);
      } on Exception {
        // One malformed prefecture report does not poison the batch;
        // surface via the aggregator's per-provider error channel
        // would require a different surface. At 0.1.0 we simply
        // skip — the publisher very rarely ships malformed reports.
        // Future versions may expose a per-record error stream.
        continue;
      }

      for (final r in records) {
        if (!kJmaSnowAdvisoryEventNames.contains(r.eventName)) continue;
        out.add(mapJmaForecastToAdvisory(r));
      }
    }
    return out;
  }

  Future<String> _httpGet(Uri uri, int maxBytes) async {
    final headers = <String, String>{
      'User-Agent': userAgent,
      'Accept': 'application/atom+xml, application/xml, text/xml',
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
    // The atom feed + per-prefecture reports are utf-8 (declared in
    // the XML prolog). `response.body` defaults to latin-1 unless
    // the Content-Type carries an explicit charset; explicitly
    // decode utf-8 to preserve JA characters across HTTP layers
    // that strip the charset hint.
    return utf8.decode(response.bodyBytes, allowMalformed: false);
  }
}
