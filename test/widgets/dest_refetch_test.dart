import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/main.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/family_area_card.dart';

/// A fully OFFLINE fake forecast provider: returns a canned [WeatherForecast]
/// and records whether it was closed (leak-hygiene assertion). Subclasses the
/// real provider so it drops into the [OfflineMapPage.destForecastProviderFactory]
/// seam unchanged.
class FakeMetProvider extends MetNorwayHourlyForecastProvider {
  FakeMetProvider(this._forecast);

  final WeatherForecast _forecast;
  bool closed = false;

  @override
  Future<WeatherForecast?> fetchForecast({
    required double latitude,
    required double longitude,
  }) async =>
      _forecast;

  @override
  void close() {
    closed = true;
    super.close();
  }
}

WeatherForecast _cannedForecast() {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(
        hour: base,
        tempCelsius: -3,
        precipitationMmPerHour: 1.0,
        visibilityMeters: 400,
        estimatedRoadCondition: RoadConditionEstimate.packedSnow,
      ),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: -1,
        precipitationMmPerHour: 0.0,
        visibilityMeters: 3000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      ),
    ],
  );
}

void main() {
  // This test exercises the live dest-area arm. Rather than gating it behind a
  // `--dart-define=PRETRIP_FORECAST=met_norway` (which made it SKIP under a plain
  // `flutter test` and in CI — leaving the _setDestination contract uncovered),
  // it injects the forecast source via the runtime [OfflineMapPage.
  // forecastSourceOverride] seam, so the full leak-hygiene + re-render +
  // anti-clobber contract is verified on every `flutter test`.
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // flutter_map's built-in tile cache calls path_provider; stub the channel so
    // it does not throw a MissingPluginException during map-view init.
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

  testWidgets(
    'HER-set destination drives a re-fetch + re-render (offline, leak-clean)',
    (tester) async {
      // ALL File I/O must run inside runAsync — the fake-async test body blocks
      // real dart:io (createTemp / read / write) otherwise.
      late Directory tmp;
      late SavedPlaceStore store;
      await tester.runAsync(() async {
        tmp = await Directory.systemTemp.createTemp('dest_refetch_test');
        store = SavedPlaceStore(File('${tmp.path}/sngnav/saved_place.json'));
      });
      addTearDown(() async {
        await tester.runAsync(() async {
          if (await tmp.exists()) await tmp.delete(recursive: true);
        });
      });

      final created = <FakeMetProvider>[];
      MetNorwayHourlyForecastProvider factory() {
        final p = FakeMetProvider(_cannedForecast());
        created.add(p);
        return p;
      }

      // Drain benign async exceptions from FlutterMap's network tile provider /
      // plugin cache (this offline test never wants real tiles); a non-benign
      // exception is rethrown so a real defect still fails the test.
      void drainBenign() {
        final ex = tester.takeException();
        if (ex == null) return;
        final s = ex.toString();
        final benign = ex is MissingPluginException ||
            s.contains('getTileUrl') ||
            s.contains('TileProvider') ||
            s.contains('flutter_map');
        if (!benign) throw ex as Object;
      }

      // The page mixes real async (File I/O in the store) with the widget tree,
      // and FlutterMap never quiesces — so pumpAndSettle is unusable. Turn the
      // real event loop with runAsync so the store's File futures complete, then
      // pump to flush the resulting (fake-zone) continuations + rebuild.
      // Each nested real-dart:io await inside the page (store create/write, etc.)
      // needs its OWN runAsync(turn real loop)+pump(flush the queued fake-zone
      // continuation) cycle, so flush runs many tight cycles.
      Future<void> flush([int cycles = 12]) async {
        for (var i = 0; i < cycles; i++) {
          await tester.runAsync(() async =>
              Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 60));
        }
        drainBenign();
      }

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('ja')],
          home: OfflineMapPage(
            savedPlaceStore: store,
            destForecastProviderFactory: factory,
            // Runtime seam: exercise the dest-area arm without a dart-define, so
            // this load-bearing test runs on a plain `flutter test` (not skipped).
            forecastSourceOverride: 'met_norway',
          ),
        ),
      );
      // Switch to the Pre-trip view IMMEDIATELY so the FlutterMap is removed
      // (disposed) rather than rebuilt — a TileLayer didUpdateWidget throws in
      // the test environment, but a disposed one does not.
      await tester.tap(find.text('Pre-trip'));
      await tester.pump();
      drainBenign();
      await flush();

      // No place configured yet ⇒ the area card is ABSENT (honest floor).
      expect(find.byType(FamilyAreaCard), findsNothing);
      expect(created, isEmpty);

      Future<void> setPlace(double lat, double lon, String label) async {
        final editIcon = find.byIcon(Icons.edit_outlined).first;
        await tester.ensureVisible(editIcon); // tile may be below the scroll fold
        await tester.pump();
        await tester.tap(editIcon);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350)); // dialog in
        // Ensure coordinates mode (idempotent when already there on edit).
        await tester.tap(find.text(BriefingStrings.en.placeEntryModeCoordinates));
        await tester.pump();
        await tester.enterText(
            find.widgetWithText(
                TextFormField, BriefingStrings.en.placeEntryLatLabel),
            '$lat');
        await tester.enterText(
            find.widgetWithText(
                TextFormField, BriefingStrings.en.placeEntryLonLabel),
            '$lon');
        // The label field is the only plain TextField (lat/lon are
        // TextFormField); match it by its always-rendered floating label so the
        // finder survives a pre-filled (edit) state.
        await tester.enterText(
            find.widgetWithText(
                TextField, BriefingStrings.en.placeEntryLabelLabel),
            label);
        await tester.pump();
        await tester.tap(find.text(BriefingStrings.en.placeEntrySave));
        await tester.pump(); // pop + _setDestination begins (awaits File I/O)
        await flush(); // dialog pop + store.save complete
        await flush(); // re-fetch + setState lands
      }

      // --- HER sets place A (coordinates, non-Japan point) ------------------
      await setPlace(60.0, 10.0, 'Area A');
      expect(created, hasLength(1));
      expect(created[0].closed, isFalse); // still the active provider
      expect(find.byType(FamilyAreaCard), findsOneWidget);
      expect(find.textContaining('Area A'), findsWidgets);

      // --- HER changes to place B ⇒ prior provider CLOSED before re-fetch ----
      await setPlace(61.0, 11.0, 'Area B');
      expect(created, hasLength(2));
      expect(created[0].closed, isTrue,
          reason: 'the prior dest provider must be closed before the re-fetch');
      expect(created[1].closed, isFalse);
      expect(find.byType(FamilyAreaCard), findsOneWidget);
      expect(find.textContaining('Area B'), findsWidgets);

      drainBenign();
    },
  );
}
