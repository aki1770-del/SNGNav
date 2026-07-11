/// Open-Meteo weather provider — real weather data for driving applications.
///
/// Fetches current weather from the Open-Meteo API (free, no API key).
/// Maps WMO weather codes + temperature to [WeatherCondition].
///
/// ## Absence is never filled in (Measured-or-Absent, O1)
///
/// Any field the response does not carry stays `null`. Up to and including
/// 0.4.4, an empty `hourly` block silently produced `visibility = 10000` (i.e.
/// "clear") and `snowfall = 0` — values the API never sent. It no longer does.
///
/// ## Offline behaviour (O3)
///
/// On fetch failure this provider emits [WeatherStale] (carrying the real age
/// of the last observation and the cause) or, with no prior observation,
/// [WeatherUnavailable]. Up to 0.4.4 it silently re-emitted the last condition
/// with no staleness marker, and emitted nothing at all when it had none.
///
/// Implements [WeatherProvider] — same 4 methods as
/// [SimulatedWeatherProvider]. Application logic is implementation-agnostic;
/// providers are swappable.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'weather_condition.dart';
import 'weather_provider.dart';
import 'weather_reading.dart';

class OpenMeteoWeatherProvider implements WeatherProvider {
  /// HTTP client — injectable for testing.
  final http.Client _client;

  /// Latitude for weather query (default: Nagoya region).
  final double latitude;

  /// Longitude for weather query (default: Nagoya region).
  final double longitude;

  /// How often to poll the API. Default 5 minutes.
  final Duration pollInterval;

  StreamController<WeatherReading>? _controller;
  Timer? _timer;

  /// Last successfully parsed condition, and when it was actually observed.
  WeatherCondition? _lastCondition;
  DateTime? _lastObservedAt;

  /// When the provider first found itself without data. Cleared on success.
  DateTime? _unavailableSince;

  OpenMeteoWeatherProvider({
    http.Client? client,
    this.latitude = 35.18,
    this.longitude = 136.91,
    this.pollInterval = const Duration(minutes: 5),
  }) : _client = client ?? http.Client();

  @override
  Stream<WeatherReading> get conditions {
    _controller ??= StreamController<WeatherReading>.broadcast();
    return _controller!.stream;
  }

  @override
  Future<void> startMonitoring() async {
    // Guard: do not restart after dispose.
    if (_controller == null) return;

    // Cancel any existing timer before starting — prevents timer leak on
    // double-start (e.g. retry after error without an intervening stop).
    _timer?.cancel();
    _timer = null;

    // Fetch immediately on start.
    await _fetchAndEmit();

    // Guard: dispose may have been called while _fetchAndEmit was awaiting.
    if (_controller == null || _controller!.isClosed) return;

    // Then poll at the configured interval.
    _timer = Timer.periodic(pollInterval, (_) => _fetchAndEmit());
  }

  @override
  Future<void> stopMonitoring() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    _controller?.close();
    _controller = null;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Future<void> _fetchAndEmit() async {
    if (_controller == null || _controller!.isClosed) return;

    try {
      final condition = await fetchWeather();
      if (_controller == null || _controller!.isClosed) return;
      // Belt-and-braces: never let a content-free condition overwrite the last
      // REAL observation. If it did, the next genuine failure would emit a
      // WeatherStale carrying nothing — the fallback the driver depends on in
      // the compound-failure case would have been quietly poisoned.
      if (!condition.isFullyUnknown) {
        _lastCondition = condition;
        _lastObservedAt = condition.timestamp;
      }
      _unavailableSince = null;
      _controller!.add(WeatherObserved(condition));
    } catch (error) {
      // The fetch failed. Say so — never re-emit an old condition as though it
      // were fresh, and never go silent.
      if (_controller == null || _controller!.isClosed) return;
      final now = DateTime.now();
      final last = _lastCondition;
      final observedAt = _lastObservedAt;
      if (last != null && observedAt != null) {
        _controller!.add(
          WeatherStale(
            lastKnown: last,
            observedAt: observedAt,
            age: now.difference(observedAt),
            cause: error,
          ),
        );
      } else {
        _unavailableSince ??= now;
        _controller!.add(
          WeatherUnavailable(since: _unavailableSince!, cause: error),
        );
      }
    }
  }

