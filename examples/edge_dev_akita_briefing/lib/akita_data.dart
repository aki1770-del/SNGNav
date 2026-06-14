/// Edge-developer data assembly for HER mother's Akita pre-trip briefing.
///
/// This file is PURE DART — no Flutter. It is the data path an edge developer
/// writes using ONLY the two published-shaped packages:
///
///   * `pretrip_decision_advisor` — the contract + reference advisor + the
///     source-neutral `VisibilityObservation` / `mergeObservedVisibility`.
///   * `pretrip_source_jma` — the `JmaVisibilityProvider` that turns a real
///     Japan Meteorological Agency AMeDAS reading into a `VisibilityObservation`.
///
/// The chain (≤4 hops to the driver):
///   JMA AMeDAS visibility sensor (秋田 / Akita 32402)
///     → JmaVisibilityProvider  → VisibilityObservation (metres)
///     → mergeObservedVisibility into the departure-hour forecast slot
///     → SnowAwarePretripAdvisor.brief() → PretripBriefing
///     → the edge developer's OWN widget so HER mother can decide before she
///       sets out into unexpected snow.
library;

import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:pretrip_source_jma/pretrip_source_jma.dart'
    show JmaVisibilityProvider, JmaVisibilityException;

/// 秋田 / Akita — HER mother's anchor (AMeDAS station 32402 @ 39.72, 140.10).
const double akitaLat = 39.72;
const double akitaLon = 140.10;

/// A deterministic, offline winter-morning forecast for Akita.
///
/// Temperature only (subzero), no visibility — exactly the shape MET Norway's
/// compact product gives a Japanese point, and exactly why a MEASURED
/// visibility source (AMeDAS) is needed to reach the whiteout band. Dated to a
/// January morning so the render is reproducible regardless of when it is run.
WeatherForecast akitaWinterForecast() {
  final issued = DateTime(2026, 1, 1, 6);
  return WeatherForecast(
    issuedAt: issued,
    hourly: [
      for (var h = 7; h <= 11; h++)
        HourlyForecast(hour: DateTime(2026, 1, 1, h), tempCelsius: -6),
    ],
  );
}

/// The planned commute the briefing is computed for. Discretionary so the
/// advisor may suggest waiting; departure 07:15 sits inside the forecast.
CommuteShape akitaCommute() => CommuteShape(
      plannedDeparture: DateTime(2026, 1, 1, 7, 15),
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['akita-morning-errand'],
      flexibility: CommuteFlexibility.discretionary,
    );

/// HER mother's driver profile (reaction-time is calibration only — never
/// changes the strength of the recommendation, per the advisor contract).
DriverProfileSpec akitaDriver() => const DriverProfileSpec(
      profileTag: 'akitaRural',
      reactionTimeSeconds: 1.5,
    );

/// The WHITEOUT-case measured observation, constructed offline so the demo is
/// deterministic.
///
/// HONEST: 80 m is the whiteout case (the in-trip turn-back band). Live Akita
/// visibility in June reads clear; this labelled value demonstrates the path
/// that lights the severe band when the AMeDAS sensor really does read low.
/// Shaped exactly as `JmaVisibilityProvider` would emit it from station 32402.
VisibilityObservation akitaWhiteoutObservation() => VisibilityObservation(
      meters: 80,
      stationId: 32402,
      stationName: 'Akita',
      measuredAt: DateTime(2026, 1, 1, 7, 10),
      distanceKm: 0.4,
    );

/// Runs the full data path for a given measured visibility observation and
/// returns the briefing the edge developer's widget renders. This is the whole
/// of the edge developer's logic — three published-package calls.
PretripBriefing assembleAkitaBriefing(VisibilityObservation observation) {
  final forecast = akitaWinterForecast();
  final commute = akitaCommute();

  // 1. Merge the NOW measurement into the single departure-hour slot only.
  final merged =
      mergeObservedVisibility(forecast, observation, commute.plannedDeparture);

  // 2. Brief on the merged forecast.
  const advisor = SnowAwarePretripAdvisor();
  return advisor.brief(
    forecast: merged,
    commute: commute,
    profile: akitaDriver(),
  );
}

/// PRODUCTION path: fetch a REAL measured AMeDAS visibility near Akita using
/// the published `JmaVisibilityProvider`. Returns `null` when no fresh
/// QC-normal reading is within range — the honest "driver's own judgement"
/// outcome (never a fabricated number). Used by the live-refresh button in the
/// running app; the deterministic demo + the capture test do NOT call it, so
/// the render never depends on the network.
Future<VisibilityObservation?> fetchLiveAkitaVisibility() async {
  final provider = JmaVisibilityProvider();
  try {
    return await provider.fetchNearestVisibility(
      latitude: akitaLat,
      longitude: akitaLon,
    );
  } on JmaVisibilityException {
    // Honest degradation: a fetch/parse failure returns the decision to the
    // driver rather than inventing a value.
    return null;
  } finally {
    provider.close();
  }
}
