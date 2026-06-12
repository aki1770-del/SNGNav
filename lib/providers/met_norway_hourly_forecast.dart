/// MetNorwayHourlyForecastProvider — live hourly forecast source for the
/// pre-trip "Before you drive" briefing.
///
/// Fetches `https://api.met.no/weatherapi/locationforecast/2.0/compact`
/// (the same publisher endpoint the `condition_aggregator_met_norway`
/// adapter speaks; the locationforecast product is GLOBAL, so it serves a
/// Nagoya commute as well as a Tromsø one) and maps the FULL hourly
/// timeseries into the `pretrip_decision_advisor` contract's
/// [WeatherForecast] — where the sibling advisory adapter maps only the
/// first slice into a single in-trip advisory, the pre-trip surface needs
/// every hour so the advisor can search for a better departure window.
///
/// Honesty rules, binding:
/// - The compact product carries NO visibility and NO road-surface state.
///   Those fields are mapped as `null` — absence of data is never turned
///   into presence of hazard (or absence of hazard) the publisher did not
///   forecast. The advisor's icing rule (precipitation at near-freezing
///   temperature) still fires on snow forecasts from temperature +
///   precipitation alone.
/// - Slices without a `next_1_hours` block (the 6-hourly tail of the
///   timeseries) are skipped, not interpolated. The forecast simply ends
///   where hourly resolution ends, and the advisor's no-data handling
///   takes over past that horizon.
/// - All fetch/parse failures surface as exceptions or `null` to the
///   caller; nothing is fabricated.
///
/// MET Norway terms: requests carry an identifying User-Agent and
/// coordinates truncated to 4 decimals (publisher cache-friendliness AND
/// a privacy posture — the driver's sub-11 m position is not transmitted).
/// Forecast data is © MET Norway, CC BY 4.0; the caller surfaces the
/// attribution wherever the data is shown.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

/// Default MET Norway locationforecast compact endpoint.
const String kMetNorwayLocationForecastUrl =
    'https://api.met.no/weatherapi/locationforecast/2.0/compact';

/// Wall-clock budget for the HTTP fetch — a slow publisher response must
/// not stall app startup (the fetch is fire-and-update, never blocking).
const Duration _kFetchBudget = Duration(seconds: 30);

/// Hard cap on the response body. The compact response for a single point
/// is observed at ~40 KB (Nagoya, 2026-06-12); 4 MB leaves headroom while
/// bounding memory.
const int _kMaxResponseBytes = 4 * 1024 * 1024;

/// Fetches and maps a MET Norway hourly forecast for one point.
class MetNorwayHourlyForecastProvider {
  /// Constructs a provider that owns its own [http.Client].
  MetNorwayHourlyForecastProvider({
    this.endpointUrl = kMetNorwayLocationForecastUrl,
    this.userAgent = 'sngnav_snow_scene github.com/aki1770-del/SNGNav',
  })  : _client = http.Client(),
        _ownsClient = true;

  /// Constructs a provider against a caller-supplied client (test injection).
  MetNorwayHourlyForecastProvider.withClient(
    http.Client client, {
    this.endpointUrl = kMetNorwayLocationForecastUrl,
    this.userAgent = 'sngnav_snow_scene github.com/aki1770-del/SNGNav',
  })  : _client = client,
        _ownsClient = false;

  /// Endpoint URL — default is the public compact product.
  final String endpointUrl;

  /// Identifying User-Agent (MET Norway terms require one naming the
  /// application plus a contact point; integrators deploying under their
  /// own identity SHOULD override to credit themselves).
  final String userAgent;

  final http.Client _client;
  final bool _ownsClient;

