/// Render-and-SEE capture of the SNOW_SCENE pre-trip surface AS HOSTED INSIDE
/// the reference app, in Japanese (OPS-066 / L32 observation-grade verification).
///
/// This is the proof that the language reach-fix actually reaches HER in the
/// SHIPPED snow-scene app — not just in an isolated widget fixture. It mounts the
/// REAL [SnowSceneShell] (its default `_Destination.pretrip` leg), which builds
/// the Scaffold chrome the product shows first: a localized "出発前に" AppBar, a
/// "運転を開始" Start-drive button, and the shared
/// [PretripScreen](surfaceState: RoadSurfaceState.compactedSnow).
///
/// The shell's pretrip leg reads NO drive BLoC (the 7 drive BLoCs are only
/// looked up on the `_Destination.drive` arm), so it stands up under a plain
/// MaterialApp with just the ja localization delegates + the Noto CJK font —
/// no BLoC mocking required.
///
/// A passing widget test alone proves nothing about whether the Japanese is
/// readable (blank test fonts render tofu), so this loads the real Noto Sans CJK
/// font and writes a real PNG for a human to go and LOOK:
///   test/widgets/_capture/snow_scene_pretrip_ja.png
///
/// Run:
///   flutter test test/widgets/snow_scene_pretrip_capture_test.dart
/// Then open the PNG under test/widgets/_capture/ and LOOK.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/snow_scene.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';

// The CJK font so the JA surface shows real Japanese (not tofu) — same approach
// the existing place-entry + family-area captures use.
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

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // path_provider is hit by the saved-place store; stub it so init does not
    // throw a MissingPluginException in the test environment (same as the
    // snow_scene pretrip lift test).
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

  testWidgets('snow_scene pre-trip surface — JA capture (in-app, shell-hosted)',
      (tester) async {
    final hasCjk = await _loadCjk();
    // ignore: avoid_print
    print('CJK font loaded: $hasCjk');
    if (!hasCjk) {
      markTestSkipped('No Noto CJK font on this host — skipping JA capture.');
      return;
    }

    const ja = BriefingStrings.ja;

    // Echo the EXACT Japanese the shell chrome should show, so the PNG and the
    // report can be checked against the same source of truth.
    // ignore: avoid_print
    print('--- SHELL CHROME (ja) ---');
    // ignore: avoid_print
    print('  AppBar title:       ${ja.beforeYouDrive}');
    // ignore: avoid_print
    print('  Start-drive button: ${ja.startDrive}');
    // ignore: avoid_print
    print('--- BRIEFING STRUCTURE (ja) ---');
    // ignore: avoid_print
    print('  before-you-leave header: ${ja.beforeYouLeave}');
    for (final c in ja.checklist) {
      // ignore: avoid_print
      print('    checklist: $c');
    }
    // ignore: avoid_print
    print('  trip-required title:    ${ja.tripRequiredTitle}');
    // ignore: avoid_print
    print('  winter header (圧雪):   ${ja.winterHeader('compactedSnow')}');
    // ignore: avoid_print
    print('  winter footer:          ${ja.winterFooter}');
    // ignore: avoid_print
    print('  simulated caption:      ${ja.simulatedForecastCaption}');
    // ignore: avoid_print
    print('--- PLACE-ENTRY TILE (ja, unset) ---');
    // ignore: avoid_print
    print('  set-area button:        ${ja.setDestinationAreaButton}');
    // ignore: avoid_print
    print('  local-only note:        ${ja.placeEntryLocalOnlyNote}');
    // ignore: avoid_print
    print('  forecast-off note:      ${ja.placeEntryForecastOffNote}');

    // A tall surface so nothing clips: the briefing card (verdict + chips +
    // switch + 5-item checklist + winter guidance + source line) plus the
    // place-entry tile make this long.
    final boundaryKey = GlobalKey();
    tester.view.physicalSize = const Size(640, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        // Force Japanese, exactly as HER device would resolve it.
        locale: const Locale('ja'),
        // The same delegates + supported locales the shipped SnowSceneApp wires,
        // so the briefing + chrome resolve to Japanese instead of leaking
        // English (the D4 reach failure this verifies is fixed).
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('ja')],
        // The shipped snow-scene theme (dark, M3) so the PNG shows what HER
        // actually sees, PLUS the CJK font family so Japanese renders as glyphs.
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1A73E8),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
          fontFamily: 'NotoSansCJK',
        ),
        // The REAL shell — its default pretrip leg builds the AppBar + button +
        // PretripScreen(compactedSnow). RepaintBoundary at the home level so the
        // whole Scaffold (AppBar included) is captured.
        home: RepaintBoundary(
          key: boundaryKey,
          child: const SnowSceneShell(),
        ),
      ),
    );

    // Let the screen's async initState work settle: the offline winter-guidance
    // asset read (WinterKnowledge.fromAsset) and the guarded saved-place load.
    await tester.pump();
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    await tester.pumpAndSettle();

    // Confirm the localized chrome actually reached the tree (cheap guard that
    // the PNG is of the Japanese surface, not a silent English fallback).
    expect(find.text(BriefingStrings.ja.beforeYouDrive), findsWidgets,
        reason: 'the AppBar title must render "出発前に" under ja');
    expect(find.text(BriefingStrings.ja.startDrive), findsOneWidget,
        reason: 'the Start-drive button must render "運転を開始" under ja');
    expect(find.text(BriefingStrings.en.beforeYouDrive), findsNothing,
        reason: 'no English "Before you drive" chrome should leak under ja');

    await tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      expect(bytes, isNotNull);
      final dir = Directory('test/widgets/_capture')..createSync(recursive: true);
      final file = File('${dir.path}/snow_scene_pretrip_ja.png');
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(file.lengthSync(), greaterThan(0));
      // ignore: avoid_print
      print('CAPTURE snow_scene_pretrip_ja: ${file.absolute.path} '
          '${file.lengthSync()} bytes ${image.width}x${image.height}');
    });

    // Surface any non-benign exception (benign plugin/asset misses degrade
    // honestly inside PretripScreen's own try/catch).
    final ex = tester.takeException();
    if (ex != null) {
      // ignore: avoid_print
      print('NOTE non-fatal exception drained: $ex');
    }
  });
}
