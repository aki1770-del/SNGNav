/// Weather condition model and provider abstraction for driving applications.
///
/// Models precipitation, visibility, ice risk, and wind — the data a
/// driving application needs to assess weather safety.
///
/// Three components:
/// - **[WeatherCondition]**: Equatable model with precipitation type/intensity,
///   temperature, visibility, wind speed, and ice risk.
/// - **[WeatherProvider]**: Abstract interface — implement to plug any weather
///   data source into a driving application.
/// - **[OpenMeteoWeatherProvider]**: Concrete provider using the free Open-Meteo
///   API with offline fallback (re-emits last known condition on failure).
/// - **[SimulatedWeatherProvider]**: Demo provider generating a realistic
///   mountain-pass snow scenario (clear → light → heavy → ice → clearing).
///
/// Safety: ASIL-QM — display and advisory only, no vehicle control.
///
/// ```dart
/// import 'package:driving_weather/driving_weather.dart';
///
/// final provider = OpenMeteoWeatherProvider(
///   latitude: 35.18,
///   longitude: 136.91,
/// );
/// await provider.startMonitoring();
/// provider.conditions.listen((condition) {
///   if (condition.isHazardous) {
///     print('WARNING: ${condition.precipType.name} — ice=${condition.iceRisk}');
///   }
/// });
/// ```
library;

export 'src/weather_condition.dart';
export 'src/weather_provider.dart';
export 'src/open_meteo_weather_provider.dart';
export 'src/simulated_weather_provider.dart';
