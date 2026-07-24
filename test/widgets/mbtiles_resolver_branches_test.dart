// OPS-068 review MUSTs (2026-07-19): the three resolver branches that are
// UNREACHABLE under plain `flutter test` (the repo-relative candidate always
// exists) — forced via the @visibleForTesting seams:
//   1. EXTRACTION: no candidates → the bundled asset is extracted to the
//      writable base and the map loads from the extracted file. This is the
//      path that actually runs on the ivi-homescreen target.
//   2. HONEST ABSENCE: no candidates AND extraction base unusable → the ja+en
//      unavailable message shows, NO TileLayer, no crash, no online fetch.
//   3. ENV OVERRIDE: SNGNAV_MBTILES wins over candidates (the target unit
//      sets it to the flutter_assets path).
//
// Run: flutter test test/widgets/mbtiles_resolver_branches_test.dart
import 'dart:io';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/main.dart' as main_app;

void main() {
  tearDown(() {
    main_app.debugMbtilesCandidatesOverride = null;
    main_app.debugMbtilesEnvOverride = null;
    main_app.debugMbtilesExtractBaseOverride = null;
  });

  Future<void> pumpToMapView(WidgetTester tester) async {
    await tester.pumpWidget(const main_app.SNGNavGettingStarted());
    await tester.pump();
    await tester.tap(find.text('2D map'));
    await tester.pump();
    // Let the real-async resolution (file IO / asset load / sqlite) land.
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 250)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('EXTRACTION branch: with no file candidates the bundled asset '
      'is extracted to the writable base and the map loads from it', (
    tester,
  ) async {
    final base = Directory.systemTemp.createTempSync('sngnav_extract_test_');
    addTearDown(() => base.deleteSync(recursive: true));
    main_app.debugMbtilesCandidatesOverride = const [];
    main_app.debugMbtilesEnvOverride = const {}; // no SNGNAV_MBTILES, no HOME
    main_app.debugMbtilesExtractBaseOverride = base;

    await pumpToMapView(tester);

    // The extracted file exists under OUR base with the asset's real size —
    // proof the rootBundle→file path itself ran (not a repo candidate).
    final extracted = File('${base.path}/akita_offline.mbtiles');
    expect(extracted.existsSync(), isTrue,
        reason: 'asset must be extracted to the injected writable base');
    final assetLen =
        File('assets/tiles/akita_offline.mbtiles').lengthSync();
    expect(extracted.lengthSync(), assetLen);
    expect(find.textContaining('MBTiles loaded'), findsOneWidget);
  });

  testWidgets('HONEST-ABSENCE branch: every route dead → ja+en message, '
      'no TileLayer, no crash', (tester) async {
    // A FILE path as the "base" makes createSync(recursive) fail for every
    // candidate dir, so extraction cannot succeed anywhere.
    final blocker = File(
      '${Directory.systemTemp.path}/sngnav_absence_blocker_${DateTime.now().microsecondsSinceEpoch}',
    )..writeAsStringSync('x');
    addTearDown(() => blocker.deleteSync());
    main_app.debugMbtilesCandidatesOverride = const [];
    main_app.debugMbtilesEnvOverride = const {};
    main_app.debugMbtilesExtractBaseOverride = Directory('${blocker.path}/sub');

    await pumpToMapView(tester);

    expect(tester.takeException(), isNull);
    expect(find.textContaining('オフライン地図が利用できません'), findsWidgets);
    expect(find.byType(TileLayer), findsNothing);
  });

  testWidgets('ENV-OVERRIDE branch: SNGNAV_MBTILES wins over candidates', (
    tester,
  ) async {
    // Point the env var at the real archive via a copied temp file, with the
    // normal candidates disabled — resolution must take the env path.
    final tmp = Directory.systemTemp.createTempSync('sngnav_env_test_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final envFile = File('${tmp.path}/from_env.mbtiles');
    File('assets/tiles/akita_offline.mbtiles').copySync(envFile.path);
    main_app.debugMbtilesCandidatesOverride = const [];
    main_app.debugMbtilesEnvOverride = {'SNGNAV_MBTILES': envFile.path};
    // No extract base: if the env path were ignored, extraction would need
    // HOME (absent) → absence message; 'MBTiles loaded' proves the env won.

    await pumpToMapView(tester);

    expect(find.textContaining('MBTiles loaded'), findsOneWidget);
    expect(find.byType(TileLayer), findsOneWidget);
  });
}
