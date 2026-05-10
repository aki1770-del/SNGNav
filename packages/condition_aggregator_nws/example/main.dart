// Minimal example for condition_aggregator_nws.
//
// Demonstrates constructing the NWS AdvisoryProvider. The provider
// fetches the NOAA NWS `/alerts/active` GeoJSON feed at runtime — for
// an offline example we just construct + show identity. Wire this
// provider into an `AdvisoryAggregator` from `condition_aggregator`
// to compose with sibling adapters (JMA / OWM Road Risk / etc).

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_nws/condition_aggregator_nws.dart';

void main() {
  final provider = NwsAdvisoryProvider(
    userAgent: '(myapp.example.com, contact@example.com)',
  );
  print('Source: ${provider.source.name}');
  print('Attribution: ${provider.source.attributionString}');
}
