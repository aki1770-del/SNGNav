/// MetNorwayAdvisoryProvider — `AdvisoryProvider` adapter for the MET
/// Norway (Meteorologisk institutt) locationforecast feed.
///
/// Fetches `https://api.met.no/weatherapi/locationforecast/2.0/compact`
/// (public endpoint; MET Norway terms require an identifying
/// User-Agent header naming the application and a contact email or
/// website) and maps the next-hour forecast slice for the requested
/// point to a source-neutral `Advisory` typed event when a
/// driver-relevant condition (freezing temperature or heavy
/// precipitation) is forecast. Pure Dart; only `http` +
/// `condition_aggregator` runtime dependencies.
library;

import 'dart:async';
import 'dart:convert';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:http/http.dart' as http;

/// Default MET Norway locationforecast endpoint — the compact product
/// returning hourly + multi-hour-summary forecasts as GeoJSON Point.
const String kDefaultMetNorwayLocationForecastUrl =
    'https://api.met.no/weatherapi/locationforecast/2.0/compact';

/// Default heavy-precipitation threshold in mm per hour applied to
/// `next_1_hours.details.precipitation_amount`. ≥ 4 mm/h is the WMO
/// "heavy rain" floor and aligns with driver-actionable wet-road /
/// reduced-visibility surfacing in the Nordic-region context. The
/// threshold is integrator-overridable at construction time.
const double kDefaultMetNorwayHeavyPrecipitationMmPerHour = 4.0;

/// Default freezing-temperature threshold in Celsius applied to
/// `instant.details.air_temperature`. ≤ 0 °C with non-zero
/// precipitation is the canonical winter-road risk shape (snow /
/// freezing rain / ice). Integrator-overridable.
const double kDefaultMetNorwayFreezingTemperatureCelsius = 0.0;

/// Wall-clock budget for the HTTP fetch. A runaway publisher response
/// must not stall the driver-facing UI.
const Duration _kFetchBudget = Duration(seconds: 30);

/// Hard cap on the response body in bytes. The compact endpoint
/// response is observed at ~37 KB for a single point on 2026-05-24;
/// 4 MB leaves comfortable headroom while preventing an unbounded
/// payload from exhausting integrator memory.
const int _kMaxResponseBytes = 4 * 1024 * 1024;

/// Adapter implementing [AdvisoryProvider] against the MET Norway
/// locationforecast feed.
class MetNorwayAdvisoryProvider implements AdvisoryProvider {
  /// Endpoint URL. Default points at the public compact product.
  final String endpointUrl;

  /// User-Agent string. MET Norway terms require an identifying UA
  /// naming the application/domain plus a contact email or website
  /// link; non-compliance risks throttling or a permanent ban. The
  /// canonical form for this adapter when the integrator does not
  /// override is
  /// `condition_aggregator_met_norway/0.0.1 github.com/aki1770-del/sngnav`.
  /// Integrators publishing under their own identity SHOULD override
  /// to credit themselves rather than the SNGNav reference repo.
  final String userAgent;

  /// Heavy-precipitation threshold in mm per hour.
  final double heavyPrecipitationMmPerHour;

  /// Freezing-temperature threshold in Celsius.
  final double freezingTemperatureCelsius;

  /// HTTP client — injectable for testing. The adapter does not own
  /// the lifecycle of an injected client; the caller owns close().
  /// When the no-arg constructor is used, the adapter owns the client
  /// and `close()` releases it.
  final http.Client _client;
  final bool _ownsClient;

  bool _initialized = false;

  /// Constructs an adapter that owns its own [http.Client].
  MetNorwayAdvisoryProvider({
    this.endpointUrl = kDefaultMetNorwayLocationForecastUrl,
    this.userAgent =
        'condition_aggregator_met_norway/0.0.1 '
        'github.com/aki1770-del/sngnav',
    this.heavyPrecipitationMmPerHour =
        kDefaultMetNorwayHeavyPrecipitationMmPerHour,
    this.freezingTemperatureCelsius =
        kDefaultMetNorwayFreezingTemperatureCelsius,
  }) : _client = http.Client(),
       _ownsClient = true;

