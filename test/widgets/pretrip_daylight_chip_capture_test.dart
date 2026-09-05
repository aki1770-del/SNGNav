// Render-and-SEE capture of the pre-trip briefing card SHOWING THE DAYLIGHT
// CHIP (observation-grade verification).
//
// The daylight chip is the offline daylight-clock low-light note. It only
// reaches the card when the briefing is produced from a CommuteShape carrying a
// TripGeo (see lib/main.dart#_buildPretripView + pretrip_daylight_app_seam_test).
// This capture reconstructs the REAL production combination — the REAL
// SnowAwarePretripAdvisor.brief() over an Akita-context winter forecast with a
// dusk-crossing departure and a wired TripGeo (Akita 39.72,140.10 +9h) — and
// writes two PNGs (en + ja) so a human can go and LOOK at the rendered card
// with the daylight chip on it.
//
// Run:
//   flutter test test/widgets/pretrip_daylight_chip_capture_test.dart
// Then open:
//   test/widgets/_capture/daylight_chip_en.png
//   test/widgets/_capture/daylight_chip_ja.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

// Latin font (rendered as 'Roboto') so the EN card shows real glyphs, and the
// CJK font so the JA card shows real Japanese (not tofu) — same approach the
// existing live-real + ja-render captures use.
const _latinTtf = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';
const _cjkPaths = <String>[
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
  '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
];

// Akita context — the driver's mother. Pinned offset == --dart-define PRETRIP_UTC_OFFSET_MIN=540.
const _geo = TripGeo(
  latitude: 39.72,
  longitude: 140.10,
  utcOffset: Duration(hours: 9),
);

// A winter-hazard, dusk-crossing window. Departure 16:50 local on 2026-01-15;
// Akita sunset is ~16:30 mid-January, so the trip instants fall postDusk -> the
// daylight chip is the after-sunset note. Subzero + reduced visibility + near-
// freezing precip make the card a realistic winter briefing, not a bare clock.
final _issued = DateTime(2026, 1, 15, 16, 0);
final _departure = DateTime(2026, 1, 15, 16, 50);
const _duration = Duration(minutes: 30);
final _forecast = WeatherForecast(
  issuedAt: _issued,
  hourly: [
    HourlyForecast(
      hour: DateTime(2026, 1, 15, 16),
      tempCelsius: -3,
      precipitationMmPerHour: 2,
      visibilityMeters: 400,
    ),
    HourlyForecast(
      hour: DateTime(2026, 1, 15, 17),
      tempCelsius: -4,
      precipitationMmPerHour: 2,
      visibilityMeters: 300,
    ),
    HourlyForecast(
      hour: DateTime(2026, 1, 15, 18),
      tempCelsius: -4,
      precipitationMmPerHour: 1,
      visibilityMeters: 600,
    ),
  ],
);

PretripBriefing _briefFor(String lang) {
  final advisor = SnowAwarePretripAdvisor(
    messages: PretripMessages.forLanguage(lang),
  );
  final commute = CommuteShape(
    plannedDeparture: _departure,
    plannedDuration: _duration,
    routeIdentifiers: const ['akita-daylight'],
    flexibility: CommuteFlexibility.discretionary,
    geo: _geo, // wired -> the daylight chip can reach the card
  );
  return advisor.brief(
    forecast: _forecast,
    commute: commute,
    profile: const DriverProfileSpec(
      profileTag: 'akita',
      reactionTimeSeconds: 1.5,
    ),
  );
}

CommuteShape _renderCommute() => CommuteShape(
  plannedDeparture: _departure,
  plannedDuration: _duration,
  routeIdentifiers: const ['akita-daylight'],
  flexibility: CommuteFlexibility.discretionary,
  geo: _geo,
);

Future<bool> _loadLatin() async {
  final f = File(_latinTtf);
  if (!f.existsSync()) return false;
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  await loader.load();
  return true;
}

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

Future<void> _capture(
  WidgetTester tester, {
  required String fontFamily,
  required Widget card,
  required String outPath,
}) async {
  final key = GlobalKey();
  tester.view.physicalSize = const Size(620, 1320);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: fontFamily, useMaterial3: true),
      home: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: RepaintBoundary(
            key: key,
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
  testWidgets('daylight chip capture (EN)', (tester) async {
    final hasLatin = await _loadLatin();
    final briefing = _briefFor('en');
    // ignore: avoid_print
    print('EN chips: ${briefing.chips}');
    final daylightChips = briefing.chips
        .where((c) => c.contains('sunset') || c.contains('sunrise'))
        .toList();
    // ignore: avoid_print
    print('EN daylight chip: $daylightChips');
    expect(
      daylightChips,
      isNotEmpty,
      reason: 'the EN briefing must carry a daylight chip to capture',
    );
    await _capture(
      tester,
      fontFamily: hasLatin ? 'Roboto' : 'Roboto',
      card: PretripBriefingCard(
        briefing: briefing,
        commute: _renderCommute(),
        forecastIssuedAt: _issued,
        tripRequired: false,
        onTripRequiredChanged: (_) {},
        sourceCaption: 'Simulated forecast (demo) — offline, deterministic',
        winterCard: WinterKnowledge.fromJsonString(
          File('assets/winter_knowledge.json').readAsStringSync(),
        ).cardFor(RoadSurfaceState.blackIce, lang: 'en'),
      ),
      outPath: 'test/widgets/_capture/daylight_chip_en.png',
    );
  });

  testWidgets('daylight chip capture (JA)', (tester) async {
    final hasCjk = await _loadCjk();
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA render.');
      return;
    }
    final briefing = _briefFor('ja');
    // ignore: avoid_print
    print('JA chips: ${briefing.chips}');
    final daylightChips = briefing.chips
        .where((c) => c.contains('日の入り') || c.contains('日の出'))
        .toList();
    // ignore: avoid_print
    print('JA daylight chip: $daylightChips');
    expect(
      daylightChips,
      isNotEmpty,
      reason: 'the JA briefing must carry a daylight chip to capture',
    );
    await _capture(
      tester,
      fontFamily: 'NotoSansCJK',
      card: PretripBriefingCard(
        strings: BriefingStrings.ja,
        briefing: briefing,
        commute: _renderCommute(),
        forecastIssuedAt: _issued,
        tripRequired: false,
        onTripRequiredChanged: (_) {},
        sourceCaption: 'シミュレーション予報(デモ)— オフライン・確定的',
        winterCard: WinterKnowledge.fromJsonString(
          File('assets/winter_knowledge.json').readAsStringSync(),
        ).cardFor(RoadSurfaceState.blackIce, lang: 'ja'),
      ),
      outPath: 'test/widgets/_capture/daylight_chip_ja.png',
    );
  });
}
