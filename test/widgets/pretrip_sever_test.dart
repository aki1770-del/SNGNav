// SEVER verification (own file): the lift replaced the host-private
// `_assessment.surfaceState` feeding the winter-guidance card with the public
// `PretripScreen.surfaceState` constructor param. The pre-lift hardcoded default
// assessment was COMPACTED SNOW; so mounting [PretripScreen] with
// `surfaceState: RoadSurfaceState.blackIce` and seeing the `If the road is black
// ice` winter-guidance header (and NOT `compacted snow`) proves the parameter
// flows — the `_assessment.surfaceState` → `widget.surfaceState` severance.
//
// This lives in its OWN test file because the offline winter-knowledge asset
// (loaded via `rootBundle`) is only served on the process-first PretripScreen
// mount in the flutter_test environment; each test file runs in its own isolate,
// so this file's single mount loads the asset deterministically.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:sngnav_snow_scene/widgets/pretrip_screen.dart';

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

  testWidgets(
    'SEVER: the winter card follows widget.surfaceState (blackIce, not the '
    'pre-lift compactedSnow default)',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en'), Locale('ja')],
          home: const Scaffold(
            body: PretripScreen(surfaceState: RoadSurfaceState.blackIce),
          ),
        ),
      );

      // The offline winter-knowledge guidance loads via rootBundle (a real async
      // asset read) which the fake-async test zone blocks — turn the real event
      // loop with runAsync between pumps to let it complete.
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () async => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
      // Drain benign FlutterMap/plugin async noise; rethrow a real defect.
      final ex = tester.takeException();
      if (ex != null) {
        final s = ex.toString();
        final benign =
            ex is MissingPluginException ||
            s.contains('getTileUrl') ||
            s.contains('TileProvider') ||
            s.contains('flutter_map');
        if (!benign) throw ex as Object;
      }

      // The winter-guidance header is `If the road is <human surface state>`.
      // blackIce was passed via widget.surfaceState; the pre-lift code would have
      // shown `compacted snow` (the default assessment's surface). Seeing
      // `black ice` and NOT `compacted snow` proves the severance.
      expect(
        find.textContaining('black ice'),
        findsWidgets,
        reason:
            'the blackIce winter-guidance header must render from '
            'widget.surfaceState',
      );
      expect(
        find.textContaining('compacted snow'),
        findsNothing,
        reason: 'the pre-lift compactedSnow default must NOT leak through',
      );
    },
  );
}
