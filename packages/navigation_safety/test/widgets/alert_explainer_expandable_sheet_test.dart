/// Tests for AlertExplainerExpandableSheet (0.9.0).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

Widget _wrap(Widget child) {
  return MaterialApp(home: Scaffold(body: Center(child: child)));
}

void main() {
  group('AlertExplainerExpandableSheet', () {
    testWidgets(
        'default-EXPANDED for ageingRural / foreignTouristSnowZone / '
        'noviceUrban; default-COLLAPSED for the other three profiles',
        (tester) async {
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

    testWidgets(
        'expanded state renders action text VERBATIM '
        '(Article 17 (β) verbatim-relay)',
        (tester) async {
      const condition = RoadSurfaceCondition.ice;
      const profile = DriverProfile.ageingRural;
      final expectedAction =
          AlertExplainer.forConditionAndProfile(condition, profile).action;

      await tester.pumpWidget(_wrap(
        const AlertExplainerExpandableSheet(
          condition: condition,
          profile: profile,
        ),
      ));
      // ageingRural defaults to EXPANDED; the verbatim action text
      // should be present in the rendered tree.
      expect(find.text(expectedAction), findsOneWidget);
    });

    testWidgets(
        'collapsed state HIDES action text but does not paraphrase',
        (tester) async {
      const condition = RoadSurfaceCondition.ice;
      const profile = DriverProfile.professional;
      final expectedAction =
          AlertExplainer.forConditionAndProfile(condition, profile).action;

      await tester.pumpWidget(_wrap(
        const AlertExplainerExpandableSheet(
          condition: condition,
          profile: profile,
        ),
      ));
      // professional defaults to COLLAPSED; action text not rendered.
      expect(find.text(expectedAction), findsNothing);
      // Tapping toggles to expanded; verbatim text now visible.
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(find.text(expectedAction), findsOneWidget);
    });

    testWidgets(
        'integrator override via defaultExpanded forces collapsed for '
        'ageingRural', (tester) async {
      const condition = RoadSurfaceCondition.snow;
      const profile = DriverProfile.ageingRural;
      final expectedAction =
          AlertExplainer.forConditionAndProfile(condition, profile).action;

      await tester.pumpWidget(_wrap(
        const AlertExplainerExpandableSheet(
          condition: condition,
          profile: profile,
          defaultExpanded: false,
        ),
      ));
      expect(find.text(expectedAction), findsNothing);
    });

    testWidgets('onExpansionChanged fires on toggle', (tester) async {
      const condition = RoadSurfaceCondition.wet;
      const profile = DriverProfile.snowZoneExperienced;
      final calls = <bool>[];

      await tester.pumpWidget(_wrap(
        AlertExplainerExpandableSheet(
          condition: condition,
          profile: profile,
          onExpansionChanged: calls.add,
        ),
      ));
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(calls, [true]);
      await tester.tap(find.byType(InkWell));
      await tester.pump();
      expect(calls, [true, false]);
    });
  });
}
