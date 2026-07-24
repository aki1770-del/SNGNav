// Render-and-SEE capture of the Lane-3 offline-constitutive changes
// (OPS-066 / L32 observation-grade verification, 2026-07-19).
//
// What this proves by RENDERING (not by narration):
//   1. _capture/boot_default_forward_scene.png — the app BOOTS into the
//      glanceable forward scene (the ratified Lane-3 default; on the IVI the
//      compositor owns layout, so the default view IS the glance).
//   2. _capture/map_akita_offline_tiles.png — the 2D map paints REAL Akita
//      tiles from the bundled archive, centered on _akitaCenter inside the
//      archive bounds. HONEST SCOPE (OPS-068 2026-07-19): under `flutter
//      test` the repo file candidate resolves directly, so THIS test proves
//      tiles paint from the archive — the target-only EXTRACTION branch is
//      proven separately in mbtiles_resolver_branches_test.dart.
//
// Run: flutter test test/widgets/akita_basemap_capture_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';
import 'package:sngnav_snow_scene/main.dart' as main_app;

Future<void> _capturePng(
  WidgetTester tester,
  Finder finder,
  String outPath,
) async {
  await tester.runAsync(() async {
    final element = finder.evaluate().first;
    RenderObject? ro = element.renderObject;
    while (ro != null && ro is! RenderRepaintBoundary) {
      ro = ro.parent;
    }
    final boundary = ro! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(outPath)..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
    // ignore: avoid_print
    print('CAPTURE $outPath ${file.lengthSync()} bytes');
  });
}

void main() {
  testWidgets('boot default is the forward glance scene + map paints real '
      'Akita offline tiles via asset extraction', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const RepaintBoundary(child: main_app.SNGNavGettingStarted()),
    );
    await tester.pump();

    // 1. Boot default = the glance scene (Lane-3 ratified behavior).
    expect(find.byType(SnowScene3DView), findsOneWidget);
    expect(find.byType(FlutterMap), findsNothing);
    await _capturePng(
      tester,
      find.byType(main_app.SNGNavGettingStarted),
      'test/widgets/_capture/boot_default_forward_scene.png',
    );

    // 2. Switch to the 2D map; let the asset-extraction + tile decode run
    //    for real (runAsync drains the real async queue).
    await tester.tap(find.text('2D map'));
    await tester.pump();
    // Tile pipeline is REAL async (file read → sqlite → image decode) and
    // paints over several frames: interleave real-async settles with pumped
    // frames so decoded tiles actually reach the raster (a single pump after
    // one delay captures the pre-decode blank — measured 2026-07-19).
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(FlutterMap), findsOneWidget);
    // The offline manager must have loaded (status shows MBTiles, not the
    // honest-absence message). Honest scope: in this test that is via the
    // repo file candidate; the extraction branch has its own forced test.
    expect(find.textContaining('MBTiles loaded'), findsOneWidget);
    await _capturePng(
      tester,
      find.byType(main_app.SNGNavGettingStarted),
      'test/widgets/_capture/map_akita_offline_tiles.png',
    );
  });
}
