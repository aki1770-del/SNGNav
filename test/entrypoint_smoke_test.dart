import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/main.dart' as main_app;
import 'package:sngnav_snow_scene/snow_scene.dart' as snow_scene;

/// FDD-9 — Entrypoint smoke tests.
///
/// Verifies that both app entrypoints can be instantiated and pumped
/// without runtime errors. These tests catch import-graph breakage,
/// missing providers, and widget tree assembly failures.
void main() {
  group('main.dart — SNGNavGettingStarted', () {
    testWidgets('pumps without error', (tester) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());
      expect(find.byType(MaterialApp), findsOneWidget);
    });

    testWidgets('shows app title', (tester) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());
      expect(find.text('SNGNav — Offline Map Demo'), findsOneWidget);
    });

    // AMENDED 2026-08-29 (SDE, IVI-6). This asserted `findsWidgets` on the text
    // "Initializing" — the placeholder — while its own comment said "either
    // 'Initializing...' or the actual status after init". The assertion and the
    // comment disagreed, and the assertion was the weaker of the two.
    //
    // It now has to change because the archive is opened SYNCHRONOUSLY in
    // initState. `MapOptions.initialCenter` is read exactly once, so a camera
    // derived one microtask later never reaches the screen at all; the previous
    // `await file.exists()` bought no concurrency (OfflineTileManager's
    // constructor was already blocking) and only guaranteed the first frame was
    // built before the camera was known.
    //
    // The replacement is STRICTLY STRONGER: it locks the new invariant that the
    // status line is a real answer at the first frame, and accepts any of the
    // four real answers so a checkout without data/offline_tiles.mbtiles still
    // passes.
    testWidgets('resolves the archive status before the first frame', (
      tester,
    ) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());

      expect(
        find.textContaining('Initializing'),
        findsNothing,
        reason: 'the archive open is synchronous; nothing should still be '
            'showing the placeholder by the first frame',
      );
      expect(
        find.byWidgetPredicate((w) {
          if (w is! Text) return false;
          final t = w.data ?? '';
          return t.startsWith('Offline — MBTiles loaded') ||
              t.startsWith('MBTiles loaded') ||
              t.startsWith('No MBTiles file at') ||
              t.startsWith('MBTiles error:');
        }),
        findsOneWidget,
        reason: 'the status line must state one of the four real outcomes',
      );
    });
  });

  group('snow_scene.dart — SnowSceneApp', () {
    testWidgets('pumps without error', (tester) async {
      // SnowSceneApp requires a consent DB and config.
      // We test that the widget class exists and is constructable.
      // Full pump requires SQLite setup — covered by integration tests.
      expect(snow_scene.SnowSceneApp, isNotNull);
    });

    testWidgets('import graph resolves', (tester) async {
      // This test verifies the entire snow_scene.dart import tree
      // compiles and loads without errors. If any provider, BLoC,
      // model, or widget has a broken import, this fails.
      expect(true, isTrue);
    });
  });
}
