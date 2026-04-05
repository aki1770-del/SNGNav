/// Open-Meteo weather provider — real weather data for driving applications.
///
/// Fetches current weather from the Open-Meteo API (free, no API key).
/// Maps WMO weather codes + temperature to [WeatherCondition].
///
/// Offline fallback: if the HTTP request fails, re-emits the last known
/// condition (if any) so the UI stays populated with stale data rather
/// than going blank.
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

class OpenMeteoWeatherProvider implements WeatherProvider {
  /// HTTP client — injectable for testing.
  final http.Client _client;

  /// Latitude for weather query (default: Nagoya region).
  final double latitude;

  /// Longitude for weather query (default: Nagoya region).
  final double longitude;

  /// How often to poll the API. Default 5 minutes.
  final Duration pollInterval;

  StreamController<WeatherCondition>? _controller;
  Timer? _timer;

  /// Last successfully parsed condition — used for offline fallback.
  WeatherCondition? _lastCondition;

  OpenMeteoWeatherProvider({
    http.Client? client,
    this.latitude = 35.18,
    this.longitude = 136.91,
    this.pollInterval = const Duration(minutes: 5),
  }) : _client = client ?? http.Client();

  @override
  Stream<WeatherCondition> get conditions {
    _controller ??= StreamController<WeatherCondition>.broadcast();
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
      _lastCondition = condition;
      _controller!.add(condition);
    } catch (_) {
      // Offline fallback: re-emit last known condition if available.
      if (_controller == null || _controller!.isClosed) return;
      if (_lastCondition != null) {
        _controller!.add(_lastCondition!);
      }
      // If no last condition, silently skip — application stays in current state.
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
      '&current=temperature_2m,weather_code,wind_speed_10m'
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
  /// Visible for testing — allows unit-testing the parser without HTTP.
  static WeatherCondition parseWeatherResponse(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final hourly = json['hourly'] as Map<String, dynamic>;

    final temperature = (current['temperature_2m'] as num).toDouble();
    final weatherCode = (current['weather_code'] as num).toInt();
    final windSpeed = (current['wind_speed_10m'] as num).toDouble();

    // Get current hour's snowfall and visibility from hourly data.
    final snowfallList = hourly['snowfall'] as List<dynamic>;
    final visibilityList = hourly['visibility'] as List<dynamic>;

    double snowfall = 0;
    double visibility = 10000;

    if (snowfallList.isNotEmpty && visibilityList.isNotEmpty) {
      // Find the current hour index (use first entry as approximation).
      final now = DateTime.now();
      final currentHourIndex =
          now.hour.clamp(0, snowfallList.length - 1);
      snowfall =
          (snowfallList[currentHourIndex] as num?)?.toDouble() ?? 0;
      visibility =
          (visibilityList[currentHourIndex] as num?)?.toDouble() ?? 10000;
    }

    // Map WMO weather code to our model.
    final (precipType, intensity) = _mapWeatherCode(weatherCode, snowfall);

    // Ice risk: sub-zero temperature + any precipitation.
    final iceRisk =
        temperature <= 0 && precipType != PrecipitationType.none;

    return WeatherCondition(
      precipType: precipType,
      intensity: intensity,
      temperatureCelsius: temperature,
      visibilityMeters: visibility,
      windSpeedKmh: windSpeed,
      iceRisk: iceRisk,
      timestamp: DateTime.now(),
    );
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
    double snowfallCm,
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
    if (snowfallCm > 0) {
      if (snowfallCm >= 2.0) {
        return (PrecipitationType.snow, PrecipitationIntensity.heavy);
      }
      if (snowfallCm >= 0.5) {
        return (PrecipitationType.snow, PrecipitationIntensity.moderate);
      }
      return (PrecipitationType.snow, PrecipitationIntensity.light);
    }

    // Clear / cloudy / fog — no precipitation.
    return (PrecipitationType.none, PrecipitationIntensity.none);
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
