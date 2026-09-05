/// REACH test: the driver must SEE the JMA partial-read (border-incomplete) caution.
///
/// THE GAP this guards: at a border, the `condition_aggregator_jma` package
/// returns the reachable prefecture's REAL warning ALONGSIDE a synthetic in-band
/// incomplete-read notice (`eventClass == kJmaIncompleteReadEventClass`) naming
/// the unreachable sibling (秋田県, which could be holding a 大雪特別警報). The app
/// used to DROP that notice — a mild reachable 着雪注意報 reached the driver dressed as a
/// COMPLETE warning check. This test pumps the SHIPPED [PretripScreen], injects
/// that exact advisory list through the JMA test seam, and proves the driver's mother's
/// family-thread surface now shows BOTH the real warning AND an honest caution
/// naming 秋田県 — and that a CLEAN complete read shows NO such caution.
///
/// Network IO is injected: the MET base via [destForecastProviderFactory], the
/// JMA advisories via [jmaAdvisoryFetchOverride]. No socket, no fixtures.
///
/// AGAINST THE UNFIXED (drop-the-notice) CODE THIS TEST FAILS: there is no
/// `jmaBorderCheckIncomplete` flag, nothing carries 秋田県 to the widget, and the
/// caution is never rendered — so the first `expect(... findsOneWidget)` fails.
library;

import 'dart:io';

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_screen.dart';

/// A fully OFFLINE fake forecast provider: returns a canned [WeatherForecast]
/// covering "now" so the destination-area read is forecast-covered. Subclasses
/// the real provider so it drops into the [PretripScreen.destForecastProviderFactory]
/// seam unchanged.
class FakeMetProvider extends MetNorwayHourlyForecastProvider {
  FakeMetProvider(this._forecast);

  final WeatherForecast _forecast;

  @override
  Future<WeatherForecast?> fetchForecast({
    required double latitude,
    required double longitude,
  }) async => _forecast;
}

WeatherForecast _cannedTempOnly() {
  // Temp-only base (exactly what the MET Norway compact product gives Japan):
  // null road condition + null visibility, so the JMA band has a slot to fill.
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(
        hour: base,
        tempCelsius: -2,
        precipitationMmPerHour: 0.5,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: -2,
        precipitationMmPerHour: 0.5,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
    ],
  );
}

Advisory _adv(String eventClass) => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: eventClass,
  severity: AdvisorySeverity.moderate,
  certainty: AdvisoryCertainty.observed,
  urgency: AdvisoryUrgency.immediate,
  areaDescription: '秋田県',
  effective: null,
  expires: null,
  headline: eventClass,
  description: eventClass,
);

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => Directory.systemTemp.path,
    );
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
  });

  /// Pumps the shipped [PretripScreen] for the driver's mother's Akita border area,
  /// seeding a saved place and injecting [jmaAdvisories] through the JMA seam.
  /// Returns nothing — the caller asserts on the rendered tree.
  Future<void> pumpForAkita(
    WidgetTester tester, {
    required List<Advisory> jmaAdvisories,
  }) async {
    late Directory tmp;
    late SavedPlaceStore store;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('border_incomplete_test');
      store = SavedPlaceStore(File('${tmp.path}/sngnav/saved_place.json'));
      // Seed the driver's mother's area (Akita, 39.72/140.10 → JMA snow-zone) so the
      // family-thread read fires from initState with no dialog interaction.
      await store.save(
        const SavedPlace(lat: 39.72, lon: 140.10, label: '母の地域'),
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
    });

    Future<void> flush([int cycles = 12]) async {
      for (var i = 0; i < cycles; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
      }
      // No FlutterMap in PretripScreen, but drain any benign plugin exception.
      final ex = tester.takeException();
      if (ex != null && ex is! MissingPluginException) throw ex as Object;
    }

    await tester.pumpWidget(
      MaterialApp(
        // the driver's mother reads Japanese — pin the locale so we verify the surface
        // SHE actually sees.
        locale: const Locale('ja'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Scaffold(
          body: PretripScreen(
            savedPlaceStore: store,
            destForecastProviderFactory: () =>
                FakeMetProvider(_cannedTempOnly()),
            forecastSourceOverride: 'met_norway',
            jmaAdvisoryFetchOverride:
                ({required double latitude, required double longitude}) async =>
                    jmaAdvisories,
            surfaceState: RoadSurfaceState.compactedSnow,
          ),
        ),
      ),
    );
    await tester.pump();
    await flush();
  }

  testWidgets(
    'PARTIAL border read: the driver sees the 秋田県 caution AND the real 着雪注意報',
    (tester) async {
      await pumpForAkita(
        tester,
        jmaAdvisories: [
          _adv('着雪注意報'), // reachable, real → merged + surfaced
          buildIncompleteReadNotice(const ['050000']), // 秋田県 unreachable
        ],
      );

      // 1) The partial-read caution REACHES the driver, naming the unreachable area.
      expect(
        find.byKey(const Key('pretrip-border-incomplete-caution')),
        findsOneWidget,
      );
      expect(
        find.textContaining('秋田県の警報を確認できませんでした'),
        findsOneWidget,
        reason: 'the driver must see the honest partial-read caution naming 秋田県',
      );

      // 2) The REAL warning is STILL surfaced (both honoured — never hidden by
      //    the notice).
      expect(
        find.textContaining('着雪注意報'),
        findsWidgets,
        reason: 'the reachable real warning must still reach the driver',
      );
    },
  );

  testWidgets('COMPLETE read: real warning shown, NO partial-read caution', (
    tester,
  ) async {
    await pumpForAkita(
      tester,
      jmaAdvisories: [_adv('着雪注意報')], // clean, complete — no notice
    );

    // The real warning still reaches the driver...
    expect(find.textContaining('着雪注意報'), findsWidgets);
    // ...and NO false caution is shown (a complete check stays clean).
    expect(
      find.byKey(const Key('pretrip-border-incomplete-caution')),
      findsNothing,
    );
    expect(find.textContaining('確認できませんでした'), findsNothing);
  });
}
