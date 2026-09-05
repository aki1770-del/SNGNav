// Widget + dignity tests for the FAMILY-THREAD destination-area section.
//
// This surface answers "what conditions will SHE face in her mother's AREA if
// she drives there" — a PUBLIC-WEATHER-AT-A-PLACE read. It watches no person,
// claims no road, and is NOT a second briefing card (no switch, no verdict, no
// delay/go-no-go). These tests pin those binding boundaries to the rendered
// tree, and pin the dest fetch's on-demand-only (no-background) wiring to the
// app source structure.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pretrip_decision_advisor/pretrip_decision_advisor.dart';
import 'package:sngnav_snow_scene/widgets/briefing_strings.dart';
import 'package:sngnav_snow_scene/widgets/family_area_card.dart';

const _personTokens = <String>[
  'Mom',
  'お母さん',
  'arrived',
  '到着',
  'is she',
  'safe?',
  '無事',
  '見守り',
  'presence', // no rendered string contains it; 'route'/'経路' would
  // false-positive on the legitimate disclaimer "not road or route status",
  // so they are NOT swept against the rendered tree here.
];

AreaConditionRead _read() => const AreaConditionRead(
  areaHazard: HourHazard.elevated,
  forecastCovered: true,
  officialWarningVerbatim: '大雪警報',
  warningCheckAvailable: true,
  measuredVisibilityMeters: 80,
  visibilityStationName: '秋田',
  visibilityDistanceKm: 5,
  areaLabel: 'Akita',
);

