import 'package:condition_aggregator/condition_aggregator.dart';

// A provider is any class implementing AdvisoryProvider. Real adapters
// (condition_aggregator_nws / _jma) fetch live feeds; here is a 6-line one.
class MyProvider implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;
  @override
  Future<void> init() async {}
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint(
          {required double latitude, required double longitude}) async =>
      const [
        Advisory(
            source: AdvisorySource.nwsUnitedStates,
            eventClass: 'Winter Storm Warning',
            severity: AdvisorySeverity.severe,
            certainty: AdvisoryCertainty.likely,
            urgency: AdvisoryUrgency.expected,
            areaDescription: 'Erie County, NY',
            effective: null,
            expires: null,
            headline: 'Heavy snow expected',
            description: 'Travel could be very difficult to impossible.'),
      ];
}

Future<void> main() async {
  final agg = AdvisoryAggregator(providers: [MyProvider()]);
  await agg.init(); // mandatory before fetch
  final r = await agg.fetchActiveAdvisoriesAtPoint(
      latitude: 47.9253, longitude: -97.0329);
  for (final a in r.advisories) {
    print('[${a.source.name}] ${a.severity.name}: ${a.headline}');
  }
  // An empty list is only an all-clear when every source answered. If a feed is
  // down, `advisories` is empty for a completely different reason — do not
  // render that as "clear".
  if (r.advisories.isEmpty) {
    if (r.canAssertNoAdvisory) {
      print('No advisory in force (every source answered).');
    } else {
      print('Advisory feed unavailable — could NOT confirm clear: '
          '${r.providerErrors.map((e) => "${e.source.name}:${e.reason.name}").join(", ")}');
    }
  }
}
