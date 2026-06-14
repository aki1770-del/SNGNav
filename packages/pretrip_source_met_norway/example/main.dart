// Minimal usage example for pretrip_source_met_norway.
//
// Fetches a MET Norway hourly forecast for a point and hands the resulting
// WeatherForecast MEASUREMENT to the pretrip_decision_advisor so an edge
// developer can build their own pre-trip "Before you drive" surface. The
// locationforecast product is GLOBAL, so this works for a Nagoya commute
// (HER) and an Akita one (HER mother) as well as a Nordic one.
//
// MET Norway terms REQUIRE an identifying User-Agent naming your app plus a
// contact point — override the default below to credit yourself.
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_met_norway/pretrip_source_met_norway.dart';

Future<void> main() async {
  final provider = MetNorwayHourlyForecastProvider(
    userAgent: 'your_app/1.0 contact@example.com',
  );
  try {
    // Nagoya (HER). Coordinates are truncated to 4 decimals before sending.
    final forecast = await provider.fetchForecast(
      latitude: 35.1709,
      longitude: 136.8815,
    );
    if (forecast == null) {
      // null = no usable hourly slice; the driver's own judgement, never a
      // fabricated hazard. Surface "no data", not "all clear".
      print('No usable hourly forecast for this point.');
      return;
    }

    // The advisor turns the measurement into a departure-timing verdict.
    const advisor = SnowAwarePretripAdvisor();
    final briefing = advisor.brief(
      forecast: forecast,
      commute: CommuteShape(
        plannedDeparture: DateTime.now().add(const Duration(minutes: 30)),
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['morning-commute'],
        flexibility: CommuteFlexibility.discretionary,
      ),
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    print('Verdict: ${briefing.verdict.name}');
    print('Peak hazard: ${briefing.peakHazard.name}');
    // Attribution is REQUIRED wherever the data is shown:
    //   Data: © MET Norway, CC BY 4.0.
  } finally {
    provider.close();
  }
}
