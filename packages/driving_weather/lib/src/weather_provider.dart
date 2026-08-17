/// Abstract weather provider — decouples application logic from data source.
///
/// Implement this interface to plug any weather data source into a driving
/// application. Swap real APIs, fleet-sourced data, or mock providers
/// without touching application logic.
///
/// ## Offline behaviour (the Measured-or-Absent contract, O3)
///
/// [conditions] emits a sealed [WeatherReading], never a bare
/// [WeatherCondition]. When the upstream source is unreachable, an
/// implementation MUST say so:
///
/// - it has a previous observation → emit [WeatherStale], carrying the real
///   age of that observation and the cause of the failure;
/// - it has none → emit [WeatherUnavailable].
///
/// An implementation MUST NOT re-emit a previous [WeatherCondition] as though
/// it were fresh, and MUST NOT substitute a synthetic "clear" value for data it
/// does not have. Both were real defects in versions up to 0.4.4.
library;

import 'weather_condition.dart';
import 'weather_reading.dart';

abstract class WeatherProvider {
  /// Stream of weather readings — observed, stale, or unavailable.
  Stream<WeatherReading> get conditions;

  /// Start monitoring weather conditions.
  Future<void> startMonitoring();

  /// Stop monitoring weather conditions.
  Future<void> stopMonitoring();

  /// Release all resources.
  void dispose();
}
