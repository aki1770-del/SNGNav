// Minimal example for route_condition_forecast.
//
// Demonstrates the typed surface — RouteSegment + RouteForecast +
// SegmentConditionForecast — that an integrator constructs from a
// planned route plus driving_weather + fleet_hazard inputs.

import 'package:route_condition_forecast/route_condition_forecast.dart';

void main() {
  print('Surface: $RouteSegment / $RouteForecast / $SegmentConditionForecast');
  print('Compose with driving_weather + fleet_hazard inputs to project');
  print('per-segment hazard with time-of-arrival weighting.');
}
