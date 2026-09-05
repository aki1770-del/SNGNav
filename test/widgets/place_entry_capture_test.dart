// Render-and-SEE capture of the in-app PLACE-ENTRY UI (observation-grade
// observation-grade verification). The destination-area place entry is the
// surface that lets the driver — the driver, a daughter — set her mother's-area
// destination herself, completing the family-thread reach. A passing widget
// test alone proves nothing about whether the Japanese is readable (blank test
// fonts render tofu), so this writes real PNGs with the real Noto Sans CJK font
// loaded, for a human to go and LOOK.
//
// It captures THREE surfaces, all in Japanese (BriefingStrings.ja):
//   1. _capture/place_entry_tile_unset_ja.png      — DestinationEntryTile,
//      hasPlace:false, forecastEnabled:false (set-area + local-only note +
//      honest forecast-off note).
//   2. _capture/place_entry_tile_set_ja.png        — DestinationEntryTile,
//      hasPlace:true, placeLabel:'秋田県', forecastEnabled:true (change-area +
//      秋田県 + the clear/delete affordance).
//   3. _capture/place_entry_dialog_prefecture_ja.png — the PlaceEntryDialog body
//      in prefecture-pick mode (the dropdown + the coarse note).
//
// Run:
//   flutter test test/widgets/place_entry_capture_test.dart
// Then open the PNGs under test/widgets/_capture/ and LOOK.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/place_entry_dialog.dart';

// The CJK font so the JA surfaces show real Japanese (not tofu) — same approach
// the existing ja-render + family-area captures use.
const _cjkPaths = <String>[
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
];

Future<bool> _loadCjk() async {
  var loaded = false;
  for (final p in _cjkPaths) {
    final f = File(p);
    if (f.existsSync()) {
      final loader = FontLoader('NotoSansCJK')
        ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
      await loader.load();
      loaded = true;
    }
  }
  return loaded;
}

/// Pumps [child] inside a white MaterialApp/Scaffold, lets it settle, then
/// writes the RepaintBoundary's pixels to [outPath] as a PNG.
Future<void> _capture(
  WidgetTester tester, {
  required Widget child,
  required Size surface,
  required String outPath,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = surface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(key: key, child: child),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURE $outPath ${file.lengthSync()} bytes');
  });
  expect(tester.takeException(), isNull);
}

void main() {
  testWidgets('place-entry UI JA capture — tile (unset + set) + dialog', (
    tester,
  ) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    const s = BriefingStrings.ja;

    // Echo the EXACT Japanese each surface should show, so the PNGs and the
    // report can be checked against the same source of truth.
    // ignore: avoid_print
    print('--- TILE (unset, forecast off) ---');
    // ignore: avoid_print
    print('  title: ${s.setDestinationAreaButton}');
    // ignore: avoid_print
    print('  subtitle line 1: ${s.placeEntryLocalOnlyNote}');
    // ignore: avoid_print
    print('  subtitle line 2: ${s.placeEntryForecastOffNote}');

    // ignore: avoid_print
    print('--- TILE (set: 秋田県, forecast on) ---');
    // ignore: avoid_print
    print('  title: ${s.editDestinationAreaButton} · 秋田県');
    // ignore: avoid_print
    print('  subtitle: ${s.placeEntryLocalOnlyNote}');
    // ignore: avoid_print
    print('  clear tooltip: ${s.placeEntryClear}');

    // ignore: avoid_print
    print('--- DIALOG (prefecture mode) ---');
    // ignore: avoid_print
    print('  title: ${s.placeEntryTitle}');
    // ignore: avoid_print
    print('  segment 1 (selected): ${s.placeEntryModePrefecture}');
    // ignore: avoid_print
    print('  segment 2: ${s.placeEntryModeCoordinates}');
    // ignore: avoid_print
    print('  dropdown hint: ${s.placeEntryPrefectureHint}');
    // ignore: avoid_print
    print('  coarse note: ${s.placeEntryCoarseNote}');
    // ignore: avoid_print
    print('  local-only note: ${s.placeEntryLocalOnlyNote}');
    // ignore: avoid_print
    print('  cancel: ${s.placeEntryCancel} · save: ${s.placeEntrySave}');

    // 1) Unset tile, forecast OFF (three-line: local-only + forecast-off note).
    await _capture(
      tester,
      surface: const Size(640, 600),
      outPath: 'test/widgets/_capture/place_entry_tile_unset_ja.png',
      child: const SizedBox(
        width: 600,
        child: DestinationEntryTile(
          strings: BriefingStrings.ja,
          hasPlace: false,
          placeLabel: '',
          forecastEnabled: false,
          onEdit: _noop,
          onClear: _noop,
        ),
      ),
    );

    // 2) Set tile, place '秋田県', forecast ON (shows change-area + place + the
    //    delete/clear affordance).
    await _capture(
      tester,
      surface: const Size(640, 600),
      outPath: 'test/widgets/_capture/place_entry_tile_set_ja.png',
      child: const SizedBox(
        width: 600,
        child: DestinationEntryTile(
          strings: BriefingStrings.ja,
          hasPlace: true,
          placeLabel: '秋田県',
          forecastEnabled: true,
          onEdit: _noop,
          onClear: _noop,
        ),
      ),
    );

    // 3) The PlaceEntryDialog in prefecture-pick mode. Instantiated directly
    //    (no `initial`, so its default mode is prefecture); the AlertDialog
    //    renders inside the Scaffold and is captured via the RepaintBoundary.
    await _capture(
      tester,
      surface: const Size(700, 1000),
      outPath: 'test/widgets/_capture/place_entry_dialog_prefecture_ja.png',
      child: const SizedBox(
        width: 640,
        height: 900,
        child: PlaceEntryDialog(strings: BriefingStrings.ja),
      ),
    );
  });
}

void _noop() {}
