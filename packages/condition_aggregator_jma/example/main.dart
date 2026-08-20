// Fetches live JMA warnings (snow + the 0.4.0 downpour / typhoon-wind /
// thunder / fog turmoil classes) for an Akita point and prints them.
//
// Run: dart run example/main.dart
// The provider does real network I/O against the public JMA feed, so this
// needs internet. Offline (or if JMA is unreachable) it prints the real
// error and exits cleanly instead of crashing.

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';

Future<void> main() async {
  final jma = JmaAdvisoryProvider(
    userAgent: '(condition_aggregator_jma example, https://example.com)',
  );
  await jma.init();
  try {
    final advisories = await jma.fetchActiveAdvisoriesAtPoint(
      latitude: 39.7186, // Akita city
      longitude: 140.1024,
    );
    print(jma.source.attributionString);
    if (advisories.isEmpty) {
      // Reached only when the feed was READ and is FRESH. A stale feed
      // appends a kJmaStaleFeedEventClass notice, so this branch would
      // not run.
      print('No active JMA warnings for this point, from a current feed.');
    }
    for (final a in advisories) {
      if (a.eventClass == kJmaStaleFeedEventClass) {
        // The feed answered, but nobody has written to it in a while.
        // NOT weather, and NOT an all-clear.
        print('FEED STALE — ${a.headline}');
        continue;
      }
      print('${a.eventClass} (${a.severity.name}) — ${a.areaDescription}');
    }
  } on JmaAdvisoryFetchException catch (e) {
    print('Could not reach JMA (offline?): $e');
  } finally {
    jma.close();
  }
}
