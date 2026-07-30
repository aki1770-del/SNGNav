import 'package:condition_aggregator/condition_aggregator.dart';

// A provider is any class implementing AdvisoryProvider. Real adapters
// (condition_aggregator_nws / _jma) fetch live feeds; here is a 6-line one.
class MyProvider implements AdvisoryProvider {
  @override
  AdvisorySource get source => AdvisorySource.nwsUnitedStates;
  @override
  Future<void> init() async {}
  @override
  Future<List<Advisory>> fetchActiveAdvisoriesAtPoint({
    required double latitude,
    required double longitude,
  }) async => const [
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
      description: 'Travel could be very difficult to impossible.',
    ),
  ];
}

Future<void> main() async {
  final agg = AdvisoryAggregator(providers: [MyProvider()]);
  await agg.init(); // mandatory before fetch
  final result = await agg.fetchActiveAdvisoriesAtPoint(
    latitude: 47.9253,
    longitude: -97.0329,
  );

  // Act on what we SAW. A hazard seen is a hazard real, even if some other
  // source was unreachable — so this line is safe in every case.
  for (final a in result.seen) {
    print('[${a.source.name}] ${a.severity.name}: ${a.headline}');
  }

  // Now the line that matters. You may ONLY tell a driver "nothing is in force"
  // when every source actually answered. `seen.isEmpty` does NOT mean that —
  // it is also what you get when the weather service was down.
  if (result.canAssertNoAdvisory && result.seen.isEmpty) {
    print('No advisory in force. (Every source answered.)');
  } else if (result.seen.isEmpty) {
    // We could not look, and we found nothing — but the nothing is meaningless.
    // Tell her the feed is down. Do NOT tell her it is clear, and do not tell
    // her nothing at all.
    for (final f in result.failures) {
      print('COULD NOT CHECK ${f.source}: ${_why(f.reason)}');
    }
  }

  // And if you want the compiler to hold you to all three cases, switch on it:
  switch (result) {
    case AdvisoryLookupComplete():
      break; // the picture is whole
    case AdvisoryLookupPartial():
      break; // act on what you saw; do not claim completeness
    case AdvisoryLookupUnavailable():
      break; // you know nothing — say so
  }
}

/// The reason is an enum, not a string, so you can say it in the language your
/// driver actually reads. She can act on "the weather service did not answer".
/// She cannot act on a stack trace.
String _why(AdvisoryUnavailableReason r) => switch (r) {
  AdvisoryUnavailableReason.networkUnreachable => 'no network',
  AdvisoryUnavailableReason.timedOut => 'the source did not answer in time',
  AdvisoryUnavailableReason.refused => 'the source refused the request',
  AdvisoryUnavailableReason.unparseable => 'the response was unreadable',
  AdvisoryUnavailableReason.incompleteAreaCoverage =>
    'part of the area could not be read — a warning may exist there',
  AdvisoryUnavailableReason.notInitialised => 'the adapter was not started',
  AdvisoryUnavailableReason.unclassified => 'the source failed',
};
