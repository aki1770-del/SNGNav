// Quickstart: fetch live NWS winter alerts at a point, as typed events.
import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_nws/condition_aggregator_nws.dart';

Future<void> main() async {
  // NWS requires a User-Agent identifying your app + a contact.
  final nws = NwsAdvisoryProvider(userAgent: '(myapp.example, you@example.com)');

  // Grand Forks, ND — swap in any U.S. lat/lon (e.g. the driver's point).
  final advisories = await nws.fetchActiveAdvisoriesAtPoint(
    latitude: 47.9253, longitude: -97.0329,
  );

  print('Active winter advisories: ${advisories.length}');
  for (final a in advisories) {
    print('[${a.severity.name}] ${a.eventClass} — ${a.areaDescription}');
  }
  nws.close();
}
