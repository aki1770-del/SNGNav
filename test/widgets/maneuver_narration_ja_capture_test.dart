// Render-and-SEE capture of Japanese maneuver narration in the REAL
// RouteProgressBar (OPS-066 / L32 observation-grade verification).
//
// This is HER glanceable driving cue: icon from maneuver.type + text from
// maneuver.instruction. The captures verify, in pixels:
//   1. The mock-demo merge maneuver (#2) — the icon/text coherence fix
//      (type 'merge' now matches the 合流 text; it was a right-turn arrow
//      beside "merge" text before the review caught it).
//   2. A sharp hairpin narrated by the REAL ManeuverLocalizer — 鋭角に右折
//      (the review's MUST fix: 大きく read as a WIDE/gentle arc, the inverse
//      severity; 鋭角 preserves the tighten-up/slow-down cue on snow).
//   3. A multi-exit roundabout with its exit ordinal — 2番目の出口 (a wrong
//      exit in low visibility is a real misdirection).
//
// Run:
//   flutter test test/widgets/maneuver_narration_ja_capture_test.dart
// Then LOOK:
//   test/widgets/_capture/maneuver_narration_ja.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';
// Internal import: the localizer is deliberately not in the public barrel (§9).
import 'package:routing_engine/src/maneuver_localizer.dart';

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

NavigationRoute _routeWith(List<NavigationManeuver> maneuvers) =>
    NavigationRoute(
      shape: const [LatLng(39.71, 140.10), LatLng(39.65, 140.18)],
      maneuvers: maneuvers,
      totalDistanceKm: 28.3,
      totalTimeSeconds: 2000,
      summary: '28.3 km, 33 min',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('capture: RouteProgressBar Japanese narration (merge fix, '
      '鋭角 sharp turn, roundabout exit ordinal)', (tester) async {
    final cjk = await _loadCjk();
    expect(cjk, isTrue, reason: 'CJK font must load or the JA renders as tofu');

    // 1. The REAL mock-demo merge maneuver (snow_scene.dart index 2, post-fix).
    const merge = NavigationManeuver(
      index: 2,
      instruction: '国道153号に合流し岡崎方面へ',
      type: 'merge',
      lengthKm: 4.0,
      timeSeconds: 210,
      position: LatLng(35.1376, 137.0000),
    );

    // 2. A sharp hairpin narrated by the REAL localizer (the MUST fix).
    final sharpText = ManeuverLocalizer.localize(
      language: 'ja-JP',
      type: 'sharp_right',
      streetName: '山道',
    );
    final sharp = NavigationManeuver(
      index: 1,
      instruction: sharpText,
      type: 'sharp_right',
      lengthKm: 0.9,
      timeSeconds: 120,
      position: const LatLng(39.70, 140.12),
    );

    // 3. Multi-exit roundabout with the exit ordinal (the misdirection fix).
    final roundaboutText = ManeuverLocalizer.localize(
      language: 'ja-JP',
      type: 'roundabout_enter',
      streetName: '国道153号',
      roundaboutExit: 2,
    );
    final roundabout = NavigationManeuver(
      index: 3,
      instruction: roundaboutText,
      type: 'roundabout_enter',
      lengthKm: 0.5,
      timeSeconds: 60,
      position: const LatLng(39.69, 140.14),
    );

    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'NotoSansCJK', useMaterial3: true),
        home: Scaffold(
          body: RepaintBoundary(
            key: boundaryKey,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RouteProgressBar(
                    status: RouteProgressStatus.active,
                    route: _routeWith([merge]),
                    currentManeuverIndex: 0,
                    destinationLabel: '東岡崎駅',
                  ),
                  RouteProgressBar(
                    status: RouteProgressStatus.active,
                    route: _routeWith([sharp]),
                    currentManeuverIndex: 0,
                    destinationLabel: '東岡崎駅',
                  ),
                  RouteProgressBar(
                    status: RouteProgressStatus.active,
                    route: _routeWith([roundabout]),
                    currentManeuverIndex: 0,
                    destinationLabel: '東岡崎駅',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    // Pixel assertions of the fixed text actually reaching the widget.
    expect(find.text('国道153号に合流し岡崎方面へ'), findsOneWidget);
    expect(find.text('山道方面へ鋭角に右折'), findsOneWidget);
    expect(find.text('ロータリーに入り2番目の出口で国道153号方面へ進む'), findsOneWidget);

    // Capture the PNG for the go-and-LOOK step. The real-async image work
    // must run inside tester.runAsync — awaiting it bare in the fake-async
    // test zone deadlocks under load (established repo capture pattern).
    await tester.runAsync(() async {
      final boundary = boundaryKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('test/widgets/_capture/maneuver_narration_ja.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      expect(out.lengthSync(), greaterThan(10000),
          reason: 'capture must be a real render, not a blank frame');
    });
  });
}
