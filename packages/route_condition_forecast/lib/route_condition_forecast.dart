/// Per-segment weather and hazard forecasting along a planned route.
///
/// Projects [driving_weather] conditions and [fleet_hazard] zones onto
/// route segments with time-of-arrival weighting. Pure Dart, no Flutter.
///
/// Quick start:
/// ```dart
/// final forecaster = RouteConditionForecaster(
///   forecastProvider: CurrentConditionsForecastProvider(currentWeather),
///   hazardZones: myHazardZones,
/// );
/// final forecast = await forecaster.forecast(routeResult);
/// if (forecast.hasAnyHazard) {
///   print('Hazard at ${forecast.firstHazardEtaSeconds}s');
/// }
/// ```
library;

export 'src/models/route_forecast.dart';
export 'src/models/route_segment.dart';
export 'src/models/segment_condition_forecast.dart';
export 'src/providers/current_conditions_forecast_provider.dart';
export 'src/providers/forecast_provider.dart';
export 'src/services/route_condition_forecaster.dart';
export 'src/services/route_segmenter.dart';
