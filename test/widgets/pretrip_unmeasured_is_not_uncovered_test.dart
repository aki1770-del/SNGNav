/// REACH tests: **an unmeasured morning is not the same absence as no forecast
/// at all**, and HER card must never say the wrong one.
///
/// `pretrip_decision_advisor` 0.6.1 refuses the affirmative all-clear it did
/// not measure: `brief()` throws `PretripAssessmentIncompleteException` when a
/// forecast DOES cover the departure window but the fields that decide the
/// winter-hazard ladder were never measured. Published 0.6.0 printed
/// 「出発時間帯に冬季の危険を示す兆候はありません」 on exactly that morning — a
/// sentence produced BY the absence of evidence.
///
/// The app is the other half of that fix. Two absences arrive at this screen
/// and they are NOT interchangeable:
///
///   A  a forecast EXISTS, and it measured nothing that decides
///   B  no forecast covers the window at all
///
/// Both land as `PretripVerdict.noData`, so the card cannot tell them apart
/// from the verdict. `allClearEarned` cannot either — it returns `false` for
/// both (`window.isEmpty` returns `false` on the same line an unmeasured
/// window does). Only the typed catch discriminates. Rendering
/// [BriefingStrings.headlineNoData] — 「出発時間帯の予報がありません」, *there is
/// no forecast* — in case A would be a NEW false sentence produced by absence,
/// in the HEADLINE, which is read first and announced first to assistive tech.
/// That is the same defect class 0.6.1 exists to close, moved somewhere larger.
///
/// Fail-then-pass: probes P1/P2/P3 FAIL before the app-side catch (the
/// exception escapes `PretripScreen.build`); controls C1/C2 PASS both before
/// and after, and C1 is what proves the fix did not simply collapse A into B.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_screen.dart';

/// CASE A — a forecast that COVERS the window and measured only temperature.
///
/// Not a contrived shape: `pretrip_source_met_norway` emits
/// `visibilityMeters: null` and `estimatedRoadCondition: null` on EVERY slot
/// by its own honesty rule, so on that source this is the DEFAULT morning.
///
/// 5 °C, and nothing else. The temperature is REAL data and it is measured —
/// it simply decides nothing here: it is above the frost band (0 °C), above
/// the cold-rain band (2 °C) and above the radiative-frost ceiling (3 °C), so
/// every rung of the ladder is either not applicable or reads a field that is
/// absent. The slot falls through every test and lands on `clear` having
/// decided NOTHING. That is the morning 0.6.0 called an all-clear.
///
/// Measured 2026-08-28, and worth stating because it shows the gate is tight
/// rather than blanket: the SAME slot at −2 °C does NOT throw — subzero air is
/// itself evidence, `hazardOf` returns caution from the temperature alone, and
/// the card correctly says so. The refusal fires only where nothing was
/// decided.
WeatherForecast _unmeasured() {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(hour: base, tempCelsius: 5),
      HourlyForecast(hour: base.add(const Duration(hours: 1)), tempCelsius: 5),
    ],
  );
}

/// CASE B — a forecast that exists but covers NOTHING near the departure.
/// Half a day away, so no slot overlaps the window.
WeatherForecast _uncovered() {
  final base = DateTime.now().add(const Duration(hours: 12));
  return WeatherForecast(
    issuedAt: DateTime.now(),
    hourly: [
      HourlyForecast(
        hour: base,
        tempCelsius: -2,
        humidityRH: 60,
        precipitationMmPerHour: 0,
        visibilityMeters: 8000,
        estimatedRoadCondition: RoadConditionEstimate.dry,
      ),
    ],
  );
}

