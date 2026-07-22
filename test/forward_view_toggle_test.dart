import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';
import 'package:sngnav_snow_scene/main.dart' as main_app;

/// FDD — Forward-view toggle integration test.
///
/// Verifies the in-product view-mode toggle wires the glanceable 3D
/// [SnowScene3DView] forward-view and the 2D map together on the home screen:
///   * default view is the FORWARD glance scene (purpose: on the IVI the
///     compositor owns layout and the app cannot self-foreground — the boot
///     default IS the glance; ratified Lane-3, 2026-07-19);
///   * tapping "2D map" shows the map and hides the forward-view;
///   * tapping "Forward" toggles back.
void main() {
  group('OfflineMapPage — forward-view toggle', () {
    testWidgets('defaults to the forward glance scene (map absent)', (
      tester,
    ) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());
      await tester.pump();

      expect(find.byType(SnowScene3DView), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets('tapping 2D map shows the map and hides the forward-view', (
      tester,
    ) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());
      await tester.pump();

      // The toggle control is present (both segment labels visible).
      expect(find.text('2D map'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);

      await tester.tap(find.text('2D map'));
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(SnowScene3DView), findsNothing);
    });

    testWidgets(
      'toggling back to Forward restores the glance scene and hides the map',
      (tester) async {
        await tester.pumpWidget(const main_app.SNGNavGettingStarted());
        await tester.pump();

        await tester.tap(find.text('2D map'));
        await tester.pump();
        expect(find.byType(FlutterMap), findsOneWidget);

        await tester.tap(find.text('Forward'));
        await tester.pump();

        expect(find.byType(SnowScene3DView), findsOneWidget);
        expect(find.byType(FlutterMap), findsNothing);
      },
    );
  });
}
