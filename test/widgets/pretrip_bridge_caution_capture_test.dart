/// Render-and-SEE capture of the ROUTE BRIDGE caution on HER pre-trip surface
/// (OPS-066 observation-grade verification).
///
/// A passing reach test (pretrip_bridge_caution_test.dart) proves the caution
/// is in the widget tree; it does NOT prove the Japanese line — この先、経路上に
/// 橋が約2か所あります。橋は路面より先に凍結します。 — is readable and sits at
/// caution (not alarm) weight beside the briefing card. This loads the real
/// Noto CJK font and writes a PNG for a human to go and LOOK:
///   test/widgets/_capture/pretrip_bridge_caution_ja.png
///
/// Run:  flutter test test/widgets/pretrip_bridge_caution_capture_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/providers/pretrip_route_bridges.dart';
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

/// A freezing live forecast covering "now", so the briefing renders the LIVE
/// path and the bridge caution's temperature gate (window min ≤ +3.0 °C) is
/// the arm actually captured.
WeatherForecast _freezingLive() {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(hour: base, tempCelsius: -2, precipitationMmPerHour: 0.5),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: -2,
        precipitationMmPerHour: 0.5,
      ),
    ],
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

  testWidgets('CAPTURE: route bridge caution reaches HER (ja)', (tester) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(640, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
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
              metForecastFetchOverride: () async => _freezingLive(),
              // The REAL resolve pipeline over a fake shape + fake sites:
              // 2 on-route clusters, exactly the reach test's fixture.
              routeBridgesOverride: () => resolvePretripRouteBridges(
                fetchRouteShape: () async => [
                  const LatLng(39.72000, 140.10000),
                  const LatLng(39.74000, 140.10000),
                ],
                loadBridgeCsv: () async =>
                    'way_id,lat,lon,bearing_deg\n'
                    '1,39.72500,140.10000,0\n'
                    '2,39.73500,140.10000,0\n',
              ),
              surfaceState: RoadSurfaceState.compactedSnow,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
    }

    // Guard: the caution actually reached the tree before we capture.
    expect(
      find.byKey(const Key('pretrip-bridge-corridor-caution')),
      findsOneWidget,
    );
    expect(find.textContaining('この先、秋田県内の経路上に橋が約2か所あります'), findsOneWidget);

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')
        ..createSync(recursive: true);
      final file = File('${dir.path}/pretrip_bridge_caution_ja.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print(
        'CAPTURE pretrip_bridge_caution_ja: ${file.absolute.path} '
        '${file.lengthSync()} bytes ${image.width}x${image.height}',
      );
    });

    final ex = tester.takeException();
    if (ex != null) {
      // ignore: avoid_print
      print('NOTE non-fatal exception drained: $ex');
    }
  });
}
