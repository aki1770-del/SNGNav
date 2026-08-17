/// Weather condition model and provider abstraction for driving applications.
///
/// Models precipitation, visibility, ice risk, and wind — the data a
/// driving application needs to assess weather safety.
///
/// ## The Measured-or-Absent contract
///
/// This package will not tell you something it did not measure.
///
/// - Every measured field on [WeatherCondition] is nullable. `null` means NOT
///   MEASURED — never zero, never benign, never "clear".
/// - Safety verdicts are tri-state ([SafetyVerdict]), never `bool`, because a
///   `bool` resolves "I don't know" into its `false` branch — which for a
///   hazard question is the "clear road" branch.
/// - A failed fetch is a [WeatherStale] or [WeatherUnavailable] reading, not a
///   silently re-dated old value.
///
/// Versions up to and including 0.4.4 did all three of the wrong things. See
/// CHANGELOG 0.5.0.
///
/// Components:
/// - **[WeatherCondition]**: Equatable model with precipitation type/intensity,
///   temperature, visibility, wind speed, ice risk — all nullable — plus
///   [ObservationSource] provenance and any [HazardAssertion] declared by an
///   authority.
/// - **[WeatherReading]**: sealed — [WeatherObserved] | [WeatherStale] |
///   [WeatherUnavailable]. What a provider actually hands you.
/// - **[WeatherProvider]**: Abstract interface — implement to plug any weather
///   data source into a driving application.
/// - **[OpenMeteoWeatherProvider]**: Concrete provider using the free Open-Meteo
///   API.
/// - **[DigitrafficWeatherProvider]**: Finnish road-authority advisories,
///   carried as a [HazardAssertion] — never laundered into fake sensor values.
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
/// provider.conditions.listen((reading) {
///   switch (reading) {
///     case WeatherObserved(:final condition):
///       switch (condition.hazard) {
///         case SafetyVerdict.hazardous:
///           print('WARNING: hazardous conditions');
///         case SafetyVerdict.notHazardous:
///           print('Conditions assessed: no hazard');
///         case SafetyVerdict.unknown:
///           // NOT a green light. Say so.
///           print('Conditions could not be assessed — drive to what you see');
///       }
///     case WeatherStale(:final age):
///       print('Weather is stale — last seen ${age.inMinutes} min ago');
///     case WeatherUnavailable():
///       print('No weather data');
///   }
/// });
/// ```
library;

export 'src/weather_condition.dart';
export 'src/weather_reading.dart';
export 'src/weather_provider.dart';
export 'src/open_meteo_weather_provider.dart';
export 'src/simulated_weather_provider.dart';
export 'src/digitraffic_weather_provider.dart';
