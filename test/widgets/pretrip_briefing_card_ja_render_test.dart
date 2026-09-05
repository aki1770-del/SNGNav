// Render-and-see capture for the Japanese pre-trip briefing (observation-grade).
//
// A normal widget test uses blank test fonts, so CJK text would not render as
// real glyphs and "tests pass" would NOT prove the driver's mother can read the card.
// This test loads the real Noto Sans CJK JP font and writes a PNG golden of
// the Japanese card, so the rendered Japanese can actually be looked at.
//
// Run: flutter test --update-goldens test/widgets/pretrip_briefing_card_ja_render_test.dart
// Then open test/widgets/goldens/pretrip_briefing_card_ja.png and LOOK.
import 'dart:io';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

void main() {
  var fontLoaded = false;
  setUpAll(() async {
    for (final path in const [
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        final loader = FontLoader('NotoSansCJK')
          ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
        await loader.load();
        fontLoaded = true;
      }
    }
  });

  testWidgets('renders the Japanese briefing for her mother in Akita', (
    tester,
  ) async {
    // Without a real CJK font the card would render tofu boxes, and a passing
    // golden would prove nothing about whether the driver's mother can read it. Skip
    // rather than bake a misleading blank (observation-grade: the artifact must be real).
    if (!fontLoaded) {
      markTestSkipped('No Noto CJK font on this host — skipping JA render.');
      return;
    }
    final dep = DateTime(2026, 1, 1, 7, 15);
    final issued = DateTime(2026, 1, 1, 6, 0);
    // The reason chips read in Japanese too now — the same locale resolution
    // main.dart performs for a `ja` driver, so this PNG shows the whole safety
    // surface (verdict + reasons + checklist + winter guidance) as the driver's mother
    // actually receives it. Only the data-source caption stays English (the
    // remaining named gap, shown not hidden).
    final advisor = SnowAwarePretripAdvisor(messages: PretripMessages.ja);

    // A whiteout-now, clear-later morning → a wait/hazard verdict with a delay.
    final forecast = WeatherForecast(
      hourly: [
        HourlyForecast(
          hour: DateTime(2026, 1, 1, 7),
          tempCelsius: -3,
          precipitationMmPerHour: 3,
          visibilityMeters: 80,
        ),
        HourlyForecast(
          hour: DateTime(2026, 1, 1, 8),
          tempCelsius: -3,
          precipitationMmPerHour: 1,
          visibilityMeters: 250,
        ),
        // The LATER hours are fully measured, since 2026-08-28. 0.6.1 will not
        // point a suggested delay into an hour it knows nothing about —
        // 「約2時間待つことを検討」 is an affirmative claim about an hour SHE is
        // not in yet, and acting on it PUTS her there. These two slots carried
        // no road surface, no humidity and no precipitation, so the advisor
        // correctly declined to offer them and this card lost its delay. The
        // fixture's own premise — "a whiteout-now, CLEAR-LATER morning" — is
        // what was untrue; measuring the later hours makes it true again.
        HourlyForecast(
          hour: DateTime(2026, 1, 1, 9),
          tempCelsius: -1,
          humidityRH: 60,
          precipitationMmPerHour: 0,
          visibilityMeters: 5000,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        ),
        HourlyForecast(
          hour: DateTime(2026, 1, 1, 10),
          tempCelsius: 0,
          humidityRH: 60,
          precipitationMmPerHour: 0,
          visibilityMeters: 8000,
          estimatedRoadCondition: RoadConditionEstimate.dry,
        ),
      ],
      issuedAt: issued,
    );
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['akita-commute'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: forecast,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'akita',
        reactionTimeSeconds: 1.5,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SizedBox(
            width: 560,
            child: PretripBriefingCard(
              strings: BriefingStrings.ja,
              briefing: briefing,
              commute: commute,
              forecastIssuedAt: issued,
              tripRequired: false,
              onTripRequiredChanged: (_) {},
              // PRODUCTION-TRUTHFUL fixture (observation-grade: the scene we look at must
              // be the scene the driver's mother gets, not an idealised one). The winter
              // guidance is resolved through the REAL loader from the REAL
              // shipped asset at lang 'ja', and the demo source caption is the
              // localized one production now renders — so this PNG shows exactly
              // what production delivers. (The LIVE-arm source captions are the
              // remaining English gap named in BriefingStrings' HONEST BOUND.)
              sourceCaption: 'シミュレーション予報(デモ)— オフライン・確定的',
              winterCard: WinterKnowledge.fromJsonString(
                File('assets/winter_knowledge.json').readAsStringSync(),
              ).cardFor(RoadSurfaceState.blackIce, lang: 'ja'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PretripBriefingCard),
      matchesGoldenFile('goldens/pretrip_briefing_card_ja.png'),
    );
  });

  testWidgets('renders the CAUTION-band Japanese briefing so the freezing-air '
      '/ black-ice chip register is actually seen', (tester) async {
    // The waitAdvised golden above shows only the whiteout chip. The
    // caution-band reason chips — freezingAir (black ice) and allowExtraTime —
    // carry the safety-CALIBRATION register that a single-pass review got wrong
    // (おそれがあります warning-grade vs the correct 可能性があります "possible"). observation-grade
    // binds "verified" on an observable surface to going and SEEING it, so this
    // second golden renders that band with real CJK glyphs.
    if (!fontLoaded) {
      markTestSkipped('No Noto CJK font on this host — skipping JA render.');
      return;
    }
    final issued = DateTime(2026, 1, 1, 6, 0);
    final dep = DateTime(2026, 1, 1, 7, 15);
    // A subzero, dry morning → caution verdict; worstSlot has no precip / road /
    // visibility signal, so _describe falls to the freezing-air (black ice) chip.
    final forecast = WeatherForecast(
      issuedAt: issued,
      hourly: [
        HourlyForecast(hour: DateTime(2026, 1, 1, 7), tempCelsius: -3),
        HourlyForecast(hour: DateTime(2026, 1, 1, 8), tempCelsius: -2),
      ],
    );
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['akita-commute'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = SnowAwarePretripAdvisor(messages: PretripMessages.ja)
        .brief(
          forecast: forecast,
          commute: commute,
          profile: const DriverProfileSpec(
            profileTag: 'akita',
            reactionTimeSeconds: 1.5,
          ),
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SizedBox(
            width: 560,
            child: PretripBriefingCard(
              strings: BriefingStrings.ja,
              briefing: briefing,
              commute: commute,
              forecastIssuedAt: issued,
              tripRequired: false,
              onTripRequiredChanged: (_) {},
              sourceCaption: 'シミュレーション予報(デモ)— オフライン・確定的',
              winterCard: WinterKnowledge.fromJsonString(
                File('assets/winter_knowledge.json').readAsStringSync(),
              ).cardFor(RoadSurfaceState.blackIce, lang: 'ja'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(PretripBriefingCard),
      matchesGoldenFile('goldens/pretrip_briefing_card_ja_caution.png'),
    );
  });
}
