import 'package:latlong2/latlong.dart';
import 'package:driving_weather/driving_weather.dart';
import 'forecast_provider.dart';

/// Simplest [ForecastProvider]: returns the same [WeatherCondition] for every
/// position and ETA.
///
/// Use this when:
/// - operating fully offline with no forecast API available
/// - the current conditions are the best available estimate for the route
/// - writing tests that need deterministic forecast output
///
/// The returned condition is identical for all positions and ETAs.
/// Confidence degradation based on time horizon is handled by
/// [RouteConditionForecaster], not by this provider.
class CurrentConditionsForecastProvider implements ForecastProvider {
  const CurrentConditionsForecastProvider(this._condition);

  final WeatherCondition _condition;

  @override
  Future<WeatherCondition> forecastAt(
    LatLng position, {
    required double etaSeconds,
  }) async =>
      _condition;
}
