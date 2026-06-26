import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficVisibilityProvider();
  // Nearest measured road visibility to Helsinki (60.17 N, 24.93 E), now.
  final obs = await provider.fetchNearestVisibility(latitude: 60.17, longitude: 24.93);
  provider.close();

  if (obs == null) {
    // No fresh sensor in range — visibility is NEVER estimated; the call stays the driver's.
    print('No fresh measured visibility in range — not estimated.');
    return;
  }
  print('Measured ${obs.meters} m visibility at ${obs.stationName} '
      '(${obs.distanceKm.toStringAsFixed(1)} km away), at ${obs.measuredAt.toIso8601String()}.');
  print(kDigitrafficVisibilityAttributionString); // CC BY 4.0 attribution — required at your UI.
}
