// Render-and-SEE capture of the in-drive black-ice warning surfaces
// (observation-grade verification).
//
// The radiative-frost morning (+2 °C / 70 % RH, clear) previously left the
// status bar SILENT and, when a feed flag did fire, the message was a
// generic English line. This captures the REAL widgets after the fix so a
// human can go and LOOK at what the driver screen shows:
//   1. _capture/weather_bar_radiative_frost.png — the status bar in the
//      invisible-ice window: red hazard styling + ICE badge on a clear
//      +2 °C morning.
//   2. _capture/safety_overlay_blackice_ja.png — the REAL SafetyOverlay
//      rendering the dispatched ja-primary ブラックアイスバーン line
//      (looks-wet variant, possibility-graded) with a real CJK font.
//
// Run:
//   flutter test test/widgets/weather_blackice_capture_test.dart
// Then open the PNGs under test/widgets/_capture/.
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
import 'package:sngnav_snow_scene/widgets/scenario_phase_indicator.dart';
import 'package:sngnav_snow_scene/widgets/weather_status_bar.dart';

class _MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

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

/// the driver Akita radiative-frost morning: raw isHazardous FALSE, surface frozen.
final _radiativeFrost = WeatherCondition(
  precipType: PrecipitationType.none,
  intensity: PrecipitationIntensity.none,
  temperatureCelsius: 2.0,
  visibilityMeters: 10000,
  windSpeedKmh: 5,
  humidityRH: 70,
  timestamp: DateTime.now(),
  source: ObservationSource.measured,
);

Future<void> _capture(
  WidgetTester tester, {
  required GlobalKey key,
  required String outPath,
}) async {
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
  testWidgets('WeatherStatusBar + SafetyOverlay black-ice JA capture', (
    tester,
  ) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    tester.view.physicalSize = const Size(900, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Real NavigationBloc so the REAL SafetyOverlay renders the REAL
    // dispatched message — no hand-fed strings.
    final navigationBloc = NavigationBloc();
    addTearDown(navigationBloc.close);
    final weatherBloc = _MockWeatherBloc();
    whenListen(
      weatherBloc,
      Stream.fromIterable([
        WeatherState(
          status: WeatherStatus.monitoring,
          condition: _radiativeFrost,
        ),
      ]),
      initialState: const WeatherState.unavailable(),
    );

    final barKey = GlobalKey();
    final overlayKey = GlobalKey();

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          backgroundColor: Colors.white,
          body: MultiBlocProvider(
            providers: [
              BlocProvider<NavigationBloc>.value(value: navigationBloc),
              BlocProvider<WeatherBloc>.value(value: weatherBloc),
            ],
            child: Column(
              children: [
                RepaintBoundary(key: barKey, child: const WeatherStatusBar()),
                const SizedBox(height: 24),
                Expanded(
                  child: RepaintBoundary(
                    key: overlayKey,
                    child: const Stack(children: [SafetyOverlay()]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Let the weather state land and the widget-mediated bridge dispatch
    // the SafetyAlertReceived into the real NavigationBloc.
    await tester.pumpAndSettle();

    // Observation-grade guards: the surfaces must actually SHOW the fix
    // before the PNGs are worth looking at.
    expect(find.text('ICE'), findsOneWidget);
    expect(find.textContaining('ブラックアイスバーン'), findsWidgets);
    expect(find.textContaining('濡れて見えても'), findsWidgets);

    await _capture(
      tester,
      key: barKey,
      outPath: 'test/widgets/_capture/weather_bar_radiative_frost.png',
    );
    await _capture(
      tester,
      key: overlayKey,
      outPath: 'test/widgets/_capture/safety_overlay_blackice_ja.png',
    );
  });

  testWidgets('ScenarioPhaseIndicator ice-first ordering JA capture', (
    tester,
  ) async {
    final hasCjk = await _loadCjk();
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    tester.view.physicalSize = const Size(700, 300);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Feed ice flag with NO precipitation — previously this showed
    // "Clear — City Departure" with a sun icon (the ordering bug); it must
    // now show the ice phase with the ja-primary description.
    final icedNoPrecip = WeatherCondition(
      precipType: PrecipitationType.none,
      intensity: PrecipitationIntensity.none,
      temperatureCelsius: -2.0,
      visibilityMeters: 8000,
      windSpeedKmh: 10,
      iceRisk: true,
      timestamp: DateTime.now(),
      source: ObservationSource.measured,
    );

    final weatherBloc = _MockWeatherBloc();
    whenListen(
      weatherBloc,
      const Stream<WeatherState>.empty(),
      initialState: WeatherState(
        status: WeatherStatus.monitoring,
        condition: icedNoPrecip,
      ),
    );

    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          backgroundColor: Colors.black,
          body: BlocProvider<WeatherBloc>.value(
            value: weatherBloc,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: const ScenarioPhaseIndicator(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('Ice Risk'), findsOneWidget);
    expect(find.textContaining('ブラックアイスバーン'), findsOneWidget);
    expect(find.text('Clear — City Departure'), findsNothing);

    await _capture(
      tester,
      key: key,
      outPath: 'test/widgets/_capture/scenario_phase_ice_first_ja.png',
    );
  });
}
