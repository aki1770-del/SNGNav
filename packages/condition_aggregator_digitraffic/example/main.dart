// Minimal usage example for condition_aggregator_digitraffic.
//
// Fetches active Digitraffic traffic announcements near a point in
// southern Finland and prints the event class and English headline of
// each matched advisory.
import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficAdvisoryProvider();
  try {
    await provider.init();
    final advisories = await provider.fetchActiveAdvisoriesAtPoint(
      latitude: 60.17,
      longitude: 24.93,
    );
    for (final a in advisories) {
      print('${a.eventClass} — ${a.headline}');
    }
  } finally {
    provider.close();
  }
}