/// CASE C — every field the ladder reads is MEASURED, and benign. The
/// all-clear is EARNED here, so it is still said. 4 °C is above the
/// radiative-frost ambient ceiling (3 °C) and above the cold-rain band
/// (2 °C), so nothing is left undecided.
WeatherForecast _measuredBenign() {
  final base = DateTime.now();
  HourlyForecast at(DateTime h) => HourlyForecast(
    hour: h,
    tempCelsius: 4,
    humidityRH: 60,
    precipitationMmPerHour: 0,
    visibilityMeters: 8000,
    estimatedRoadCondition: RoadConditionEstimate.dry,
  );
  return WeatherForecast(
    issuedAt: base,
    hourly: [at(base), at(base.add(const Duration(hours: 1)))],
  );
}

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

  /// Turns the real event loop so the injected live-forecast future lands,
  /// then flushes the rebuild. Rethrows anything that escaped the widget tree
  /// — a `PretripAssessmentIncompleteException` reaching here IS the defect.
  Future<void> flush(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }
    final ex = tester.takeException();
    if (ex != null && ex is! MissingPluginException) throw ex as Object;
  }

  /// Pumps the shipped [PretripScreen] on the ja surface — the one HER mother
  /// in Akita reads — with the live forecast injected. No socket.
  Future<void> pumpScreen(
    WidgetTester tester,
    WeatherForecast forecast, {
    Locale locale = const Locale('ja'),
  }) async {
    late Directory tmp;
    late SavedPlaceStore store;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('unmeasured_test');
      store = SavedPlaceStore(File('${tmp.path}/sngnav/saved_place.json'));
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
    });

    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ja')],
        home: Scaffold(
          body: PretripScreen(
            savedPlaceStore: store,
            metForecastFetchOverride: () async => forecast,
            surfaceState: RoadSurfaceState.compactedSnow,
          ),
        ),
      ),
    );
    await tester.pump();
    await flush(tester);
  }

  const ja = BriefingStrings.ja;
  const en = BriefingStrings.en;

  // ── P1 ─────────────────────────────────────────────────────────────────
  // The screen must SURVIVE the refusal. Before the app-side catch the
  // exception escapes `PretripScreen.build` and `flush` rethrows it: HER card
  // is not merely wrong, it is absent — a red error box where the briefing was.
  testWidgets(
    'P1 an unmeasured morning renders a card at all — the refusal never '
    'reaches HER as a crashed screen',
    (tester) async {
      await pumpScreen(tester, _unmeasured());
      expect(find.text(ja.beforeYouDrive), findsOneWidget);
    },
  );

  // ── P2 ─────────────────────────────────────────────────────────────────
  // The banner says 「情報が必要」 and the package's own chip says WHAT was not
  // measured. No new sentence is authored for this state: both strings already
  // shipped, in both languages.
  testWidgets(
    'P2 an unmeasured morning says 情報が必要 and names what was not measured',
    (tester) async {
      await pumpScreen(tester, _unmeasured());

      expect(
        find.text(ja.severityInformationNeeded),
        findsOneWidget,
        reason: 'the banner must carry the honest severity word',
      );
      expect(
        find.textContaining('判定できませんでした'),
        findsOneWidget,
        reason: "the package's assessmentIncomplete() chip must reach HER",
      );
      expect(
        find.textContaining('危険がないという意味ではありません'),
        findsOneWidget,
        reason: 'the chip must say plainly that this is not an all-clear',
      );
    },
  );

  // ── P3 ─────────────────────────────────────────────────────────────────
  // THE ANTI-COLLAPSE PROBE. This is the one that fails under
  // `briefOrUnassessed()`-instead-of-catch: that seam returns
  // `verdict: noData` for BOTH absences, the card switches on the verdict
  // alone, and case A renders 「出発時間帯の予報がありません」 — *there is no
  // forecast* — on a morning a forecast DID arrive.
  testWidgets(
    'P3 an unmeasured morning NEVER says 予報がありません — a forecast DID arrive',
    (tester) async {
      await pumpScreen(tester, _unmeasured());

      expect(
        find.text(ja.headlineNoData),
        findsNothing,
        reason: 'a forecast arrived; saying none did is a false sentence',
      );
      expect(
        find.textContaining('兆候はありません'),
        findsNothing,
        reason: 'the 0.6.0 fabricated all-clear must not return',
      );
      expect(
        find.text(ja.headlineClear),
        findsNothing,
        reason: 'nothing was measured, so nothing is clear',
      );
    },
  );

  // Same discrimination on the English surface — the edge developer who ships
  // this card in en must get the same honesty HER mother gets in ja.
  testWidgets('P3en the English surface discriminates identically', (
    tester,
  ) async {
    await pumpScreen(tester, _unmeasured(), locale: const Locale('en'));
    expect(find.text(en.severityInformationNeeded), findsOneWidget);
    expect(find.text(en.headlineNoData), findsNothing);
    expect(find.textContaining('No winter hazard signals'), findsNothing);
  });

  // ── C1 ─────────────────────────────────────────────────────────────────
  // CONTROL, passes BEFORE and AFTER. Case B is untouched: when no forecast
  // covers the window, 「予報がありません」 is TRUE and must still be said. If a
  // fix ever collapses A into B this control keeps passing while P3 fails —
  // and if a fix collapses B into A, THIS one fails. The pair is the loom.
  testWidgets(
    'C1 CONTROL — no forecast covering the window still says 予報がありません',
    (tester) async {
      await pumpScreen(tester, _uncovered());

      expect(find.text(ja.headlineNoData), findsOneWidget);
      expect(
        find.textContaining('判定できませんでした'),
        findsNothing,
        reason: 'nothing was covered, so nothing was left half-measured',
      );
    },
  );

  // ── C2 ─────────────────────────────────────────────────────────────────
  // CONTROL, passes BEFORE and AFTER. The gate withholds ONLY the unearned
  // all-clear. A morning that measured everything and found nothing wrong
  // still gets its all-clear — otherwise the fix would have made the card
  // useless on the days it works.
  testWidgets(
    'C2 CONTROL — a fully measured benign morning still earns its all-clear',
    (tester) async {
      await pumpScreen(tester, _measuredBenign());

      expect(find.text(ja.headlineClear), findsOneWidget);
      expect(find.text(ja.severityInformationNeeded), findsNothing);
      // The severity word is not DRAWN anywhere — the card carries it only in
      // the banner's semantics label (measured 2026-08-28). Assert it where it
      // actually lives, so this control cannot pass by looking at nothing.
      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp('。${ja.severityClear}。')),
        findsOneWidget,
      );
      handle.dispose();
    },
  );
}
