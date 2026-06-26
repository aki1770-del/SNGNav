// Fetches live JMA snow advisories for an Akita point and prints them.
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
      print('No active snow advisories for this point right now.');
    }
    for (final a in advisories) {
      print('${a.eventClass} (${a.severity.name}) — ${a.areaDescription}');
    }
  } on JmaAdvisoryFetchException catch (e) {
    print('Could not reach JMA (offline?): $e');
  } finally {
    jma.close();
  }
}
