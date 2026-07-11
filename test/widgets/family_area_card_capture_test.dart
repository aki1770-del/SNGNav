// Render-and-SEE capture of the FamilyAreaCard (OPS-066 / L32 observation-grade
// verification). The FamilyAreaCard is the FAMILY-THREAD destination-area read —
// "what conditions will SHE face in her mother's area if she drives there" — so
// the card must be looked at, in Japanese, the way HER mother in Akita receives
// it. A passing widget test alone proves nothing about whether the Japanese is
// readable (blank test fonts render tofu), so this writes real PNGs with the
// real Noto Sans CJK font loaded, for a human to go and LOOK.
//
// It builds the REAL FamilyAreaCard over an AreaConditionRead constructed
// directly (the legitimate DTO entry point — the read is a const data shape),
// BOTH in Japanese (PretripMessages.ja + BriefingStrings.ja):
//   1. _capture/family_area_ja_populated.png   — warning + elevated band + 80 m
//   2. _capture/family_area_ja_honest_null.png — the honest-degradation state
//
// Run:
//   flutter test test/widgets/family_area_card_capture_test.dart
// Then open:
//   test/widgets/_capture/family_area_ja_populated.png
//   test/widgets/_capture/family_area_ja_honest_null.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/family_area_card.dart';

// The CJK font so the JA card shows real Japanese (not tofu) — same approach the
// existing ja-render + daylight captures use.
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

// The POPULATED Akita read: 大雪警報 active, an elevated forecast band, and a
// real measured visibility of 80 m from the 秋田 station ~5 km away.
const _populated = AreaConditionRead(
  areaLabel: '秋田県',
  officialWarningVerbatim: '大雪警報',
  warningCheckAvailable: true,
  areaHazard: HourHazard.elevated,
  forecastCovered: true,
  measuredVisibilityMeters: 80,
  visibilityStationName: '秋田',
  visibilityDistanceKm: 5,
);

// The HONEST-NULL read: the warning check failed, no forecast covers the
// window, and there is no measured visibility — every line degrades to its
// honest "unavailable / not covered / none" form, never to a fabricated value.
const _honestNull = AreaConditionRead(
  areaLabel: '秋田県',
  officialWarningVerbatim: null,
  warningCheckAvailable: false,
  areaHazard: HourHazard.clear, // non-asserted placeholder; band is not shown
  forecastCovered: false,
  measuredVisibilityMeters: null,
  visibilityStationName: null,
  visibilityDistanceKm: null,
);

Future<void> _capture(
  WidgetTester tester, {
  required Widget card,
  required String outPath,
}) async {
  final key = GlobalKey();
  // Tall surface so the whole card lays out without clipping; the
  // RepaintBoundary sizes to the card's natural height.
  tester.view.physicalSize = const Size(640, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: key,
            // The card carries its own L/R margins; give it a 600 px column.
            child: SizedBox(width: 600, child: card),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
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
  testWidgets('FamilyAreaCard JA capture — populated + honest-null', (
    tester,
  ) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    // Echo the EXACT Japanese strings each card should be showing, so the PNG
    // and the report can be checked against the same source of truth.
    const m = PretripMessages.ja;
    const s = BriefingStrings.ja;
    final populatedChips = areaConditionChips(_populated, m);
    final honestNullChips = areaConditionChips(_honestNull, m);
    // ignore: avoid_print
    print('TITLE: ${s.destinationAreaTitle}');
    // ignore: avoid_print
    print('PLACE (populated): ${s.destinationAreaPlace(_populated.areaLabel)}');
    // ignore: avoid_print
    print('POPULATED CHIPS: $populatedChips');
    // ignore: avoid_print
    print('PLACE (null): ${s.destinationAreaPlace(_honestNull.areaLabel)}');
    // ignore: avoid_print
    print('HONEST-NULL CHIPS: $honestNullChips');
    // ignore: avoid_print
    print('NOTE: ${s.areaResolutionNote}');

    await _capture(
      tester,
      card: const FamilyAreaCard(
        read: _populated,
        messages: PretripMessages.ja,
        strings: BriefingStrings.ja,
      ),
      outPath: 'test/widgets/_capture/family_area_ja_populated.png',
    );

    await _capture(
      tester,
      card: const FamilyAreaCard(
        read: _honestNull,
        messages: PretripMessages.ja,
        strings: BriefingStrings.ja,
      ),
      outPath: 'test/widgets/_capture/family_area_ja_honest_null.png',
    );
  });
}
