// Minimal example for condition_aggregator_owm_road_risk.
//
// Demonstrates constructing the OpenWeatherMap Road Risk
// AdvisoryProvider. Operators supply their own publisher API key
// (`appid`); for an offline example we construct with a placeholder
// key and show identity. Wire this provider into an
// `AdvisoryAggregator` from `condition_aggregator` to compose with
// sibling adapters (JMA / NWS / etc).

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_owm_road_risk/condition_aggregator_owm_road_risk.dart';

void main() {
  final provider = OwmRoadRiskProvider.withApiKey(
    apiKey: 'your-openweathermap-api-key',
  );
  print('Source: ${provider.source.name}');
  print('Attribution: ${provider.source.attributionString}');
}