  /// Constructs an adapter against a caller-supplied [http.Client]
  /// (test injection).
  MetNorwayAdvisoryProvider.withClient(
    http.Client client, {
    this.endpointUrl = kDefaultMetNorwayLocationForecastUrl,
    this.userAgent =
        'condition_aggregator_met_norway/0.0.1 '
        'github.com/aki1770-del/sngnav',
    this.heavyPrecipitationMmPerHour =
        kDefaultMetNorwayHeavyPrecipitationMmPerHour,
    this.freezingTemperatureCelsius =
        kDefaultMetNorwayFreezingTemperatureCelsius,
  }) : _client = client,
       _ownsClient = false;

  /// Names the publisher this adapter speaks for. The parent
  /// `condition_aggregator` interface enum carries
  /// `AdvisorySource.metNorway` and its verbatim CC-BY-4.0
  /// attribution string.
  @override
  AdvisorySource get source => AdvisorySource.metNorway;

  /// One-shot init. Validates that a non-empty User-Agent is
  /// configured (MET Norway terms require identification). No network
  /// handshake; pure configuration check.
  @override
  Future<void> init() async {
    if (userAgent.trim().isEmpty) {
      throw const MetNorwayConfigurationException(
        'MetNorwayAdvisoryProvider requires a non-empty User-Agent — '
        'MET Norway terms require an identifying User-Agent naming '
        'the application/domain plus a contact email or website link.',
      );
    }
    if (heavyPrecipitationMmPerHour < 0) {
      throw const MetNorwayConfigurationException(
        'heavyPrecipitationMmPerHour must be non-negative.',
      );
    }
    _initialized = true;
  }

  /// Fetches the locationforecast for the given point and returns a
  /// list of advisories derived from the next-hour forecast slice.
  ///
  /// MET Norway terms require truncating coordinates to at most 4
  /// decimal places; the adapter truncates before constructing the
  /// request URI.
  ///
  /// Returns an empty list when the next-hour slice does not match a
  /// driver-actionable threshold (no freezing temperature, no heavy
  /// precipitation). Throws [MetNorwayHttpException] on non-2xx
  /// response or [MetNorwayParseException] on malformed JSON.
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async {
    if (!_initialized) {
      throw const AdvisoryProviderInitException(
        source: AdvisorySource.metNorway,
        message:
            'MetNorwayAdvisoryProvider.fetchActiveAdvisoriesAtPoint '
            'called before init(); the AdvisoryProvider contract '
            'requires init exactly once before any fetch.',
      );
    }

    final lat = _truncateToFourDecimals(latitude);
    final lon = _truncateToFourDecimals(longitude);
    final uri = Uri.parse(endpointUrl).replace(
      queryParameters: <String, String>{
        'lat': lat.toString(),
        'lon': lon.toString(),
      },
    );

    final response = await _client
        .get(
          uri,
          headers: <String, String>{
            'User-Agent': userAgent,
            'Accept': 'application/json',
            'Accept-Encoding': 'gzip',
          },
        )
        .timeout(
          _kFetchBudget,
          onTimeout: () {
            throw MetNorwayHttpException(
              statusCode: 0,
              message:
                  'Wall-clock budget ${_kFetchBudget.inSeconds}s '
                  'exhausted before MET Norway response.',
            );
          },
        );

    if (response.statusCode != 200) {
      throw MetNorwayHttpException(
        statusCode: response.statusCode,
        message:
            'MET Norway locationforecast fetch failed: '
            'HTTP ${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > _kMaxResponseBytes) {
      throw MetNorwayHttpException(
        statusCode: response.statusCode,
        message:
            'MET Norway response exceeded $_kMaxResponseBytes-byte '
            'cap (${response.bodyBytes.length} bytes received).',
      );
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const MetNorwayParseException(
          'MET Norway response is not a JSON object',
        );
      }
      json = decoded;
    } on FormatException catch (e) {
      throw MetNorwayParseException(
        'MET Norway response is not valid JSON: ${e.message}',
      );
    }

    final advisory = mapLocationForecastResponseToAdvisory(
      response: json,
      heavyPrecipitationMmPerHour: heavyPrecipitationMmPerHour,
      freezingTemperatureCelsius: freezingTemperatureCelsius,
    );
    if (advisory == null) return const <Advisory>[];
    return <Advisory>[advisory];
  }

