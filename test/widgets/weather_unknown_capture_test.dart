// Render-and-LOOK verification for the state this release invented.
//
// The whole point of the honest-absence release is a third state that never
// existed before: "we do not know what the road is". It is now in the type
// system and asserted by many tests — and until this file it had NEVER BEEN
// RENDERED AND LOOKED AT. "Tests green" is not "verified": the driver reads
// PIXELS, not a `SafetyVerdict`.
//
// This captures the three absence states the app can now show her:
//
//   1. NO CONDITION AT ALL  — the feed is gone (the compound-failure case).
//      Before: `SizedBox.shrink()` — literally nothing. An empty status bar is
//      indistinguishable from a calm one, so "no data" rendered exactly like
//      "the road is fine".
//   2. PARTIAL DATA         — a feed answered, but not with everything. The bar
//      must show "not measured" for the fields it does not have, not a
//      fabricated number (0.4.4 rendered +5.0 °C and "No ice risk" here).
//   3. AUTHORITY ADVISORY   — a road authority declared a hazard and measured
//      nothing. The alert must still reach her.
//
// Run:   flutter test test/widgets/weather_unknown_capture_test.dart
// Then:  LOOK at the PNGs under test/widgets/_capture/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/widgets/weather_status_bar.dart';

class _MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class _MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

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

Future<void> _capture(
  WidgetTester tester, {
  required GlobalKey key,
  required String outPath,
}) async {
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outPath);
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURE $outPath ${file.lengthSync()} bytes');
  });
  expect(tester.takeException(), isNull);
}

Future<void> _pumpBar(
  WidgetTester tester, {
  required GlobalKey key,
  required WeatherState state,
}) async {
  final weather = _MockWeatherBloc();
  final nav = _MockNavigationBloc();
  whenListen(weather, const Stream<WeatherState>.empty(), initialState: state);
  whenListen(
    nav,
    const Stream<NavigationState>.empty(),
    initialState: const NavigationState(status: NavigationStatus.idle),
  );

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(fontFamily: 'NotoSansCJK'),
      home: Scaffold(
        body: MultiBlocProvider(
          providers: [
            BlocProvider<WeatherBloc>.value(value: weather),
            BlocProvider<NavigationBloc>.value(value: nav),
          ],
          // The REAL layout the app uses (snow_scene_scaffold.dart): the bar is
          // the first child of a Column, so it must HUG its content. Capturing
          // it under a stretching parent would tell us nothing about what she
          // actually sees.
          child: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RepaintBoundary(key: key, child: const WeatherStatusBar()),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the three absence states RENDER — go and see them', (
    tester,
  ) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    // ---------------------------------------------------------------------
    // 1. NO CONDITION AT ALL — the feed is gone.
    //    Before this release: nothing was drawn.
    // ---------------------------------------------------------------------
    final k1 = GlobalKey();
    await _pumpBar(
      tester,
      key: k1,
      state: const WeatherState(status: WeatherStatus.monitoring),
    );
    // It must SAY SO — in Japanese first, because the night the feed dies in
    // Akita is exactly the night an English-only sentence becomes silence.
    expect(find.textContaining('路面状況を取得できていません'), findsOneWidget);
    expect(find.text('NO DATA'), findsOneWidget);
    await _capture(
      tester,
      key: k1,
      outPath: 'test/widgets/_capture/weather_bar_no_data.png',
    );

    // ---------------------------------------------------------------------
    // 2. PARTIAL DATA — the feed answered, but did not measure everything.
    //    0.4.4 rendered +5.0 °C / 10 km / "No ice risk" here.
    // ---------------------------------------------------------------------
    final k2 = GlobalKey();
    await _pumpBar(
      tester,
      key: k2,
      state: WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition(
          // temperature measured; visibility and ice risk were NOT.
          temperatureCelsius: -1.0,
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          source: ObservationSource.measured,
          timestamp: DateTime.now(),
        ),
      ),
    );
    // The fields we do not have render as "not measured" — never a number.
    expect(find.textContaining('not measured'), findsOneWidget);
    expect(find.text('未計測 / NOT MEASURED'), findsOneWidget);
    await _capture(
      tester,
      key: k2,
      outPath: 'test/widgets/_capture/weather_bar_partial.png',
    );

    // ---------------------------------------------------------------------
    // 3. AUTHORITY ADVISORY, NOTHING MEASURED — the Digitraffic shape.
    //    A road authority declared a SEVERE situation and measured no
    //    temperature, no visibility, no wind. The alert must still reach her.
    // ---------------------------------------------------------------------
    final k3 = GlobalKey();
    await _pumpBar(
      tester,
      key: k3,
      state: WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition.unknown(
          timestamp: DateTime.now(),
          hazardAssertion: HazardAssertion.severe,
        ),
      ),
    );
    // Positive evidence fires on partial data: this is a HAZARD, not "unknown".
    expect(find.text('HAZARD'), findsOneWidget);
    await _capture(
      tester,
      key: k3,
      outPath: 'test/widgets/_capture/weather_bar_authority_severe.png',
    );
  });
}
