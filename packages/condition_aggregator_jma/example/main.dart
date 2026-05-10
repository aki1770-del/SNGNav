// Minimal example for condition_aggregator_jma.
//
// Demonstrates constructing the JMA AdvisoryProvider. The provider
// fetches the JMA disaster-info atom feed at runtime — for an offline
// example we just construct + show identity. Wire this provider into
// an `AdvisoryAggregator` from `condition_aggregator` to compose with
// sibling adapters (NWS / OWM Road Risk / etc).

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';

void main() {
  final provider = JmaAdvisoryProvider();
  print('Source: ${provider.source.name}');
  print('Attribution: ${provider.source.attributionString}');
}