  /// Releases the underlying [http.Client] HTTP resources if this
  /// adapter constructed it; no-op if a caller-supplied client was
  /// injected via [MetNorwayAdvisoryProvider.withClient].
  void close() {
    if (_ownsClient) _client.close();
  }
}

double _truncateToFourDecimals(double v) {
  // MET Norway terms: "Truncate coordinates to max 4 decimals" — this
  // is both a cache-friendliness ask from the publisher AND a privacy
  // posture (the driver's exact location is not transmitted at sub-11m
  // resolution).
  final sign = v.isNegative ? -1.0 : 1.0;
  final abs = v.abs();
  final truncated = (abs * 10000).truncateToDouble() / 10000.0;
  return sign * truncated;
}

/// Maps a MET Norway locationforecast/2.0/compact response to a
/// source-neutral [Advisory], or returns `null` if the next-hour
/// forecast slice does not match a driver-actionable threshold.
///
/// Mapping (v0.0.1):
/// - `source` ← `AdvisorySource.metNorway`
/// - `eventClass` ← derived from the first matched condition:
///   - `Freezing precipitation` when air_temperature ≤
///     [freezingTemperatureCelsius] AND next-hour precipitation > 0
///   - `Heavy precipitation` when next-hour precipitation ≥
///     [heavyPrecipitationMmPerHour]
///   - `Subzero forecast` when air_temperature ≤
///     [freezingTemperatureCelsius] AND precipitation == 0
///   - else: returns null (no advisory)
/// - `severity` ← heuristic by combined temperature + precipitation
///   intensity (see [_deriveSeverity])
/// - `certainty` ← `likely` when a publisher symbol_code is present;
///   else `possible`
/// - `urgency` ← `expected` (next-1-hour slice is the canonical
///   next-hour horizon)
/// - `areaDescription` ← `Lat <lat>, Lon <lon>` formatted from the
///   GeoJSON geometry. MET Norway compact response is point-based
///   and does not carry an area description string.
/// - `effective` ← parsed `timeseries[0].time` (UTC)
/// - `expires` ← effective + 1 hour (the next-1-hours slice horizon)
/// - `headline` ← short publisher-derived string (see
///   [_composeHeadline]) including the symbol_code
/// - `description` ← multi-line publisher-derived string carrying
///   the air_temperature, precipitation_amount, symbol_code, and the
///   verbatim CC-BY-4.0 attribution
///
/// Visible at top level for direct-call testing.
Advisory? mapLocationForecastResponseToAdvisory({
  required Map<String, dynamic> response,
  double heavyPrecipitationMmPerHour =
      kDefaultMetNorwayHeavyPrecipitationMmPerHour,
  double freezingTemperatureCelsius =
      kDefaultMetNorwayFreezingTemperatureCelsius,
}) {
  final properties = response['properties'];
  if (properties is! Map<String, dynamic>) return null;
  final timeseriesRaw = properties['timeseries'];
  if (timeseriesRaw is! List || timeseriesRaw.isEmpty) return null;
  final firstSlice = timeseriesRaw.first;
  if (firstSlice is! Map<String, dynamic>) return null;

  final timeRaw = firstSlice['time'];
  final effective = _parseIsoOrNull(timeRaw);

  final data = firstSlice['data'];
  if (data is! Map<String, dynamic>) return null;

  final instant = data['instant'];
  Map<String, dynamic>? instantDetails;
  if (instant is Map<String, dynamic>) {
    final d = instant['details'];
    if (d is Map<String, dynamic>) instantDetails = d;
  }

  final next1 = data['next_1_hours'];
  Map<String, dynamic>? next1Details;
  String? next1Symbol;
  if (next1 is Map<String, dynamic>) {
    final d = next1['details'];
    if (d is Map<String, dynamic>) next1Details = d;
    final s = next1['summary'];
    if (s is Map<String, dynamic>) {
      final code = s['symbol_code'];
      if (code is String && code.isNotEmpty) next1Symbol = code;
    }
  }

  final temperature = _readNum(instantDetails?['air_temperature']);
  // NULLABLE. `null` means the feed did not carry `precipitation_amount` — it
  // does NOT mean 0.0 mm. Up to 0.0.5 the `?? 0.0` here did two things, both
  // fabrication: (1) with a freezing temperature and UNMEASURED precipitation
  // it silently classified "Subzero forecast" (moderate) instead of the
  // "Freezing precipitation" (severe) it would have reached had the value
  // actually been measured above zero — absence resolving to the benign branch;
  // (2) it printed "next_1_hours precipitation_amount 0.0 mm" into the
  // driver-facing description for a figure the feed never sent.
  final precipitation = _readNum(next1Details?['precipitation_amount']);

  final eventClass = _classify(
    temperature: temperature,
    precipitation: precipitation,
    heavyPrecipitationMmPerHour: heavyPrecipitationMmPerHour,
    freezingTemperatureCelsius: freezingTemperatureCelsius,
  );
  if (eventClass == null) return null;

  final severity = _deriveSeverity(
    eventClass: eventClass,
    temperature: temperature,
    precipitation: precipitation,
    heavyPrecipitationMmPerHour: heavyPrecipitationMmPerHour,
    freezingTemperatureCelsius: freezingTemperatureCelsius,
  );

  final certainty = next1Symbol != null
      ? AdvisoryCertainty.likely
      : AdvisoryCertainty.possible;

  final geometry = response['geometry'];
  final areaDescription = _composeAreaDescription(geometry);

  final headline = _composeHeadline(
    eventClass: eventClass,
    symbolCode: next1Symbol,
  );

  final description = _composeDescription(
    temperature: temperature,
    precipitation: precipitation,
    symbolCode: next1Symbol,
  );

  return Advisory(
    source: AdvisorySource.metNorway,
    eventClass: eventClass,
    severity: severity,
    certainty: certainty,
    urgency: AdvisoryUrgency.expected,
    areaDescription: areaDescription,
    effective: effective,
    expires: effective?.add(const Duration(hours: 1)),
    headline: headline,
    description: description,
  );
}

