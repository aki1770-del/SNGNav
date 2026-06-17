import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

void main() {
  final dep = DateTime(2026, 1, 1, 7, 15);
  final issued = DateTime(2026, 1, 1, 6, 0);

  // Hazard fixtures stay subzero; clear fixtures pass a temp above the frost
  // band (subzero dry air is caution class since the 2026-06-12 quant fix).
  HourlyForecast slot(int hour, {double temp = -3, double? vis, double? precip}) =>
      HourlyForecast(
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

  const profile =
      DriverProfileSpec(profileTag: 'test', reactionTimeSeconds: 1.5);

  Future<void> pumpCard(
    WidgetTester tester, {
    required List<HourlyForecast> hourly,
    required CommuteFlexibility flexibility,
    ValueChanged<bool>? onChanged,
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

  testWidgets('clear forecast shows the clear verdict and checklist',
      (tester) async {
    await pumpCard(
      tester,
      hourly: [slot(7, temp: 3, vis: 8000), slot(8, temp: 3, vis: 8000)],
      flexibility: CommuteFlexibility.discretionary,
    );
    expect(
      find.textContaining('Conditions look clear'),
      findsOneWidget,
    );
    expect(find.text('Before you leave'), findsOneWidget);
    expect(
      find.textContaining('Whiteout plan'),
      findsOneWidget,
    );
  });

  testWidgets('whiteout + clear-later shows a wait verdict with the delay',
      (tester) async {
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

  testWidgets('winter card renders grounded action bullets when present',
      (tester) async {
    await pumpWithWinter(
      tester,
      const WinterCard(
        state: 'blackIce',
        guidance: '# Black Ice\n\n**ACTIONABLE STEPS:**\n\n'
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

  testWidgets('no winter card → no winter section (honest degradation)',
      (tester) async {
    await pumpWithWinter(tester, null);
    expect(find.textContaining('If the road is'), findsNothing);
    expect(find.textContaining('CC BY-SA'), findsNothing);
    // The typed checklist still stands.
    expect(find.textContaining('Whiteout plan'), findsOneWidget);
  });
}
