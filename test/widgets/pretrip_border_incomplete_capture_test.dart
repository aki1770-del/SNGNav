/// Render-and-SEE capture of the JMA partial-read (border-incomplete) caution on
/// HER mother's family-thread surface (OPS-066 observation-grade verification).
///
/// A passing reach test (pretrip_border_incomplete_test.dart) proves the caution
/// is in the widget tree; it does NOT prove the Japanese is readable or that the
/// real warning and the honest caution sit together legibly. This loads the real
/// Noto CJK font and writes a PNG for a human (VAA) to go and LOOK:
///   test/widgets/_capture/pretrip_border_incomplete_ja.png
///
/// Run:  flutter test test/widgets/pretrip_border_incomplete_capture_test.dart
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:condition_aggregator/condition_aggregator.dart';
import 'package:condition_aggregator_jma/condition_aggregator_jma.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/providers/met_norway_hourly_forecast.dart';
import 'package:sngnav_snow_scene/services/saved_place_store.dart';
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

class FakeMetProvider extends MetNorwayHourlyForecastProvider {
  FakeMetProvider(this._forecast);
  final WeatherForecast _forecast;
  @override
  Future<WeatherForecast?> fetchForecast({
    required double latitude,
    required double longitude,
  }) async => _forecast;
}

WeatherForecast _cannedTempOnly() {
  final base = DateTime.now();
  return WeatherForecast(
    issuedAt: base,
    hourly: [
      HourlyForecast(
        hour: base,
        tempCelsius: -2,
        precipitationMmPerHour: 0.5,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
      HourlyForecast(
        hour: base.add(const Duration(hours: 1)),
        tempCelsius: -2,
        precipitationMmPerHour: 0.5,
        visibilityMeters: null,
        estimatedRoadCondition: null,
      ),
    ],
  );
}

Advisory _adv(String eventClass) => Advisory(
  source: AdvisorySource.jmaJapan,
  eventClass: eventClass,
  severity: AdvisorySeverity.moderate,
  certainty: AdvisoryCertainty.observed,
  urgency: AdvisoryUrgency.immediate,
  areaDescription: '秋田県',
  effective: null,
  expires: null,
  headline: eventClass,
  description: eventClass,
);

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

  testWidgets('CAPTURE: JMA partial-read caution reaches HER (ja)', (
    tester,
  ) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    late Directory tmp;
    late SavedPlaceStore store;
    await tester.runAsync(() async {
      tmp = await Directory.systemTemp.createTemp('border_incomplete_capture');
      store = SavedPlaceStore(File('${tmp.path}/sngnav/saved_place.json'));
      await store.save(
        const SavedPlace(lat: 39.72, lon: 140.10, label: '母の地域'),
      );
    });
    addTearDown(() async {
      await tester.runAsync(() async {
        if (await tmp.exists()) await tmp.delete(recursive: true);
      });
    });

    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(640, 1900);
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
              savedPlaceStore: store,
              destForecastProviderFactory: () =>
                  FakeMetProvider(_cannedTempOnly()),
              forecastSourceOverride: 'met_norway',
              jmaAdvisoryFetchOverride:
                  ({
                    required double latitude,
                    required double longitude,
                  }) async => [
                    _adv('着雪注意報'),
                    buildIncompleteReadNotice(const ['050000']),
                  ],
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
      find.byKey(const Key('pretrip-border-incomplete-caution')),
      findsOneWidget,
    );
    expect(find.textContaining('秋田県の警報を確認できませんでした'), findsOneWidget);
    expect(find.textContaining('着雪注意報'), findsWidgets);

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')
        ..createSync(recursive: true);
      final file = File('${dir.path}/pretrip_border_incomplete_ja.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print(
        'CAPTURE pretrip_border_incomplete_ja: ${file.absolute.path} '
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