/// Event classes this adapter can emit.
///
/// `Freezing, precipitation not measured` exists because absence must not be
/// sorted onto the benign end of the scale. With a freezing temperature and an
/// unmeasured precipitation figure, we do not know whether ice is falling —
/// and per the contract's asymmetry (positive evidence fires on partial data;
/// only the BENIGN verdict requires complete data) an unknown must not be
/// quietly filed as the milder "Subzero forecast".
const String _freezingPrecipitation = 'Freezing precipitation';
const String _freezingPrecipUnmeasured = 'Freezing, precipitation not measured';
const String _heavyPrecipitation = 'Heavy precipitation';
const String _subzeroForecast = 'Subzero forecast';

String? _classify({
  required double? temperature,
  required double? precipitation,
  required double heavyPrecipitationMmPerHour,
  required double freezingTemperatureCelsius,
}) {
  final freezing =
      temperature != null && temperature <= freezingTemperatureCelsius;

  // An unmeasured precipitation figure can never make `heavy` true, and it must
  // never make it FALSE either — it simply is not evidence.
  final heavy =
      precipitation != null && precipitation >= heavyPrecipitationMmPerHour;

  if (freezing && precipitation != null && precipitation > 0) {
    return _freezingPrecipitation;
  }
  if (heavy) return _heavyPrecipitation;
  if (freezing && precipitation == null) return _freezingPrecipUnmeasured;
  if (freezing && precipitation == 0) return _subzeroForecast;
  return null;
}

