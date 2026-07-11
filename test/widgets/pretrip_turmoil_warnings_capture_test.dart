/// Render-and-SEE capture of the JMA turmoil-warnings card on HER pre-trip
/// briefing (OPS-066 observation-grade verification).
///
/// A passing reach test (pretrip_turmoil_warnings_test.dart) proves the card
/// is in the widget tree; it does NOT prove the Japanese is readable, that the
/// verbatim 大雨危険警報 row sits legibly above the 強風注意報 row, or that the
/// error-container escalation tone reads as a warning and not an alarm. This
/// loads the real Noto CJK font and writes a PNG for a human (VAA) to go and
/// LOOK:
///   test/widgets/_capture/pretrip_turmoil_warnings_ja.png
///
/// Run:  flutter test test/widgets/pretrip_turmoil_warnings_capture_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_screen.dart';

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

WeatherForecast _cannedTempOnly() {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(
        hour: base,
        tempCelsius: 18,
        precipitationMmPerHour: 4.0,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: 18,
        precipitationMmPerHour: 4.0,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
    ],
  );
}

Advisory _adv(String eventClass, AdvisorySeverity severity) => Advisory(
      source: AdvisorySource.jmaJapan,
      eventClass: eventClass,
      severity: severity,
      certainty: AdvisoryCertainty.observed,
      urgency: AdvisoryUrgency.immediate,
      areaDescription: '秋田県',
      effective: null,
      expires: null,
      headline: eventClass,
      description: eventClass,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture: turmoil warnings card, ja, real CJK glyphs',
      (tester) async {
    final cjk = await _loadCjk();
    // A tall phone-ish viewport so the card region is capturable below the
    // briefing card.
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('ja')],
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A73E8),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          fontFamily: 'NotoSansCJK',
        ),
        home: RepaintBoundary(
          key: boundaryKey,
          child: Scaffold(
            body: PretripScreen(
              pretripPointOverride: (lat: 39.72, lon: 140.10), // Akita
              metForecastFetchOverride: () async => _cannedTempOnly(),
              jmaAdvisoryFetchOverride: ({
                required double latitude,
                required double longitude,
              }) async =>
                  [
                    _adv('強風注意報', AdvisorySeverity.moderate),
                    _adv('大雨危険警報', AdvisorySeverity.extreme),
                  ],
              surfaceState: RoadSurfaceState.dry,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Guard: the card actually reached the tree before we capture.
    final card = find.byKey(const Key('pretrip-jma-turmoil-warnings'));
    expect(card, findsOneWidget);
    await tester.ensureVisible(card);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('大雨危険警報（秋田県）'), findsOneWidget);
    expect(find.text('強風注意報（秋田県）'), findsOneWidget);

    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')
        ..createSync(recursive: true);
      final file = File('${dir.path}/pretrip_turmoil_warnings_ja.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('CAPTURE pretrip_turmoil_warnings_ja: ${file.absolute.path} '
          '${file.lengthSync()} bytes ${image.width}x${image.height} '
          'cjk=$cjk');
    });

    final ex = tester.takeException();
    if (ex != null) {
      // ignore: avoid_print
      print('NOTE non-fatal exception drained: $ex');
    }
  });
}
