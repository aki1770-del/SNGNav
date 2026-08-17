/// Abstract weather provider — decouples application logic from data source.
///
/// Implement this interface to plug any weather data source into a driving
/// application. Swap real APIs, fleet-sourced data, or mock providers
/// without touching application logic.
///
/// Offline behavior: when the upstream data source is unreachable,
/// implementations should re-emit the last known [WeatherCondition] via
/// [conditions] rather than letting the stream go silent. The driver sees
/// stale-but-present data instead of a blank widget.
library;

import 'weather_condition.dart';

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
