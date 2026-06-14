// Minimal usage example for pretrip_source_digitraffic.
//
// Fetches the nearest fresh measured road-network visibility near a point in
// southern Finland, merges it onto the departure-hour slot of a forecast, and
// prints the measurement. Visibility is NEVER estimated: when no fresh sensor
// is in range the observation is `null` and nothing is fabricated — that is the
// driver's own judgment to make.
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_digitraffic/pretrip_source_digitraffic.dart';

Future<void> main() async {
  final provider = DigitrafficVisibilityProvider();
  try {
    final departure = DateTime.now();
    final observation = await provider.fetchNearestVisibility(
      latitude: 60.17,
      longitude: 24.93,
      now: departure,
    );

    if (observation == null) {
      // No fresh sensor in range — nothing is estimated. The forecast is
      // surfaced as-is; the call on the drive stays with the driver.
      print('No fresh measured visibility in range — not estimated.');
      print(kDigitrafficVisibilityAttributionString);
      return;
    }

    print(
      'Measured visibility ${observation.meters} m at '
      '${observation.stationName} (${observation.distanceKm.toStringAsFixed(1)} '
      'km away), measured ${observation.measuredAt.toIso8601String()}.',
    );

    // The measurement is valid for the DEPARTURE HOUR only — never projected
    // forward. mergeObservedVisibility (from pretrip_decision_advisor) sets it
    // on the covering departure-hour slot and leaves every later hour untouched.
    final forecast = WeatherForecast(
      issuedAt: departure,
      hourly: [
        for (var h = 0; h < 6; h++)
          HourlyForecast(
            hour: DateTime(
              departure.year,
              departure.month,
              departure.day,
              departure.hour + h,
            ),
            tempCelsius: -4,
            precipitationMmPerHour: 1.0,
          ),
      ],
    );
    final merged = mergeObservedVisibility(forecast, observation, departure);
    print(
      'Departure-hour visibility on the briefing: '
      '${merged.hourly.first.visibilityMeters} m.',
    );

    // Attribution is required at the consumer-facing surface (CC BY 4.0).
    print(kDigitrafficVisibilityAttributionString);
  } finally {
    provider.close();
  }
}
