/// Tests for AlertExplainerExpandableSheet (0.9.0).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  group('AlertExplainerExpandableSheet', () {
    testWidgets('default-EXPANDED for ageingRural / foreignTouristSnowZone / '
        'noviceUrban; default-COLLAPSED for the other three profiles', (
      tester,
    ) async {
      const expandedProfiles = <DriverProfile>[
        DriverProfile.ageingRural,
        DriverProfile.foreignTouristSnowZone,
        DriverProfile.noviceUrban,
      ];
      const collapsedProfiles = <DriverProfile>[
        DriverProfile.agriculturalForestry,
        DriverProfile.snowZoneExperienced,
        DriverProfile.professional,
      ];

      for (final p in expandedProfiles) {
        expect(
          AlertExplainerExpandableSheet.defaultExpansionForProfile(p),
          isTrue,
          reason: '$p should default-EXPANDED',
        );
      }
      for (final p in collapsedProfiles) {
        expect(
          AlertExplainerExpandableSheet.defaultExpansionForProfile(p),
          isFalse,
          reason: '$p should default-COLLAPSED',
        );
      }
    });

    testWidgets('expanded state renders action text VERBATIM '
        '(Article 17 (β) verbatim-relay)', (tester) async {
      const condition = RoadSurfaceCondition.ice;
      const profile = DriverProfile.ageingRural;
      final expectedAction = AlertExplainer.forConditionAndProfile(
        condition,
        profile,
      ).action;

      await tester.pumpWidget(
        _wrap(
          const AlertExplainerExpandableSheet(
            condition: condition,
            profile: profile,
          ),
        ),
      );
      // ageingRural defaults to EXPANDED; the verbatim action text
      // should be present in the rendered tree.
      expect(find.text(expectedAction), findsOneWidget);
    });

    testWidgets('collapsed state HIDES action text but does not paraphrase', (
      tester,
    ) async {
      const condition = RoadSurfaceCondition.ice;
      const profile = DriverProfile.professional;
      final expectedAction = AlertExplainer.forConditionAndProfile(
        condition,
        profile,
      ).action;

      await tester.pumpWidget(
        _wrap(
          const AlertExplainerExpandableSheet(
            condition: condition,
            profile: profile,
          ),
        ),
      );
      // professional defaults to COLLAPSED; action text not rendered.
      expect(find.text(expectedAction), findsNothing);
      // Tapping toggles to expanded; verbatim text now visible.
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(find.text(expectedAction), findsOneWidget);
    });

    testWidgets('integrator override via defaultExpanded forces collapsed for '
        'ageingRural', (tester) async {
      const condition = RoadSurfaceCondition.snow;
      const profile = DriverProfile.ageingRural;
      final expectedAction = AlertExplainer.forConditionAndProfile(
        condition,
        profile,
      ).action;

      await tester.pumpWidget(
        _wrap(
          const AlertExplainerExpandableSheet(
            condition: condition,
            profile: profile,
            defaultExpanded: false,
          ),
        ),
      );
      expect(find.text(expectedAction), findsNothing);
    });

    testWidgets('onExpansionChanged fires on toggle', (tester) async {
      const condition = RoadSurfaceCondition.wet;
      const profile = DriverProfile.snowZoneExperienced;
      final calls = <bool>[];

      await tester.pumpWidget(
        _wrap(
          AlertExplainerExpandableSheet(
            condition: condition,
            profile: profile,
            onExpansionChanged: calls.add,
          ),
        ),
      );
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(calls, [true]);
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(calls, [true, false]);
    });

    testWidgets('default sourceLine is exactly \'AlertExplainer\' and no '
        'rendered text names JAF, MLIT or NEXCO, in both states', (
      tester,
    ) async {
      // 0.9.7 changed the default from 'AlertExplainer (JAF / MLIT / NEXCO)'.
      // Those organisations did not write the action strings, so a default
      // that names them again must fail here.
      final attribution = RegExp('JAF|MLIT|NEXCO');
      const condition = RoadSurfaceCondition.ice;

      expect(
        const AlertExplainerExpandableSheet(
          condition: condition,
          profile: DriverProfile.professional,
        ).sourceLine,
        'AlertExplainer',
      );

      List<String> renderedTexts() => tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();

      for (final profile in DriverProfile.values) {
        await tester.pumpWidget(
          _wrap(
            AlertExplainerExpandableSheet(
              key: ValueKey(profile),
              condition: condition,
              profile: profile,
            ),
          ),
        );
        for (var state = 0; state < 2; state++) {
          final expanded = find.text(
            AlertExplainer.forConditionAndProfile(condition, profile).action,
          ).evaluate().isNotEmpty;
          // The source line renders once collapsed, twice expanded.
          expect(
            find.text('AlertExplainer'),
            findsNWidgets(expanded ? 2 : 1),
            reason: '$profile expanded=$expanded',
          );
          for (final text in renderedTexts()) {
            expect(
              attribution.hasMatch(text),
              isFalse,
              reason: '$profile expanded=$expanded rendered "$text"',
            );
          }
          await tester.tap(find.byType(InkWell));
          await tester.pump();
        }
      }
    });
  });
}
