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

import 'weather_absence.dart';
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
    } on WeatherDataUnavailableException catch (absence) {
      // Already a typed absence (incomplete response) — forward it as-is.
      if (_controller == null || _controller!.isClosed) return;
      _controller!.addError(absence);
    } catch (error) {
      // The feed is unreachable. Up to 0.4.4 the last known condition was
      // silently re-emitted here, with no staleness marker, so old data was
      // indistinguishable from fresh data — and with no previous condition the
      // stream simply went silent, which a UI cannot tell apart from "still
      // loading". Both are absence pretending to be an observation. The stream
      // now STOPS and SAYS WHY; the listener decides what to show (and may
      // still show the last value, clearly marked as old — `lastObservedAt`
      // carries its age).
      if (_controller == null || _controller!.isClosed) return;
      _controller!.addError(
        WeatherDataUnavailableException(
          reason: WeatherAbsenceReason.feedUnreachable,
          latitude: latitude,
          longitude: longitude,
          lastObservedAt: _lastCondition?.timestamp,
          cause: error,
        ),
      );
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
  /// Visible for testing — allows unit-testing the parser without HTTP.
  ///
  /// **Throws [WeatherDataUnavailableException]** when the response does not
  /// carry a visibility for the current hour. Up to and including 0.4.4 a
  /// missing, empty or truncated `hourly` block silently became
  /// `visibility = 10000` — i.e. "you can see for 10 km" — a figure the API
  /// never sent, and one that feeds `hasReducedVisibility` and `isHazardous`
  /// directly. `WeatherCondition` (0.4.x) has no way to say "unknown", so the
  /// parse stops instead of inventing a value.
  static WeatherCondition parseWeatherResponse(Map<String, dynamic> json) {
    final current = json['current'] as Map<String, dynamic>;
    final hourly = json['hourly'] as Map<String, dynamic>;

    final temperature = (current['temperature_2m'] as num).toDouble();
    final weatherCode = (current['weather_code'] as num).toInt();
    final windSpeed = (current['wind_speed_10m'] as num).toDouble();
    // Relative humidity in percent. Optional: older cached responses and other
    // feeds may omit it — a missing value stays null (never fabricated), so the
    // radiative-frost classifier simply abstains rather than guessing.
    final humidityRH = (current['relative_humidity_2m'] as num?)?.toDouble();

    // Current hour's snowfall and visibility. The index is NOT clamped into the
    // list: a truncated `hourly` array would then return a DIFFERENT hour's
    // reading and present it as "now". A value we do not hold for this hour is
    // absent — not the nearest hour we happen to have.
    final snowfallList = hourly['snowfall'] as List<dynamic>?;
    final visibilityList = hourly['visibility'] as List<dynamic>?;
    final hourIndex = DateTime.now().hour;

    final visibility = _hourlyValue(visibilityList, hourIndex);
    if (visibility == null) {
      // No visibility for this hour. It is not 10 km.
      throw WeatherDataUnavailableException(
        reason: WeatherAbsenceReason.incompleteResponse,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        cause: 'hourly.visibility carries no value for hour $hourIndex',
      );
    }

    // Snowfall is only ever used to ESCALATE a weather code that reports no
    // precipitation. An absent snowfall therefore cannot manufacture an
    // all-clear: the WMO code we did receive still decides. Absence simply
    // means the escalation check abstains — it is never read as "0 cm of snow".
    final snowfall = _hourlyValue(snowfallList, hourIndex);

    // Map WMO weather code to our model.
    final (precipType, intensity) = _mapWeatherCode(weatherCode, snowfall ?? 0);

    // Ice risk: sub-zero temperature + any precipitation.
    final iceRisk = temperature <= 0 && precipType != PrecipitationType.none;

    return WeatherCondition(
      precipType: precipType,
      intensity: intensity,
      temperatureCelsius: temperature,
      visibilityMeters: visibility,
      windSpeedKmh: windSpeed,
      iceRisk: iceRisk,
      humidityRH: humidityRH,
      timestamp: DateTime.now(),
    );
  }

  /// Reads the value at [hourIndex] from an Open-Meteo hourly array, or `null`
  /// when the array is missing, or does not extend to that hour, or carries a
  /// null there. The index is deliberately NOT clamped: a missing hour is
  /// absent, not the nearest hour we happen to hold.
  static double? _hourlyValue(List<dynamic>? list, int hourIndex) {
    if (list == null) return null;
    if (hourIndex < 0 || hourIndex >= list.length) return null;
    return (list[hourIndex] as num?)?.toDouble();
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
