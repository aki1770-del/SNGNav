/// Abstract weather provider — decouples WeatherBloc from data source.
///
/// The edge developer can swap the simulated provider for a real weather
/// API, fleet-sourced data, or mock providers without touching the BLoC.
///
/// Same abstraction pattern as LocationProvider and RoutingEngine.
///
/// Offline behavior: when the upstream data source is unreachable,
/// implementations should re-emit the last known [WeatherCondition] via
/// `conditions` rather than letting the stream go silent. The driver sees
/// stale-but-present data instead of a blank widget. See
/// [OpenMeteoWeatherProvider] for the reference implementation (re-emits
/// cached condition on HTTP failure).
library;

import '../models/weather_condition.dart';

abstract class WeatherProvider {
  /// Stream of weather condition updates.
  Stream<WeatherCondition> get conditions;

  /// Start monitoring weather conditions.
  Future<void> startMonitoring();

  /// Stop monitoring weather conditions.
  Future<void> stopMonitoring();

  /// Release all resources.
  void dispose();
}