  /// Fetches current weather from Open-Meteo and returns a [WeatherCondition].
  ///
  /// Visible for testing — allows direct invocation without stream machinery.
  Future<WeatherCondition> fetchWeather() async {
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$latitude'
      '&longitude=$longitude'
      '&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m'
      '&hourly=snowfall,visibility'
      '&forecast_days=1'
      '&timezone=Asia%2FTokyo',
    );

    final response = await _client.get(uri);

    if (response.statusCode != 200) {
      throw HttpException(
        'Open-Meteo returned ${response.statusCode}',
        uri: uri,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return parseWeatherResponse(json);
  }

  /// Parses an Open-Meteo JSON response into a [WeatherCondition].
  ///
  /// Every field the response does not carry is left `null`. Nothing is
  /// defaulted: a missing visibility is not 10 km, a missing snowfall is not
  /// zero, and a missing temperature is not above freezing.
  ///
  /// **A body with no `current` block is not a weather response at all** — it
  /// is a failure, and it throws [WeatherParseException] so that the caller
  /// routes it to [WeatherStale] / [WeatherUnavailable]. That distinction is
  /// load-bearing: "the source did not measure this field" (`null`, honest) is
  /// a different fact from "the response was not a weather response". Parsing
  /// a malformed body into an all-null condition would label it
  /// [WeatherObserved] — a reading claiming to be an observation when nothing
  /// was observed — and would also overwrite the last real observation, so the
  /// next genuine failure would emit a [WeatherStale] carrying nothing.
  ///
  /// Visible for testing — allows unit-testing the parser without HTTP.
  static WeatherCondition parseWeatherResponse(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>?;
    final hourly = json['hourly'] as Map<String, dynamic>?;

    if (current == null) {
      throw const WeatherParseException(
        'Open-Meteo response carried no `current` block — not a weather '
        'response',
      );
    }

    // `current` block — measured. Absent entries stay null.
    final temperature = (current['temperature_2m'] as num?)?.toDouble();
    final weatherCode = (current['weather_code'] as num?)?.toInt();
    final windSpeed = (current['wind_speed_10m'] as num?)?.toDouble();
    // Relative humidity in percent. Optional: older cached responses and other
    // feeds may omit it — a missing value stays null (never fabricated), so the
    // radiative-frost classifier simply abstains rather than guessing.
    final humidityRH = (current['relative_humidity_2m'] as num?)?.toDouble();

    // `hourly` block — current hour's snowfall and visibility. An empty or
    // absent list means WE DO NOT KNOW. It does not mean zero snow and 10 km
    // of visibility (which is what 0.4.4 and earlier claimed here).
    final snowfall = _hourlyValue(hourly?['snowfall']);
    final visibility = _hourlyValue(hourly?['visibility']);

    // Map WMO weather code to our model. With no code, precipitation is
    // unknown — unless the hourly snowfall itself evidences snow.
    PrecipitationType? precipType;
    PrecipitationIntensity? intensity;
    if (weatherCode != null) {
      (precipType, intensity) = _mapWeatherCode(weatherCode, snowfall);
    } else if (snowfall != null && snowfall > 0) {
      (precipType, intensity) = _inferFromSnowfall(snowfall);
    }

    // Ice risk: sub-zero temperature + any precipitation. Derivable ONLY when
    // both inputs are present; otherwise it is unknown, never `false`.
    bool? iceRisk;
    if (temperature != null && precipType != null) {
      iceRisk = temperature <= 0 && precipType != PrecipitationType.none;
    }

    return WeatherCondition(
      precipType: precipType,
      intensity: intensity,
      temperatureCelsius: temperature,
      visibilityMeters: visibility,
      windSpeedKmh: windSpeed,
      iceRisk: iceRisk,
      humidityRH: humidityRH,
      source: ObservationSource.measured,
      timestamp: DateTime.now(),
    );
  }

  /// Reads the current hour's entry out of an Open-Meteo `hourly` list.
  ///
  /// Returns `null` — never a stand-in value — when the list is absent, empty,
  /// carries no entry at the current hour, or carries a non-numeric entry.
  ///
  /// The index is NOT clamped into the list. A truncated response (say, three
  /// entries read at 20:00) does not carry this hour's value; substituting a
  /// DIFFERENT hour's snowfall or visibility and presenting it as "now" is the
  /// same fabrication class this contract exists to remove — it just launders
  /// the wrong hour instead of the wrong number.
  static double? _hourlyValue(Object? list) {
    if (list is! List || list.isEmpty) return null;
    final index = DateTime.now().hour;
    if (index >= list.length) return null;
    final value = list[index];
    return value is num ? value.toDouble() : null;
  }

  /// Maps WMO weather code to (PrecipitationType, PrecipitationIntensity).
  ///
  /// WMO codes: https://open-meteo.com/en/docs
  ///   0 = Clear, 1-3 = Clouds, 45-48 = Fog,
  ///   51-57 = Drizzle, 61-67 = Rain, 71-77 = Snow,
  ///   80-82 = Rain showers, 85-86 = Snow showers,
  ///   95-99 = Thunderstorm.
  static (PrecipitationType, PrecipitationIntensity) _mapWeatherCode(
    int code,
    double? snowfallCm,
  ) {
    // Snow codes: 71 (light), 73 (moderate), 75 (heavy), 77 (snow grains).
    if (code == 71 || code == 85) {
      return (PrecipitationType.snow, PrecipitationIntensity.light);
    }
    if (code == 73) {
      return (PrecipitationType.snow, PrecipitationIntensity.moderate);
    }
    if (code == 75 || code == 86) {
      return (PrecipitationType.snow, PrecipitationIntensity.heavy);
    }
    if (code == 77) {
      return (PrecipitationType.snow, PrecipitationIntensity.light);
    }

    // Rain codes: 51 (light drizzle), 53, 55, 61 (light rain), 63, 65, 80-82.
    if (code >= 51 && code <= 57) {
      return (PrecipitationType.rain, PrecipitationIntensity.light);
    }
    if (code == 61 || code == 80) {
      return (PrecipitationType.rain, PrecipitationIntensity.light);
    }
    if (code == 63 || code == 81) {
      return (PrecipitationType.rain, PrecipitationIntensity.moderate);
    }
    if (code == 65 || code == 82) {
      return (PrecipitationType.rain, PrecipitationIntensity.heavy);
    }

    // Sleet codes: 66 (light freezing rain), 67 (heavy freezing rain).
    if (code == 66) {
      return (PrecipitationType.sleet, PrecipitationIntensity.light);
    }
    if (code == 67) {
      return (PrecipitationType.sleet, PrecipitationIntensity.heavy);
    }

    // Thunderstorm codes: 95-99.
    if (code >= 95) {
      return (PrecipitationType.rain, PrecipitationIntensity.heavy);
    }

    // If snowfall > 0 but code doesn't match snow, infer from data.
    if (snowfallCm != null && snowfallCm > 0) {
      return _inferFromSnowfall(snowfallCm);
    }

    // Clear / cloudy / fog — the code positively says no precipitation.
    return (PrecipitationType.none, PrecipitationIntensity.none);
  }

  /// Infers snow intensity from a measured hourly snowfall depth (cm/hr).
  static (PrecipitationType, PrecipitationIntensity) _inferFromSnowfall(
    double snowfallCm,
  ) {
    if (snowfallCm >= 2.0) {
      return (PrecipitationType.snow, PrecipitationIntensity.heavy);
    }
    if (snowfallCm >= 0.5) {
      return (PrecipitationType.snow, PrecipitationIntensity.moderate);
    }
    return (PrecipitationType.snow, PrecipitationIntensity.light);
  }
}

/// Exception for HTTP errors from the Open-Meteo API.
class HttpException implements Exception {
  final String message;
  final Uri? uri;

  const HttpException(this.message, {this.uri});

  @override
  String toString() => 'HttpException: $message${uri != null ? ' ($uri)' : ''}';
}

/// Thrown when a 200-response body is not a weather response at all.
///
/// Distinct from an absent FIELD (which is honestly `null`): a body with no
/// `current` block carries no observation, and a reading built from it would
/// be a [WeatherObserved] that observed nothing. It is a failure, and it is
/// routed to [WeatherStale] / [WeatherUnavailable] like any other failure.
class WeatherParseException implements Exception {
  final String message;

  const WeatherParseException(this.message);

  @override
  String toString() => 'WeatherParseException: $message';
}
