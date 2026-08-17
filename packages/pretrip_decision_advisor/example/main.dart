// End-to-end pre-trip briefing from this package, offline + deterministic.
//
// A pretrip_source_* provider (JMA / MET Norway / Digitraffic) gives you a
// measured VisibilityObservation and a WeatherForecast; here we construct them
// inline so the example is reproducible with no network. See those packages to
// fetch real measurements.
//
// HONESTY (binding): visibility is NEVER estimated; a warning never produces a
// number; an observation is valid for the DEPARTURE HOUR only; null = the
// driver's own judgment (a real source returns null, never a fabricated value).
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';

void main() {
  // 1. A winter-morning forecast — temperature only, NO visibility (exactly the
  //    shape a compact global forecast gives; this is why a MEASURED visibility
  //    source is needed to reach the whiteout band).
  final forecast = WeatherForecast(
    issuedAt: DateTime(2026, 1, 1, 6),
    hourly: [
      for (var h = 7; h <= 11; h++)
        HourlyForecast(hour: DateTime(2026, 1, 1, h), tempCelsius: -6),
    ],
  );

  // 2. A MEASURED visibility observation, exactly as a pretrip_source_* provider
  //    emits it. 80 m is the labelled whiteout case; a real provider returns
  //    null (never a fabricated number) when no fresh reading is in range.
  final observed = VisibilityObservation(
    meters: 80,
    stationId: 32402,
    stationName: 'Akita',
    measuredAt: DateTime(2026, 1, 1, 7, 10),
    distanceKm: 0.4,
  );

  final commute = CommuteShape(
    plannedDeparture: DateTime(2026, 1, 1, 7, 15),
    plannedDuration: const Duration(minutes: 30),
    routeIdentifiers: const ['akita-morning-errand'],
    flexibility: CommuteFlexibility.discretionary,
  );

  // 3. Merge the NOW measurement into the DEPARTURE-HOUR slot only (never
  //    projected forward), then brief.
  final merged = mergeObservedVisibility(
    forecast,
    observed,
    commute.plannedDeparture,
  );
  final briefing = const SnowAwarePretripAdvisor().brief(
    forecast: merged,
    commute: commute,
    profile: const DriverProfileSpec(
      profileTag: 'akitaRural',
      reactionTimeSeconds: 1.5,
    ),
  );

  // 4. Read the typed result out — this is what an edge dev renders in their UI.
  print('Verdict : ${briefing.verdict.name}');
  print('Strength: ${briefing.recommendation?.strength.name ?? "(none)"}');
  print(
    'Delay   : ${briefing.recommendation?.suggestedDelay ?? Duration.zero}',
  );
  print('Chips   :');
  for (final c in briefing.chips) {
    print('  - $c');
  }

  // The SAME deterministic logic, in Japanese — for a driver who reads
  // Japanese. The measured numbers (80 m, 07:00, 08:15) survive translation
  // verbatim; only the surrounding words change.
  final jaBriefing = const SnowAwarePretripAdvisor(messages: PretripMessages.ja)
      .brief(
        forecast: merged,
        commute: commute,
        profile: const DriverProfileSpec(
          profileTag: 'akitaRural',
          reactionTimeSeconds: 1.5,
        ),
      );
  print('Chips (ja):');
  for (final c in jaBriefing.chips) {
    print('  - $c');
  }
  print(
    'Measured: ${observed.meters} m at ${observed.stationName} '
    '(${observed.distanceKm.toStringAsFixed(1)} km away)',
  );
}