Future<void> _pump(
  WidgetTester tester, {
  required BriefingStrings strings,
  required PretripMessages messages,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FamilyAreaCard(
            read: _read(),
            messages: messages,
            strings: strings,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

/// Pump an arbitrary read (for the honest-gap cases that the fixed [_read]
/// fixture does not exercise).
Future<void> _pumpRead(
  WidgetTester tester,
  AreaConditionRead read, {
  BriefingStrings strings = BriefingStrings.en,
  PretripMessages messages = PretripMessages.en,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: FamilyAreaCard(
            read: read,
            messages: messages,
            strings: strings,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('renders place label + chips + honesty note (en)', (
    tester,
  ) async {
    await _pump(
      tester,
      strings: BriefingStrings.en,
      messages: PretripMessages.en,
    );

    expect(find.text('Conditions in the destination area'), findsOneWidget);
    expect(find.text('Area: Akita'), findsOneWidget);
    expect(
      find.textContaining('Official winter warning or advisory in effect'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Forecast hazard for this area'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Nearest measured visibility ~80 m'),
      findsOneWidget,
    );
    expect(find.textContaining('not road or route status'), findsOneWidget);
  });

  testWidgets(
    'is NOT a second briefing card: no switch, no wait/delay/go-no-go',
    (tester) async {
      await _pump(
        tester,
        strings: BriefingStrings.en,
        messages: PretripMessages.en,
      );

      expect(find.byType(SwitchListTile), findsNothing);
      for (final banned in const ['wait', 'delay', "don't go", 'go-no-go']) {
        expect(
          find.textContaining(banned),
          findsNothing,
          reason: 'the area section must not urge/deter a trip ($banned)',
        );
      }
    },
  );

  testWidgets('reaches her mother in Japanese, with no person token', (
    tester,
  ) async {
    await _pump(
      tester,
      strings: BriefingStrings.ja,
      messages: PretripMessages.ja,
    );

    expect(find.text('目的地周辺の状況'), findsOneWidget);
    expect(find.textContaining('道路や経路の状況ではありません'), findsOneWidget);

    for (final token in _personTokens) {
      expect(
        find.textContaining(token),
        findsNothing,
        reason: 'no person token may appear ($token)',
      );
    }
  });

  // Honest-gap rendering: an uncovered window / a failed warning-check / no
  // measured visibility must render an HONEST gap, never an implied "all clear".
  testWidgets('honest gap: forecast not covered renders the not-covered line', (
    tester,
  ) async {
    await _pumpRead(
      tester,
      const AreaConditionRead(
        areaHazard: HourHazard.clear,
        forecastCovered: false,
        officialWarningVerbatim: null,
        warningCheckAvailable: true,
        measuredVisibilityMeters: null,
        visibilityStationName: null,
        visibilityDistanceKm: null,
        areaLabel: 'Akita',
      ),
    );

    expect(
      find.textContaining('No forecast available for this area'),
      findsOneWidget,
    );
    // No band word may be implied when the window is not covered.
    expect(find.textContaining('Forecast hazard for this area'), findsNothing);
  });

  testWidgets(
    'honest gap: warning-check unavailable shows the caveat, not "no"',
    (tester) async {
      await _pumpRead(
        tester,
        const AreaConditionRead(
          areaHazard: HourHazard.caution,
          forecastCovered: true,
          officialWarningVerbatim: null,
          warningCheckAvailable: false,
          measuredVisibilityMeters: null,
          visibilityStationName: null,
          visibilityDistanceKm: null,
          areaLabel: 'Akita',
        ),
      );

      expect(find.textContaining('may be in effect that'), findsOneWidget);
      // Must NOT assert a verified negative when the check did not happen.
      expect(find.textContaining('No active snow warning'), findsNothing);
    },
  );

  testWidgets(
    'honest gap: no measured visibility shows the none line, no number',
    (tester) async {
      await _pumpRead(
        tester,
        const AreaConditionRead(
          areaHazard: HourHazard.caution,
          forecastCovered: true,
          officialWarningVerbatim: null,
          warningCheckAvailable: true,
          measuredVisibilityMeters: null,
          visibilityStationName: null,
          visibilityDistanceKm: null,
          areaLabel: 'Akita',
        ),
      );

      expect(
        find.textContaining('No measured visibility available for this area'),
        findsOneWidget,
      );
      expect(find.textContaining('Nearest measured visibility'), findsNothing);
    },
  );

  test('areaResolutionNote states the claim ceiling (en + ja)', () {
    expect(
      BriefingStrings.en.areaResolutionNote,
      contains('not road or route status'),
    );
    expect(BriefingStrings.ja.areaResolutionNote, contains('道路や経路の状況ではありません'));
  });

  // No-background guard (by source structure): the dest fetch must be invoked
  // ONLY from initState AND from the single driver-action setter (_setDestination),
  // with NO Timer/Stream/scheduled refresh — background polling of "her area"
  // would be 見守り-by-proxy. The driver-action setter is the in-app typed-place
  // entry that lets the driver set/change the destination area herself; it is a
  // ONE-SHOT user action, not a schedule. The section is still guarded by
  // `if (_destAreaRead != null)`.
  test('dest fetch fires ONLY from initState + the single driver-action setter, '
      'never self-scheduled', () {
    // The dest-path orchestration was lifted into the shared PretripScreen.
    final src = File('lib/widgets/pretrip_screen.dart').readAsStringSync();

    // EXACTLY TWO call sites: initState (first read) + _setDestination (the the driver-
    // action re-fetch). Count every `_initDestAreaCondition(` (open-paren — so a
    // closure-wrapped re-invocation such as
    // `Timer.periodic(d, (_) => _initDestAreaCondition())` is also counted) and
    // subtract the single declaration; the remainder is the invocation count.
    final all = RegExp(r'_initDestAreaCondition\(').allMatches(src).length;
    final decl = RegExp(
      r'Future<void>\s+_initDestAreaCondition\(',
    ).allMatches(src).length;
    expect(decl, 1, reason: 'exactly one method declaration expected');
    expect(
      all - decl,
      2,
      reason:
          'the dest read must have exactly TWO invocation sites — '
          'initState + the single driver-action setter; a scheduled caller '
          'would be 見守り-by-proxy',
    );

    // One invocation is inside initState.
    final initStart = src.indexOf('void initState()');
    expect(initStart, greaterThan(-1));
    final initEnd = src.indexOf('\n  }', initStart);
    expect(initEnd, greaterThan(initStart));
    expect(
      src.substring(initStart, initEnd).contains('_initDestAreaCondition('),
      isTrue,
      reason: 'the dest read must be invoked from initState',
    );

    // The other invocation is inside the driver-action setter _setDestination.
    final setStart = src.indexOf('Future<void> _setDestination(');
    expect(
      setStart,
      greaterThan(-1),
      reason: 'the single driver-action setter must exist',
    );

    // Neither the read method NOR the driver-action setter may self-schedule a
    // background refresh. Slice each body from its declaration to the NEXT
    // top-level method declaration (a STRUCTURAL boundary, not a hard-coded
    // sibling name), failing loudly if no following declaration is found.
    String bodySliceFrom(String declStr) {
      final start = src.indexOf(declStr);
      expect(start, greaterThan(-1));
      final nextDecl = RegExp(
        r'\n  (?:Future<void>|void|Widget)\s+\w+\(',
      ).firstMatch(src.substring(start + 1));
      expect(
        nextDecl,
        isNotNull,
        reason: 'a following method declaration must bound the body slice',
      );
      return src.substring(start, start + 1 + nextDecl!.start);
    }

    for (final declStr in const [
      'Future<void> _initDestAreaCondition()',
      'Future<void> _setDestination(',
    ]) {
      final body = bodySliceFrom(declStr);
      for (final bg in const [
        'Timer',
        '.periodic',
        'Stream',
        '.listen(',
        'Notification',
      ]) {
        expect(
          body.contains(bg),
          isFalse,
          reason:
              'the dest path must have no background scheduling ($bg) '
              'in $declStr',
        );
      }
    }
  });

  test(
    'the section render is guarded on a non-null read, built exactly once',
    () {
      final src = File('lib/widgets/pretrip_screen.dart').readAsStringSync();
      expect(
        src.contains('if (_destAreaRead != null)'),
        isTrue,
        reason:
            'FamilyAreaCard must only build when a real read delivered — '
            'with DEST defines unset, _destAreaRead is null and it is omitted',
      );
      // Exactly one FamilyAreaCard build site, so no second UNCONDITIONAL card can
      // bypass the null-guard.
      expect(
        'FamilyAreaCard('.allMatches(src).length,
        1,
        reason: 'exactly one FamilyAreaCard build site, under the null guard',
      );
    },
  );
}
