/// REACH test: HER must SEE an in-force JMA turmoil-class warning
/// (0.4.0 widening: 大雨 / 暴風・強風 / 雷 / 濃霧) on the pre-trip briefing.
///
/// THE GAP this guards: from `condition_aggregator_jma` 0.4.0 the adapter
/// surfaces the non-snow turmoil classes (e.g. a 大雨危険警報 during a summer
/// downpour), but the app's pre-trip lane only consumed the snow classes
/// (road-condition merge) — a fetched in-force 大雨危険警報 was silently
/// dropped between the adapter and HER while the caption said "no active
/// winter warning" (true, but the warning she needed never rendered). This
/// test pumps the SHIPPED [PretripScreen] at an Akita point, injects the
/// turmoil advisories through the JMA seam, and proves they REACH the tree
/// verbatim — highest severity first — and that the card never renders when
/// nothing is in force.
///
/// Network IO is injected: the current-location MET base via
/// [PretripScreen.metForecastFetchOverride], the JMA advisories via
/// [PretripScreen.jmaAdvisoryFetchOverride], the Akita routing via
/// [PretripScreen.pretripPointOverride]. No socket, no `--dart-define`.
///
/// AGAINST THE UNFIXED (drop-the-turmoil) CODE THIS TEST FAILS: nothing
/// carries the advisories to the widget and the card is never rendered — the
/// first `expect(... findsOneWidget)` fails.
library;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_screen.dart';

WeatherForecast _cannedTempOnly() {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(
        hour: base,
        tempCelsius: 18,
        precipitationMmPerHour: 4.0,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: 18,
        precipitationMmPerHour: 4.0,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
    ],
  );
}

Advisory _adv(String eventClass, AdvisorySeverity severity) => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: eventClass,
  severity: severity,
  certainty: AdvisoryCertainty.observed,
  urgency: AdvisoryUrgency.immediate,
  areaDescription: '秋田県',
  effective: null,
  expires: null,
  headline: eventClass,
  description: eventClass,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Pumps the shipped [PretripScreen] with the CURRENT location pinned to
  /// Akita (JMA snow-zone routing) and [jmaAdvisories] injected through the
  /// JMA seam. No saved place is seeded — the destination lane stays idle, so
  /// every assertion below reads the CURRENT-LOCATION briefing lane.
  Future<void> pumpAtAkita(
    WidgetTester tester, {
    required List<Advisory> jmaAdvisories,
  }) async {
    Future<void> flush([int cycles = 12]) async {
      for (var i = 0; i < cycles; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      final ex = tester.takeException();
      if (ex != null) throw ex as Object;
    }

    await tester.pumpWidget(
      MaterialApp(
        // HER reads Japanese — pin the locale so we verify the surface SHE
        // actually sees.
        locale: const Locale('ja'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Scaffold(
          body: PretripScreen(
            pretripPointOverride: (lat: 39.72, lon: 140.10), // Akita
            metForecastFetchOverride: () async => _cannedTempOnly(),
            jmaAdvisoryFetchOverride:
                ({required double latitude, required double longitude}) async =>
                    jmaAdvisories,
            surfaceState: RoadSurfaceState.dry,
          ),
        ),
      ),
    );
    await tester.pump();
    await flush();
  }

  testWidgets('in-force 大雨危険警報 + 強風注意報 REACH HER verbatim, highest severity '
      'first, with the verbatim-relay honesty note', (tester) async {
    await pumpAtAkita(
      tester,
      jmaAdvisories: [
        // Moderate FIRST in fetch order — the lane must show extreme first.
        _adv('強風注意報', AdvisorySeverity.moderate),
        _adv('大雨危険警報', AdvisorySeverity.extreme),
      ],
    );

    expect(
      find.byKey(const Key('pretrip-jma-turmoil-warnings')),
      findsOneWidget,
    );
    // Verbatim relay (Article 17 β): JMA's own words, prefecture-labeled.
    expect(find.text('大雨危険警報（秋田県）'), findsOneWidget);
    expect(find.text('強風注意報（秋田県）'), findsOneWidget);
    // Highest severity renders ABOVE: the extreme card row precedes the
    // moderate one in the rendered tree.
    final kikenY = tester.getTopLeft(find.text('大雨危険警報（秋田県）')).dy;
    final kyoufuuY = tester.getTopLeft(find.text('強風注意報（秋田県）')).dy;
    expect(
      kikenY,
      lessThan(kyoufuuY),
      reason: 'the extreme 危険警報 must render above the 注意報',
    );
    // The honesty note: verbatim wording, prefecture-level scope.
    expect(find.textContaining('気象庁の発表をそのまま表示しています'), findsOneWidget);
  });

  testWidgets(
    'no in-force warning → NO turmoil card (never an empty warning frame)',
    (tester) async {
      await pumpAtAkita(tester, jmaAdvisories: const []);
      expect(
        find.byKey(const Key('pretrip-jma-turmoil-warnings')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'a snow-class warning alone rides the road-condition lane, NOT the '
    'turmoil card',
    (tester) async {
      await pumpAtAkita(
        tester,
        jmaAdvisories: [_adv('大雪警報', AdvisorySeverity.severe)],
      );
      expect(
        find.byKey(const Key('pretrip-jma-turmoil-warnings')),
        findsNothing,
      );
    },
  );
}