  /// Fetches the forecast for the given point and maps the hourly
  /// timeseries. Returns `null` when the response parses but carries no
  /// usable hourly slices. Throws [MetNorwayForecastException] on
  /// configuration, HTTP, or parse failure.
  Future<WeatherForecast?> fetchForecast({
    required double latitude,
    required double longitude,
  }) async {
    if (userAgent.trim().isEmpty) {
      throw const MetNorwayForecastException(
        'A non-empty identifying User-Agent is required by MET Norway terms.',
      );
    }

    final uri = Uri.parse(endpointUrl).replace(
      queryParameters: <String, String>{
        'lat': _truncateToFourDecimals(latitude).toString(),
        'lon': _truncateToFourDecimals(longitude).toString(),
      },
    );

    final response = await _client.get(uri, headers: <String, String>{
      'User-Agent': userAgent,
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip',
    }).timeout(
      _kFetchBudget,
      onTimeout: () => throw MetNorwayForecastException(
        'Wall-clock budget ${_kFetchBudget.inSeconds}s exhausted before '
        'MET Norway response.',
      ),
    );

    if (response.statusCode != 200) {
      throw MetNorwayForecastException(
        'MET Norway locationforecast fetch failed: '
        'HTTP ${response.statusCode}',
      );
    }
    if (response.bodyBytes.length > _kMaxResponseBytes) {
      throw MetNorwayForecastException(
        'MET Norway response exceeded $_kMaxResponseBytes-byte cap '
        '(${response.bodyBytes.length} bytes received).',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (e) {
      throw MetNorwayForecastException(
        'MET Norway response is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const MetNorwayForecastException(
        'MET Norway response is not a JSON object.',
      );
    }
    return mapLocationForecastToWeatherForecast(decoded);
  }

  /// Releases the underlying client if this provider constructed it.
  void close() {
    if (_ownsClient) _client.close();
  }
}

/// Maps a locationforecast/2.0/compact response to the pre-trip contract's
/// [WeatherForecast], or returns `null` when no usable hourly slice exists.
///
/// Field mapping per hourly slice (a slice is hourly iff it carries a
/// `next_1_hours` block):
/// - `hour`                    ← `timeseries[i].time` (UTC, converted to local
///                               wall-clock so it aligns with the commute's
///                               local planned departure)
/// - `tempCelsius`             ← `instant.details.air_temperature` (slice
///                               skipped when absent — temperature is the one
///                               required contract field)
/// - `humidityRH`              ← `instant.details.relative_humidity`, or null
/// - `precipitationMmPerHour`  ← `next_1_hours.details.precipitation_amount`,
///                               or null
/// - `visibilityMeters`        ← null ALWAYS (not in the compact product)
/// - `estimatedRoadCondition`  ← null ALWAYS (sky-state is not surface-state;
///                               we do not estimate what the publisher did
///                               not forecast)
///
/// `issuedAt` ← `properties.meta.updated_at`; the mapper returns null when
/// it is absent/unparseable rather than inventing an issue time (the
/// advisor's staleness chip depends on it being real).
///
/// Top-level for direct-call testing.
WeatherForecast? mapLocationForecastToWeatherForecast(
  Map<String, dynamic> response,
) {
  final properties = response['properties'];
  if (properties is! Map<String, dynamic>) return null;

  final meta = properties['meta'];
  final issuedAt = meta is Map<String, dynamic>
      ? _parseIsoOrNull(meta['updated_at'])
      : null;
  if (issuedAt == null) return null;

  final timeseries = properties['timeseries'];
  if (timeseries is! List || timeseries.isEmpty) return null;

  final hourly = <HourlyForecast>[];
  for (final raw in timeseries) {
    if (raw is! Map<String, dynamic>) continue;
    final hour = _parseIsoOrNull(raw['time']);
    if (hour == null) continue;

    final data = raw['data'];
    if (data is! Map<String, dynamic>) continue;

    // Hourly resolution only: the 6-hourly tail has no next_1_hours block
    // and is skipped, never interpolated.
    final next1 = data['next_1_hours'];
    if (next1 is! Map<String, dynamic>) continue;

    final instant = data['instant'];
    final instantDetails = instant is Map<String, dynamic>
        ? instant['details']
        : null;
    if (instantDetails is! Map<String, dynamic>) continue;

    final temp = _readNum(instantDetails['air_temperature']);
    if (temp == null) continue; // required contract field — skip, not guess

    final next1Details = next1['details'];
    final precip = next1Details is Map<String, dynamic>
        ? _readNum(next1Details['precipitation_amount'])
        : null;

    hourly.add(HourlyForecast(
      hour: hour.toLocal(),
      tempCelsius: temp,
      humidityRH: _readNum(instantDetails['relative_humidity']),
      precipitationMmPerHour: precip,
      // Compact product carries neither visibility nor surface state.
      visibilityMeters: null,
      estimatedRoadCondition: null,
    ));
  }

  if (hourly.isEmpty) return null;
  return WeatherForecast(hourly: hourly, issuedAt: issuedAt.toLocal());
}

double _truncateToFourDecimals(double v) {
  final sign = v.isNegative ? -1.0 : 1.0;
  final truncated = (v.abs() * 10000).truncateToDouble() / 10000.0;
  return sign * truncated;
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

/// Raised on configuration, HTTP, or parse failure of the forecast fetch.
class MetNorwayForecastException implements Exception {
  const MetNorwayForecastException(this.message);

  /// Human-readable description of the failure.
  final String message;

  @override
  String toString() => 'MetNorwayForecastException: $message';
}
