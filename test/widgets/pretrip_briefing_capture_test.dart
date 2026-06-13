/// Pixel-capture harness for the pre-trip briefing surface.
///
/// An observable deliverable is verified by rendering it and looking at the
/// actual output — passing widget tests alone are not "seen". This harness
/// loads a real system TTF in place of the test-default Ahem block font so
/// the captured PNGs show actual legible text, renders the card in its three
/// load-bearing states (wait-advised / required-trip honesty / clear), and
/// writes real PNGs to test/widgets/_capture/ for a human to eyeball.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/providers/jma_briefing_merge.dart';
import 'package:sngnav_snow_scene/services/snow_aware_pretrip_advisor.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_briefing_card.dart';

const _ttf = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf';

Future<void> _loadRealFont() async {
  final bytes = File(_ttf).readAsBytesSync();
  final loader = FontLoader('Roboto')
    ..addFont(Future.value(ByteData.view(bytes.buffer)));
  await loader.load();
}

void main() {
  final dep = DateTime(2026, 1, 1, 7, 15);
  final issued = DateTime(2026, 1, 1, 6, 0);

  // Hazard fixtures stay subzero; the clear fixture sits above the frost
  // band (subzero dry air is caution class since the 2026-06-12 quant fix).
  HourlyForecast slot(int hour, {double temp = -3, double? vis, double? precip}) =>
      HourlyForecast(
        hour: DateTime(2026, 1, 1, hour),
        tempCelsius: temp,
        precipitationMmPerHour: precip,
        visibilityMeters: vis,
      );

  final whiteoutThenClear = [
    slot(7, vis: 80, precip: 3),
    slot(8, vis: 250, precip: 1),
    slot(9, vis: 5000),
    slot(10, vis: 8000),
  ];
  final clear = [
    slot(7, temp: 3, vis: 8000),
    slot(8, temp: 3, vis: 8000),
  ];
  // Dry subzero air — caution class with the frost/black-ice chip (the
  // 2026-06-12 quant fix: 70/620 real winter slots used to render "clear").
  final frostDry = [
    slot(7, temp: -8),
    slot(8, temp: -8),
  ];

  final cases = <String, (List<HourlyForecast>, CommuteFlexibility)>{
    'wait_advised': (whiteoutThenClear, CommuteFlexibility.discretionary),
    'required_honesty': (whiteoutThenClear, CommuteFlexibility.required),
    'clear_depart': (clear, CommuteFlexibility.discretionary),
    'frost_caution': (frostDry, CommuteFlexibility.discretionary),
  };

  for (final entry in cases.entries) {
    testWidgets('capture: ${entry.key}', (tester) async {
      await _loadRealFont();
      final (hourly, flexibility) = entry.value;
      const advisor = SnowAwarePretripAdvisor();
      final commute = CommuteShape(
        plannedDeparture: dep,
        plannedDuration: const Duration(minutes: 30),
        routeIdentifiers: const ['demo'],
        flexibility: flexibility,
      );
      final briefing = advisor.brief(
        forecast: WeatherForecast(hourly: hourly, issuedAt: issued),
        commute: commute,
        profile: const DriverProfileSpec(
          profileTag: 'demo',
          reactionTimeSeconds: 1.5,
        ),
      );

      final boundaryKey = GlobalKey();
      tester.view.physicalSize = const Size(620, 760);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 600,
                  height: 740,
                  child: PretripBriefingCard(
                    briefing: briefing,
                    commute: commute,
                    forecastIssuedAt: issued,
                    tripRequired: flexibility == CommuteFlexibility.required,
                    onTripRequiredChanged: (_) {},
                    sourceCaption:
                        'Simulated forecast (demo) — offline, deterministic',
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.runAsync(() async {
        final boundary = boundaryKey.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        expect(bytes, isNotNull);
        final dir = Directory('test/widgets/_capture')..createSync();
        final file = File('${dir.path}/pretrip_${entry.key}.png');
        file.writeAsBytesSync(bytes!.buffer.asUint8List());
        expect(file.lengthSync(), greaterThan(0));
        // ignore: avoid_print
        print('CAPTURE ${entry.key}: ${file.path} '
            '${file.lengthSync()} bytes ${image.width}x${image.height}');
      });

      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('capture: jp_jma_snow', (tester) async {
    await _loadRealFont();
    // Japan-shaped live forecast: temperature only (the MET Norway compact
    // product gives Nagoya no visibility and no road state), with an official
    // JMA heavy-snow warning merged onto the departure window. Without the
    // merge this renders "no winter hazard"; with it the driver sees the snow.
    final jpForecast = WeatherForecast(
      hourly: [slot(7, temp: -2), slot(8, temp: -2)],
      issuedAt: issued,
    );
    final merged = mergeJmaWinterAdvisory(
      jpForecast,
      jmaEventName: '大雪警報',
      windowStart: dep,
      windowDuration: const Duration(minutes: 30),
    );
    const advisor = SnowAwarePretripAdvisor();
    final commute = CommuteShape(
      plannedDeparture: dep,
      plannedDuration: const Duration(minutes: 30),
      routeIdentifiers: const ['demo'],
      flexibility: CommuteFlexibility.discretionary,
    );
    final briefing = advisor.brief(
      forecast: merged,
      commute: commute,
      profile: const DriverProfileSpec(
        profileTag: 'demo',
        reactionTimeSeconds: 1.5,
      ),
    );

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(620, 760);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Roboto', useMaterial3: true),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: boundaryKey,
              child: SizedBox(
                width: 600,
                height: 740,
                child: PretripBriefingCard(
                  briefing: briefing,
                  commute: commute,
                  forecastIssuedAt: issued,
                  tripRequired: false,
                  onTripRequiredChanged: (_) {},
                  sourceCaption:
                      'MET Norway forecast + JMA heavy-snow warning (official)',
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync();
      final file = File('${dir.path}/pretrip_jp_jma_snow.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print('CAPTURE jp_jma_snow: ${file.path} ${file.lengthSync()} bytes');
    });

    expect(tester.takeException(), isNull);
  });
}
