import 'package:condition_aggregator_digitraffic/condition_aggregator_digitraffic.dart';

Future<void> main() async {
  // Live Finnish traffic announcements near Helsinki (no API key needed).
  final provider = DigitrafficAdvisoryProvider();
  try {
    await provider.init();
    final advisories = await provider.fetchActiveAdvisoriesAtPoint(
      latitude: 60.17,
      longitude: 24.93,
    );
    print('${advisories.length} active advisory(ies) nearby:');
    for (final a in advisories) {
      print('  [${a.severity.name}] ${a.eventClass} — ${a.headline}');
    }
  } finally {
    provider.close(); // releases the HTTP client
  }
}
