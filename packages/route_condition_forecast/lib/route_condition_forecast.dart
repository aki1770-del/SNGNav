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
///
/// // TRI-STATE. `hazard` is a SafetyVerdict, not a bool: a route with any
/// // unmeasured segment is `unknown`, NOT `notHazardous`. Up to 0.1.5 this was
/// // `bool get hasAnyHazard`, and a route nobody had looked at answered `false`
/// // — presented to the driver as verified safe. Never collapse unknown to clear.
/// switch (forecast.hazard) {
///   case SafetyVerdict.hazardous:
///     print('Hazard at ${forecast.firstHazardEtaSeconds}s');
///   case SafetyVerdict.unknown:
///     print('Route not fully assessed — do NOT present this as clear.');
///   case SafetyVerdict.notHazardous:
///     print('Route assessed, no hazard found.');
/// }
/// ```
library;

// `RouteForecast.hazard` RETURNS a SafetyVerdict, so we must export the type —
// otherwise a consumer cannot even write the switch our own docs tell him to
// write. (Found 2026-07-14 by the L35 snippet oracle: our quickstart named a type
// the package did not hand out. Same class as routing_engine not exporting LatLng.)
export 'package:driving_weather/driving_weather.dart' show SafetyVerdict;

export 'src/models/route_forecast.dart';
export 'src/models/route_segment.dart';
export 'src/models/segment_condition_forecast.dart';
export 'src/providers/current_conditions_forecast_provider.dart';
export 'src/providers/forecast_provider.dart';
export 'src/services/route_condition_forecaster.dart';
export 'src/services/route_segmenter.dart';
