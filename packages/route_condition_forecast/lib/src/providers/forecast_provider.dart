import 'package:latlong2/latlong.dart';
import 'package:driving_weather/driving_weather.dart';

/// Provides a weather forecast for a given position and future time horizon.
///
/// Implementations range from simple (return current conditions for all
/// future times) to complex (call a forecast API with time-aware interpolation).
///
/// The [etaSeconds] parameter expresses how far in the future to forecast.
/// A value of 0 means "conditions right now at this location".
/// Implementations should degrade [confidence] as [etaSeconds] grows.
abstract class ForecastProvider {
  /// Returns forecasted [WeatherCondition] for [position] at [etaSeconds]
  /// seconds from now.
  Future<WeatherCondition> forecastAt(
    LatLng position, {
    required double etaSeconds,
  });
}
