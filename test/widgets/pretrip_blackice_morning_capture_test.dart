// Render-and-SEE capture of the humidity-aware black-ice morning (observation-grade).
//
// The scene: a classic Akita radiative-cooling dawn — air ABOVE freezing
// (+0.5 °C), 95% humidity, NO precipitation, clear visibility. Before advisor
// 0.5.0 this morning briefed CLEAR — the ambient-only frost check cannot see
// it. Now the Magnus surface estimate (−0.21 °C) fires the caution and the
// briefing tells the driver's mother, in Japanese, that the road can be ice even
// though the thermometer says it is not freezing.
//
// Run: flutter test test/widgets/pretrip_blackice_morning_capture_test.dart
// Then LOOK: test/widgets/_capture/pretrip_blackice_morning_ja.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
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

  testWidgets('the black-ice morning briefs caution with the 放射冷却 chip', (
    tester,
  ) async {
    if (!fontLoaded) {
      markTestSkipped('No Noto CJK font on this host — skipping JA render.');
      return;
    }
    final advisor = SnowAwarePretripAdvisor(messages: PretripMessages.ja);
    final dep = DateTime(2026, 1, 15, 6, 30);
    final issued = DateTime(2026, 1, 15, 5, 30);

    // Above-zero ambient + high humidity + NO precip + clear visibility:
    // every pre-0.5.0 condition is silent; only the radiative-frost check
    // can produce the caution (probe-measured: 95% @ 0.5 °C → −0.21).
    final forecast = WeatherForecast(
      hourly: [
        HourlyForecast(
          hour: DateTime(2026, 1, 15, 6),
          tempCelsius: 0.5,
          humidityRH: 95,
          visibilityMeters: 9000,
        ),
        HourlyForecast(
          hour: DateTime(2026, 1, 15, 7),
          tempCelsius: 1.0,
          humidityRH: 95,
          visibilityMeters: 10000,
        ),
        HourlyForecast(
          hour: DateTime(2026, 1, 15, 8),
          tempCelsius: 2.0,
          humidityRH: 95,
          visibilityMeters: 10000,
        ),
      ],
      issuedAt: issued,
    );
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['akita-commute'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: forecast,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'akita',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: SingleChildScrollView(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 560,
                child: PretripBriefingCard(
                  strings: BriefingStrings.ja,
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption: 'シミュレーション予報(デモ)— オフライン・確定的',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // The chip must be on screen — in Japanese, describing the above-zero
    // freeze honestly.
    expect(find.textContaining('放射冷却'), findsWidgets);

    // Capture for the go-and-LOOK step (repo pattern: runAsync for the
    // real-async image work).
    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('test/widgets/_capture/pretrip_blackice_morning_ja.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(out.lengthSync(), greaterThan(10000));
    });
  });
}
