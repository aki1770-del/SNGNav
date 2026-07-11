// App-seam contract test for the offline daylight clock's REACH.
//
// The render path in lib/main.dart#_buildPretripView constructs a
// `TripGeo(latitude:_pretripLat, longitude:_pretripLon, utcOffset:…)` and
// hands it to `CommuteShape(geo: geo)` so the daylight chip can reach HER. No
// existing test exercises that production combination — grep across test/ for
// `geo:` / `TripGeo` / `PRETRIP_UTC_OFFSET` returns nothing, and the capture
// tests build their OWN geo-LESS CommuteShape. So a future edit that drops
// `geo: geo` would silently re-introduce the "capability without reach"
// failure this wiring exists to fix, and the pretrip suite would stay green.
//
// This reconstructs the EXACT production combination — the package advisor
// resolved via `PretripMessages.forLanguage`, a `TripGeo` + `CommuteShape(geo:)`,
// and the real `PretripBriefingCard` — with a dusk-crossing departure, and
// asserts the daylight chip text reaches the rendered card under both en and
// ja, and is ABSENT when geo is unwired (the regression guard). The offset is
// pinned (Akita JST +9) so the astronomy is deterministic, not timezone-flaky;
// the package daylight_test covers the astronomy itself — what is guarded here
// is the APP wiring that carries it to the screen.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

void main() {
  // A clear, above-frost dusk window so the ONLY low-light chip in play is the
  // daylight chip (peak == clear → noWinterHazard + daylight chip).
  final issued = DateTime(2026, 1, 15, 16, 0);
  final forecast = WeatherForecast(
    issuedAt: issued,
    hourly: [
      HourlyForecast(
        hour: DateTime(2026, 1, 15, 17),
        tempCelsius: 3,
        visibilityMeters: 8000,
      ),
      HourlyForecast(
        hour: DateTime(2026, 1, 15, 18),
        tempCelsius: 3,
        visibilityMeters: 8000,
      ),
    ],
  );
  // Departure 17:45, +30 min → arrival 18:15. Akita sunset is ~16:30 in
  // mid-January, so the arrival instant is postDusk (the package daylight_test
  // pins 18:00 @ Akita as postDusk). The genuine trip instants — NOT the
  // worst-hazard slot — drive the chip.
  final departure = DateTime(2026, 1, 15, 17, 45);
  const duration = Duration(minutes: 30);
  // Pinned offset == what `--dart-define=PRETRIP_UTC_OFFSET_MIN=540` produces in
  // production, so the assertion is deterministic on any host timezone.
  const geo = TripGeo(
    latitude: 39.72,
    longitude: 140.10,
    utcOffset: Duration(hours: 9),
  );

  PretripBriefing briefFor(String lang, {required bool wireGeo}) {
    final advisor = SnowAwarePretripAdvisor(
      messages: PretripMessages.forLanguage(lang),
    );
    final commute = CommuteShape(
      plannedDeparture: departure,
      plannedDuration: duration,
      routeIdentifiers: const ['app-seam'],
      flexibility: CommuteFlexibility.discretionary,
      geo: wireGeo ? geo : null,
    );
    return advisor.brief(
      forecast: forecast,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );
  }

  Future<void> pumpCard(WidgetTester tester, PretripBriefing briefing) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: PretripBriefingCard(
              briefing: briefing,
              commute: CommuteShape(
                plannedDeparture: departure,
                plannedDuration: duration,
                routeIdentifiers: const ['app-seam'],
                flexibility: CommuteFlexibility.discretionary,
              ),
              forecastIssuedAt: issued,
              tripRequired: false,
              onTripRequiredChanged: (_) {},
              sourceCaption: 'test',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('daylight chip reaches the card (en) when geo is wired', (
    tester,
  ) async {
    await pumpCard(tester, briefFor('en', wireGeo: true));
    expect(
      find.textContaining('past sunset'),
      findsWidgets,
      reason: 'the postDusk daylight chip must render when geo is wired',
    );
  });

  testWidgets('daylight chip reaches the card (ja) when geo is wired', (
    tester,
  ) async {
    await pumpCard(tester, briefFor('ja', wireGeo: true));
    expect(
      find.textContaining('日の入り'),
      findsWidgets,
      reason: 'the JA postDusk daylight chip must render when geo is wired',
    );
  });

  testWidgets(
    'NO daylight chip when geo is unwired (the reach regression guard)',
    (tester) async {
      await pumpCard(tester, briefFor('en', wireGeo: false));
      expect(
        find.textContaining('past sunset'),
        findsNothing,
        reason:
            'dropping `geo: geo` must drop the daylight chip — '
            'this is the capability-without-reach regression',
      );
    },
  );
}
