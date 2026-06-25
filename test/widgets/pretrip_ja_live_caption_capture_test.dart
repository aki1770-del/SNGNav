/// OPS-066 / Loom L32 render-and-SEE capture for the JAPANESE LIVE source
/// caption — the reach-fix this commit lands.
///
/// A normal widget test renders with blank test fonts, so CJK text would draw
/// as tofu boxes and "tests pass" would prove NOTHING about whether HER mother
/// in Akita can actually read the live caption. This test loads the real Noto
/// Sans CJK JP font and writes a PNG of the full pre-trip card carrying a
/// POPULATED Japanese LIVE caption (the JMA-merged 大雪警報 arm WITH a measured
/// departure-hour visibility reading) so the rendered Japanese can be looked at.
///
/// The caption is built by the SAME production functions the pre-trip screen
/// calls (`pretripLiveSourceCaption` + `pretripMeasuredVisibilityCaption`,
/// lang: 'ja') — not a hand-copied literal — so the PNG shows exactly what
/// production composes (genchi-genbutsu). The PNG lands in test/widgets/_capture/
/// (gitignored) for a human to eyeball; this is the L32 observation artifact.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:driving_conditions/driving_conditions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/pretrip_live_forecast.dart';
import 'package:sngnav_snow_scene/providers/winter_knowledge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

void main() {
  var fontLoaded = false;
  setUpAll(() async {
    for (final path in const [
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc',
      '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',
    ]) {
      final file = File(path);
      if (file.existsSync()) {
        final loader = FontLoader('NotoSansCJK')
          ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
        await loader.load();
        fontLoaded = true;
      }
    }
  });

  testWidgets('captures the JA LIVE caption (JMA 大雪警報 + measured visibility)',
      (tester) async {
    // Without a real CJK font this PNG would be misleading tofu — refuse to
    // bake one (OPS-066: the artifact must be real or absent).
    if (!fontLoaded) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    // The measured-visibility clause + the JMA-merged live caption, composed by
    // the REAL production builders at lang 'ja'. 80 m / 45 km / lat / lon pass
    // through verbatim; the 大雪警報 classification is relayed byte-for-byte.
    final visJa = pretripMeasuredVisibilityCaption(
      meters: 80,
      stationName: '青森空港',
      km: '45',
      attribution: 'Japan Meteorological Agency / AMeDAS (気象庁)',
      lang: 'ja',
    );
    final caption = pretripLiveSourceCaption(
      status: PretripLiveStatus.japanJmaMerged,
      latitude: 39.72,
      longitude: 140.10,
      prefectureCode: '050000',
      jmaEventName: '大雪警報',
      visCaption: visJa,
      lang: 'ja',
    );

    final issued = DateTime(2026, 1, 1, 6, 0);
    final dep = DateTime(2026, 1, 1, 7, 15);
    // A whiteout-now, clear-later morning → a wait/hazard verdict, so the card
    // carries a real safety verdict above the live caption.
    final forecast = WeatherForecast(
      issuedAt: issued,
      hourly: [
        HourlyForecast(
            hour: DateTime(2026, 1, 1, 7),
            tempCelsius: -3,
            precipitationMmPerHour: 3,
            visibilityMeters: 80),
        HourlyForecast(
            hour: DateTime(2026, 1, 1, 8),
            tempCelsius: -3,
            precipitationMmPerHour: 1,
            visibilityMeters: 250),
        HourlyForecast(
            hour: DateTime(2026, 1, 1, 9),
            tempCelsius: -1,
            visibilityMeters: 5000),
        HourlyForecast(
            hour: DateTime(2026, 1, 1, 10),
            tempCelsius: 0,
            visibilityMeters: 8000),
      ],
    );
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['akita-commute'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = SnowAwarePretripAdvisor(messages: PretripMessages.ja).brief(
      forecast: forecast,
      commute: commute,
      profile:
          const DriverProfileSpec(profileTag: 'akita', reactionTimeSeconds: 1.5),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(640, 1280);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 1240,
                child: PretripBriefingCard(
                  strings: BriefingStrings.ja,
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption: caption,
                  winterCard: WinterKnowledge.fromJsonString(
                    File('assets/winter_knowledge.json').readAsStringSync(),
                  ).cardFor(RoadSurfaceState.blackIce, lang: 'ja'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_ja_live_caption.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print('CAPTURE pretrip_ja_live_caption: ${file.absolute.path} '
          '${file.lengthSync()} bytes ${image.width}x${image.height}');
      // ignore: avoid_print
      print('JA CAPTION RENDERED: $caption');
    });

    expect(tester.takeException(), isNull);
  });
}