AdvisorySeverity _deriveSeverity({
  required String eventClass,
  required double? temperature,
  required double? precipitation,
  required double heavyPrecipitationMmPerHour,
  required double freezingTemperatureCelsius,
}) {
  // Heuristic severity at v0.0.1:
  // - extreme: freezing precipitation AND precipitation ≥ heavy floor
  //   (combined ice-and-heavy-fall is the canonical winter-road
  //   high-impact shape).
  // - severe: freezing precipitation OR heavy precipitation alone
  //   (either condition alone is driver-actionable).
  // - moderate: subzero forecast without precipitation (cold-road
  //   risk but no active fall).
  // - minor: otherwise (defensive default; classify() would have
  //   returned null in that case).
  if (eventClass == _freezingPrecipitation &&
      precipitation != null &&
      precipitation >= heavyPrecipitationMmPerHour) {
    return AdvisorySeverity.extreme;
  }
  if (eventClass == _freezingPrecipitation) return AdvisorySeverity.severe;
  if (eventClass == _heavyPrecipitation) return AdvisorySeverity.severe;
  // Freezing, and nobody measured whether anything is falling. This is NOT the
  // milder "subzero, dry" case — we do not know that it is dry. The severity is
  // therefore UNSTATED (never `moderate` by default): an unmeasured field must
  // not buy a downgrade. `AdvisorySeverity.unknown` ranks above minor/moderate
  // in every consumer that ranks honestly.
  if (eventClass == _freezingPrecipUnmeasured) return AdvisorySeverity.unknown;
  if (eventClass == _subzeroForecast) return AdvisorySeverity.moderate;
  return AdvisorySeverity.minor;
}

String _composeAreaDescription(Object? geometry) {
  if (geometry is! Map<String, dynamic>) return '';
  final type = geometry['type'];
  final coords = geometry['coordinates'];
  if (type == 'Point' && coords is List && coords.length >= 2) {
    final lon = _readNum(coords[0]);
    final lat = _readNum(coords[1]);
    if (lon != null && lat != null) {
      return 'Lat ${lat.toStringAsFixed(4)}, '
          'Lon ${lon.toStringAsFixed(4)}';
    }
  }
  return '';
}

String _composeHeadline({
  required String eventClass,
  required String? symbolCode,
}) {
  if (symbolCode == null) return eventClass;
  return '$eventClass — $symbolCode';
}

String _composeDescription({
  required double? temperature,
  required double? precipitation,
  required String? symbolCode,
}) {
  final parts = <String>[];
  if (temperature != null) {
    parts.add('air_temperature ${temperature.toStringAsFixed(1)} °C');
  }
  // A figure the feed did not send is not printed. Up to 0.0.5 this line
  // unconditionally emitted "precipitation_amount 0.0 mm" into the text a
  // driver reads — for a value nobody measured.
  if (precipitation != null) {
    parts.add(
      'next_1_hours precipitation_amount '
      '${precipitation.toStringAsFixed(1)} mm',
    );
  } else {
    parts.add('next_1_hours precipitation_amount not reported');
  }
  if (symbolCode != null) parts.add('symbol_code $symbolCode');
  parts.add(AdvisorySource.metNorway.attributionString);
  return parts.join('. ');
}

double? _readNum(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

DateTime? _parseIsoOrNull(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    return null;
  }
}

/// Raised when the MET Norway HTTP fetch returns a non-200 status or
/// exceeds a documented byte / wall-clock cap.
class MetNorwayHttpException implements Exception {
  /// HTTP status code observed on the failing response. Set to 0 for
  /// pre-response failures (wall-clock timeout, transport error).
  final int statusCode;

  /// Human-readable description of the failure.
  final String message;

  const MetNorwayHttpException({
    required this.statusCode,
    required this.message,
  });

  @override
  String toString() =>
      'MetNorwayHttpException(statusCode: $statusCode): $message';
}

/// Raised when the MET Norway response body cannot be parsed as the
/// expected GeoJSON-Point JSON shape.
class MetNorwayParseException implements Exception {
  /// Human-readable description of the contract violation.
  final String message;

  const MetNorwayParseException(this.message);

  @override
  String toString() => 'MetNorwayParseException: $message';
}

/// Raised when [MetNorwayAdvisoryProvider.init] is called with an
/// invalid configuration (empty User-Agent, negative threshold).
class MetNorwayConfigurationException implements AdvisoryProviderInitException {
  /// Human-readable description of the configuration failure.
  @override
  final String message;

  const MetNorwayConfigurationException(this.message);

  @override
  AdvisorySource get source => AdvisorySource.metNorway;

  @override
  String toString() => 'MetNorwayConfigurationException: $message';
}
