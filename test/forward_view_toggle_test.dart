import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/fluorite/snow_scene_3d_view.dart';
import 'package:sngnav_snow_scene/main.dart' as main_app;

/// FDD — Forward-view toggle integration test.
///
/// Verifies the in-product view-mode toggle wires the existing 2D map and the
/// 3D [SnowScene3DView] forward-view together on the home screen:
///   * default view is the 2D map (FlutterMap present, forward-view absent);
///   * tapping the "Forward" segment shows the forward-view and hides the map;
///   * tapping "2D map" toggles back.
void main() {
  group('OfflineMapPage — forward-view toggle', () {
    testWidgets('defaults to the 2D map (forward-view absent)', (tester) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());
      await tester.pump();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.byType(SnowScene3DView), findsNothing);
    });

    testWidgets('tapping Forward shows the 3D forward-view and hides the map', (
      tester,
    ) async {
      await tester.pumpWidget(const main_app.SNGNavGettingStarted());
      await tester.pump();

      // The toggle control is present (both segment labels visible).
      expect(find.text('2D map'), findsOneWidget);
      expect(find.text('Forward'), findsOneWidget);

      await tester.tap(find.text('Forward'));
      await tester.pump();

      expect(find.byType(SnowScene3DView), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
    });

    testWidgets(
      'toggling back to 2D map restores the map and hides forward-view',
      (tester) async {
        await tester.pumpWidget(const main_app.SNGNavGettingStarted());
        await tester.pump();

        await tester.tap(find.text('Forward'));
        await tester.pump();
        expect(find.byType(SnowScene3DView), findsOneWidget);

        await tester.tap(find.text('2D map'));
        await tester.pump();

        expect(find.byType(FlutterMap), findsOneWidget);
        expect(find.byType(SnowScene3DView), findsNothing);
      },
    );
  });
}
