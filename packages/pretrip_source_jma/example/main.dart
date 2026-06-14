// Minimal usage example for pretrip_source_jma.
//
// Fetches the nearest fresh measured surface-visibility reading from the
// Japan Meteorological Agency AMeDAS network near a point in Japan
// (秋田 / Akita here, HER mother's anchor) and prints it. A null result means
// no fresh QC-normal reading within range — the decision returns to the
// driver's own judgement; nothing is estimated, no number is fabricated.
//
// See README.md for the full chain: merge the observation into a
// `pretrip_decision_advisor` forecast via `mergeObservedVisibility` and brief.
import 'package:pretrip_source_jma/pretrip_source_jma.dart';

Future<void> main() async {
  final provider = JmaVisibilityProvider();
  try {
    final obs = await provider.fetchNearestVisibility(
      latitude: 39.72, // 秋田 / Akita
      longitude: 140.10,
    );
    if (obs == null) {
      // No fresh measured visibility within range: the driver's own judgement.
      print('No fresh measured visibility within range.');
      return;
    }
    print('Measured ${obs.meters} m at ${obs.stationName} '
        '(${obs.distanceKm.toStringAsFixed(1)} km away, '
        'observed ${obs.measuredAt.toIso8601String()}). '
        'Source: 気象庁 / Japan Meteorological Agency (open data).');
  } finally {
    provider.close();
  }
}
