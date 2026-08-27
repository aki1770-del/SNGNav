import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/place_entry_dialog.dart';

/// WIDGET — the place-entry dialog + tile.
void main() {
  // A host that opens the dialog and records its result, so the full
  // [showPlaceEntryDialog] flow (incl. Navigator.pop) is exercised.
  Widget host(
    BriefingStrings strings,
    Locale locale,
    void Function(SavedPlace?) onResult,
  ) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en'), Locale('ja')],
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final r = await showPlaceEntryDialog(context, strings: strings);
              onResult(r);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  group('prefecture mode picks Akita 050000', () {
    Future<void> run(
      WidgetTester tester,
      BriefingStrings strings,
      Locale locale,
      String akitaLabel,
    ) async {
      SavedPlace? result;
      var called = false;
      await tester.pumpWidget(
        host(strings, locale, (r) {
          result = r;
          called = true;
        }),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Open the prefecture dropdown and select Akita.
      await tester.tap(find.byType(DropdownButton<String>));
      await tester.pumpAndSettle();

      // The curated JMA prefecture list is NOT a fixed length. It grew from 6
      // entries to 13 when Hokkaido's single '010000' office was split into its
      // 8 sub-offices, which moved Akita ('050000') from the 4th row to the
      // 11th — past the bottom of the opened menu's first screenful. A bare
      // `tap(find.text(akitaLabel).last)` then landed on the dropdown route's
      // modal barrier instead of the row, and the dialog never received a
      // selection.
      //
      // That made this test assert "Akita happens to sit near the top of the
      // list", which is not what its name claims. Scroll the menu to the row
      // first, so what is asserted is the thing that matters to the driver:
      // she CAN reach Akita and select it, wherever the list has grown to.
      final menu = find
          .byType(Scrollable)
          .last; // the just-opened dropdown menu
      final akitaRow = find.text(akitaLabel).last;
      await tester.scrollUntilVisible(akitaRow, 120, scrollable: menu);
      await tester.pumpAndSettle();
      await tester.ensureVisible(akitaRow);
      await tester.pumpAndSettle();
      await tester.tap(akitaRow);
      await tester.pumpAndSettle();

      // Save.
      await tester.tap(find.text(strings.placeEntrySave));
      await tester.pumpAndSettle();

      expect(called, isTrue);
      expect(result, isNotNull);
      expect(result!.lat, closeTo(39.69, 0.01));
      expect(result!.lon, closeTo(140.34, 0.01));
      expect(result!.label, akitaLabel);
    }

    testWidgets('en -> Akita', (tester) async {
      await run(tester, BriefingStrings.en, const Locale('en'), 'Akita');
    });

    testWidgets('ja -> 秋田県', (tester) async {
      await run(tester, BriefingStrings.ja, const Locale('ja'), '秋田県');
    });
  });

  testWidgets('typed mode valid coords -> SavedPlace', (tester) async {
    SavedPlace? result;
    await tester.pumpWidget(
      host(BriefingStrings.en, const Locale('en'), (r) => result = r),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(BriefingStrings.en.placeEntryModeCoordinates));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, BriefingStrings.en.placeEntryLatLabel),
      '39.69',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, BriefingStrings.en.placeEntryLonLabel),
      '140.34',
    );
    await tester.tap(find.text(BriefingStrings.en.placeEntrySave));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.lat, closeTo(39.69, 0.0001));
    expect(result!.lon, closeTo(140.34, 0.0001));
  });

  testWidgets('typed mode out-of-range shows invalid note and does NOT pop', (
    tester,
  ) async {
    SavedPlace? result;
    var called = false;
    await tester.pumpWidget(
      host(BriefingStrings.en, const Locale('en'), (r) {
        result = r;
        called = true;
      }),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text(BriefingStrings.en.placeEntryModeCoordinates));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, BriefingStrings.en.placeEntryLatLabel),
      '999',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, BriefingStrings.en.placeEntryLonLabel),
      '0',
    );
    await tester.tap(find.text(BriefingStrings.en.placeEntrySave));
    await tester.pumpAndSettle();

    // The invalid-coords note is shown and the dialog is still open (not popped).
    expect(
      find.text(BriefingStrings.en.placeEntryInvalidCoords),
      findsOneWidget,
    );
    expect(find.byType(PlaceEntryDialog), findsOneWidget);
    expect(called, isFalse);
    expect(result, isNull);
  });

  testWidgets('DestinationEntryTile shows forecast-off note when disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DestinationEntryTile(
            strings: BriefingStrings.en,
            hasPlace: false,
            placeLabel: '',
            forecastEnabled: false,
            onEdit: () {},
            onClear: () {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.textContaining(BriefingStrings.en.placeEntryForecastOffNote),
      findsOneWidget,
    );
    expect(
      find.text(BriefingStrings.en.setDestinationAreaButton),
      findsWidgets,
    );
  });
}
