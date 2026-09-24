// What the nearest Finnish road-weather station measured about the ROAD.
//
// FINLAND ONLY. Digitraffic's road-weather network covers Finland; this call
// answers nothing anywhere else, and there is no equivalent road-surface
// source for Japan.
import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficVisibilityProvider();
  // Rovaniemi, Lapland — rural, and where the road freezes first.
  final obs = await provider.fetchNearestRoadSurface(
    latitude: 66.50,
    longitude: 25.73,
  );
  provider.close();

  if (obs == null) {
    // No fresh road-surface sensor in range. Nothing is estimated; the call
    // stays the driver's.
    print('No fresh measured road surface in range — not estimated.');
    return;
  }

  print(
    'Station ${obs.stationName} (#${obs.stationId}), '
    '${obs.distanceKm.toStringAsFixed(1)} km away, '
    'measured ${obs.measuredAt.toIso8601String()}',
  );
  for (final s in obs.surfaceStates) {
    print(
      '  ${s.sensorName}: ${s.code} = "${s.publisherLabel}"  '
      'VSS=${s.vssRoadSurfaceCondition ?? "(no VSS equivalent — not guessed)"}',
    );
  }
  if (obs.sensorFaultDeclared) {
    print('  the station declared a sensor fault — no surface class from it');
  }
  print(
    '  coldest surface: ${obs.coldestSurfaceCelsius} °C '
    '(${obs.coldestSurfaceSensor})',
  );
  print(
    '  highest freezing point: ${obs.highestFreezingPointCelsius} °C '
    '(${obs.highestFreezingPointSensor})',
  );
  print(
    '  fastest cooling: ${obs.fastestSurfaceCoolingCelsiusPerHour} °C/h '
    '(${obs.fastestSurfaceCoolingSensor})',
  );
  print(
    '  present but NOT interpreted (no publisher code table): '
    '${obs.uninterpretedSensors.join(", ")}',
  );
  print(kDigitrafficVisibilityAttributionString);
}
