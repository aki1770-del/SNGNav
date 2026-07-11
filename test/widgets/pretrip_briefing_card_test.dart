import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

void main() {
  final dep = DateTime(2026, 1, 1, 7, 15);
  final issued = DateTime(2026, 1, 1, 6, 0);

  // Hazard fixtures stay subzero; clear fixtures pass a temp above the frost
  // band (subzero dry air is caution class since the 2026-06-12 quant fix).
  HourlyForecast slot(
    int hour, {
    double temp = -3,
    double? vis,
    double? precip,
  }) => HourlyForecast(
    hour: DateTime(2026, 1, 1, hour),
    tempCelsius: temp,
    precipitationMmPerHour: precip,
    visibilityMeters: vis,
  );

  CommuteShape commuteOf(CommuteFlexibility flexibility) => CommuteShape(
    plannedDeparture: dep,
    plannedDuration: const Duration(minutes: 30),
    routeIdentifiers: const ['r1'],
    flexibility: flexibility,
  );

  const profile = DriverProfileSpec(
    profileTag: 'test',
    reactionTimeSeconds: 1.5,
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<HourlyForecast> hourly,
    required CommuteFlexibility flexibility,
    ValueChanged<bool>? onChanged,
    BriefingStrings strings = BriefingStrings.en,
  }) async {
    const advisor = SnowAwarePretripAdvisor();
    final commute = commuteOf(flexibility);
    final briefing = advisor.brief(
      forecast: WeatherForecast(hourly: hourly, issuedAt: issued),
      commute: commute,
      profile: profile,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PretripBriefingCard(
            strings: strings,
            briefing: briefing,
            commute: commute,
            forecastIssuedAt: issued,
            tripRequired: flexibility == CommuteFlexibility.required,
            onTripRequiredChanged: onChanged ?? (_) {},
            sourceCaption: 'Simulated forecast (test)',
          ),
        ),
      ),
    );
  }

  testWidgets('clear forecast shows the clear verdict and checklist', (
    tester,
  ) async {
    await pumpCard(
      tester,
      hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
      flexibility: CommuteFlexibility.discretionary,
    );
    expect(find.textContaining('Conditions look clear'), findsOneWidget);
    expect(find.text('Before you leave'), findsOneWidget);
    expect(find.textContaining('Whiteout plan'), findsOneWidget);
  });

  testWidgets('whiteout + clear-later shows a wait verdict with the delay', (
    tester,
  ) async {
    await pumpCard(
      tester,
      hourly: [
        slot(7, vis: 80, precip: 3),
        slot(8, vis: 250, precip: 1),
        slot(9, vis: 5000),
        slot(10, vis: 8000),
      ],
      flexibility: CommuteFlexibility.discretionary,
    );
    expect(find.textContaining('Consider waiting about 2 h'), findsOneWidget);
    expect(find.textContaining('whiteout'), findsWidgets);
  });

  testWidgets('required trip shows the honesty-mode verdict', (tester) async {
    await pumpCard(
      tester,
      hourly: [
        slot(7, vis: 80, precip: 3),
        slot(8, vis: 250, precip: 1),
        slot(9, vis: 5000),
        slot(10, vis: 8000),
      ],
      flexibility: CommuteFlexibility.required,
    );
    expect(
      find.textContaining('Your call — trip is marked required'),
      findsOneWidget,
    );
    // No delay urged anywhere on the card.
    expect(find.textContaining('Consider waiting'), findsNothing);
  });

  testWidgets('trip-required switch reports toggles', (tester) async {
    bool? toggled;
    await pumpCard(
      tester,
      hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
      flexibility: CommuteFlexibility.discretionary,
      onChanged: (v) => toggled = v,
    );
    await tester.tap(find.byType(Switch));
    expect(toggled, isTrue);
  });

  // The optional winter-knowledge card renders the grounded action bullets
  // when present, and is omitted entirely (honest degradation) when absent.
  Future<void> pumpWithWinter(WidgetTester tester, WinterCard? card) async {
    const advisor = SnowAwarePretripAdvisor();
    final commute = commuteOf(CommuteFlexibility.discretionary);
    final briefing = advisor.brief(
      forecast: WeatherForecast(
        hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
        issuedAt: issued,
      ),
      commute: commute,
      profile: profile,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PretripBriefingCard(
            briefing: briefing,
            commute: commute,
            forecastIssuedAt: issued,
            tripRequired: false,
            onTripRequiredChanged: (_) {},
            sourceCaption: 'Simulated forecast (test)',
            winterCard: card,
          ),
        ),
      ),
    );
  }

  testWidgets('winter card renders grounded action bullets when present', (
    tester,
  ) async {
    await pumpWithWinter(
      tester,
      const WinterCard(
        state: 'blackIce',
        guidance:
            '# Black Ice\n\n**ACTIONABLE STEPS:**\n\n'
            '• **Reduce speed significantly** — drive well below normal\n'
            '• **Increase following distance** — 5–6 seconds',
      ),
    );
    expect(find.textContaining('If the road is black ice'), findsOneWidget);
    expect(find.textContaining('Reduce speed significantly'), findsOneWidget);
    expect(find.textContaining('Increase following distance'), findsOneWidget);
    // Markdown markup is stripped, not shown raw.
    expect(find.textContaining('**'), findsNothing);
    expect(find.textContaining('CC BY-SA'), findsOneWidget);
  });

  testWidgets('no winter card → no winter section (honest degradation)', (
    tester,
  ) async {
    await pumpWithWinter(tester, null);
    expect(find.textContaining('If the road is'), findsNothing);
    expect(find.textContaining('CC BY-SA'), findsNothing);
    // The typed checklist still stands.
    expect(find.textContaining('Whiteout plan'), findsOneWidget);
  });

  testWidgets(
    'verdict banner announces severity then headline to assistive tech',
    (tester) async {
      final handle = tester.ensureSemantics();
      // A whiteout-now, clear-later window → a strong wait/hazard verdict.
      await pumpCard(
        tester,
        hourly: [
          slot(7, vis: 80, precip: 3),
          slot(8, vis: 250, precip: 1),
          slot(9, vis: 5000),
          slot(10, vis: 8000),
        ],
        flexibility: CommuteFlexibility.discretionary,
      );
      // Severity is carried visually only by colour; for a screen-reader user it
      // is announced as a word first, then the full headline, so the safety
      // signal is never colour-only.
      expect(
        find.bySemanticsLabel(
          RegExp(r'Pre-trip safety briefing\. Hazard\. Consider waiting'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  testWidgets(
    'clear verdict announces the "Clear" severity word to assistive tech',
    (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
        flexibility: CommuteFlexibility.discretionary,
      );
      expect(
        find.bySemanticsLabel(RegExp(r'Pre-trip safety briefing\. Clear\.')),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  // Restraint regression: when the forecast does not cover the departure
  // window, the card must degrade honestly to "use your own judgment" — never
  // a fabricated all-clear — and announce the honest severity to assistive
  // tech. Pins the honest-null behaviour so it cannot silently regress.
  testWidgets(
    'no-coverage forecast degrades to honest noData, not a false clear',
    (tester) async {
      final handle = tester.ensureSemantics();
      // Forecast covers only the evening — nothing for the 07:15 departure.
      await pumpCard(
        tester,
        hourly: [slot(20, vis: 8000), slot(21, vis: 8000)],
        flexibility: CommuteFlexibility.discretionary,
      );
      expect(find.textContaining('use your own judgment'), findsOneWidget);
      expect(find.textContaining('Conditions look clear'), findsNothing);
      // Severity announced as the honest "Information needed", never "Clear".
      expect(
        find.bySemanticsLabel(
          RegExp(r'Pre-trip safety briefing\. Information needed\.'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    },
  );

  // Reach-fix for language: HER mother in Akita reads Japanese. The safety
  // verdict, the checklist, and the assistive-tech announcement must all reach
  // her in her own language — a verdict she cannot read does not reach her.
  group('Japanese (ja) localization', () {
    testWidgets('clear forecast renders the Japanese verdict and checklist', (
      tester,
    ) async {
      await pumpCard(
        tester,
        hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
        flexibility: CommuteFlexibility.discretionary,
        strings: BriefingStrings.ja,
      );
      expect(find.text('出発前に'), findsOneWidget);
      expect(find.textContaining('良好な見込み'), findsOneWidget);
      expect(find.text('出発前の準備'), findsOneWidget);
      // The JAF whiteout-plan checklist line, in Japanese.
      expect(find.textContaining('ホワイトアウト'), findsOneWidget);
      // No English headline leaked through.
      expect(find.textContaining('Conditions look clear'), findsNothing);
    });

    testWidgets('hazard headline localizes the delay and the hazard clause', (
      tester,
    ) async {
      await pumpCard(
        tester,
        hourly: [
          slot(7, vis: 80, precip: 3),
          slot(8, vis: 250, precip: 1),
          slot(9, vis: 5000),
          slot(10, vis: 8000),
        ],
        flexibility: CommuteFlexibility.discretionary,
        strings: BriefingStrings.ja,
      );
      // "Consider waiting about 2 h" → "約2時間…待つことを検討してください".
      expect(find.textContaining('約2時間'), findsOneWidget);
      expect(find.textContaining('待つことを検討'), findsOneWidget);
      expect(find.textContaining('Consider waiting'), findsNothing);
    });

    testWidgets(
      'assistive tech hears the Japanese severity word then headline',
      (tester) async {
        final handle = tester.ensureSemantics();
        await pumpCard(
          tester,
          hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
          flexibility: CommuteFlexibility.discretionary,
          strings: BriefingStrings.ja,
        );
        // Severity word first ("良好"), then the headline — colour-encoded
        // severity is never the only carrier of the signal, in Japanese too.
        expect(
          find.bySemanticsLabel(RegExp(r'出発前の安全ブリーフィング。良好。')),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    testWidgets(
      'honest-null degrades to the Japanese "use your own judgment"',
      (tester) async {
        // Forecast covers only the evening — nothing for the 07:15 departure.
        await pumpCard(
          tester,
          hourly: [slot(20, vis: 8000), slot(21, vis: 8000)],
          flexibility: CommuteFlexibility.discretionary,
          strings: BriefingStrings.ja,
        );
        expect(find.textContaining('ご自身の判断で'), findsOneWidget);
        expect(find.textContaining('良好な見込み'), findsNothing);
      },
    );
  });

  // Locale resolution: ja → Japanese table, everything else → English fallback,
  // and an unsupported language never throws (it degrades to English, never to
  // no surface).
  test('BriefingStrings.of resolves locale, falling back to English', () {
    expect(BriefingStrings.of(const Locale('ja')), same(BriefingStrings.ja));
    expect(BriefingStrings.of(const Locale('en')), same(BriefingStrings.en));
    expect(BriefingStrings.of(const Locale('fr')), same(BriefingStrings.en));
  });
}
