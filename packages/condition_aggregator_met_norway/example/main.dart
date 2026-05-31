// Minimal usage example for condition_aggregator_met_norway.
//
// Fetches the MET Norway locationforecast for a point in Oslo and
// prints any driver-actionable Advisory derived from the next-hour
// slice (freezing precipitation, heavy precipitation, or subzero
// forecast). An empty list is the publisher saying "no
// driver-actionable condition forecast for the next hour".
//
// Integrators publishing under their own identity SHOULD override the
// User-Agent constructor argument — MET Norway terms require an
// identifying User-Agent naming the application/domain plus a contact
// email or website link. The default points at this reference repo.
import 'package:condition_aggregator_met_norway/condition_aggregator_met_norway.dart';

Future<void> main() async {
  final provider = MetNorwayAdvisoryProvider(
    userAgent: 'sngnav-example/0.0.1 github.com/aki1770-del/sngnav',
  );
  try {
    await provider.init();
    final advisories = await provider.fetchActiveAdvisoriesAtPoint(
      latitude: 59.91,
      longitude: 10.75,
    );
    if (advisories.isEmpty) {
      print(
        'MET Norway: no driver-actionable condition '
        'forecast in the next hour.',
      );
      return;
    }
    for (final a in advisories) {
      print('${a.eventClass} (${a.severity.name}) — ${a.headline}');
      print('  ${a.areaDescription}');
      print('  effective ${a.effective}, expires ${a.expires}');
      print('  ${a.description}');
    }
  } finally {
    provider.close();
  }
}
