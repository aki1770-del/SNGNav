// No explainer string tells her the road is fine to drive as usual, or tells
// her to stop, to go on, or to turn back.
//
// WHY THIS TEST EXISTS
// This package sees neither the road nor the traffic behind her, so whether
// to stop, go on or turn back is hers to decide. Its words give her honest
// information and may name what she can do; they never decide for her. Two
// kinds of string broke that until 2026-09-25:
// - The dry-road cell said 「乾燥路面、通常運転で問題ありません」 / "Road is
//   dry. Maintain normal driving." That is an all-clear from a classification
//   that may be inferred, on a surface where black ice can look dry.
//   A driver in unexpected snow who hears "no problem" has been told the one
//   thing this package cannot know.
// - Four wet-ice cells told her to stop: 「…停車できる安全な場所を探してください」,
//   「可能なら安全な場所で停車してください」, 「停車できる場所まで最低速で」 and
//   "If possible, stop in a safe place." Stopping stays available. The cells
//   name it as an option instead, in the words the app already speaks for the
//   same choice: 「安全にできるときは、安全な場所での停車も選べます」.
//
// WHAT IT CHECKS
// Every one of the 48 (condition, profile) strings: no reassurance, and no
// directive to stop, go on or turn back. Naming stopping as an option passes.
//
// BOUNDS
// - Lexical. It catches the known words for these two kinds; a new phrasing
//   can pass it, so a person still reads every change to a string.
// - "Drive slowly" and 「速度を落とし」 pass: they say how to drive if she
//   drives, not whether to.

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

/// Words that tell her the road is fine to drive as usual.
bool reassures(String s) =>
    const ['問題ありません', '問題ない', '大丈夫', '安心', '安全です', '通常運転',
      '通常どおり', '通常通り'].any(s.contains) ||
    RegExp(
      r"\b(no problem|normal driving|as usual|safe to drive|you can make it|"
      r"it(?:'s| is) safe|you are safe|all clear)\b",
      caseSensitive: false,
    ).hasMatch(s);

/// Words that tell her to stop, to go on, or to turn back.
bool directsStopOrGo(String s) =>
    RegExp(r'停車して|停車できる(?:安全な)?場所(?:を探|まで)|止まって'
            r'|引き返して|走行を続け|そのまま走行')
        .hasMatch(s) ||
    RegExp(
      r'\b(stop in|stop at|stop now|pull over|turn back|keep driving|'
      r'continue driving|carry on)\b',
      caseSensitive: false,
    ).hasMatch(s);

bool decidesForHer(String s) => reassures(s) || directsStopOrGo(s);

void main() {
  group('The explainer informs; it does not decide for her', () {
    test('the check catches every string it was written for', () {
      // A check never run against the defect it exists for has not been
      // tested.
      const before = <String>[
        '乾燥路面、通常運転で問題ありません',
        'Road is dry. Maintain normal driving.',
        'アイスバーンです。最も滑りやすい路面の一つです。'
            '可能であれば停車できる安全な場所を探してください。'
            '走行中は時速20km以下を目安に',
        'アイスバーン、極めて危険。可能なら安全な場所で停車してください。'
            '走行時は時速20km以下に',
        'アイスバーン、停車できる場所まで最低速で',
        'Wet ice — among the most slippery road surfaces. '
            'If possible, stop in a safe place. '
            'Otherwise drive below 20 km/h.',
      ];
      const mustPass = <String>[
        '乾燥路面',
        'Road is dry.',
        '安全にできるときは、安全な場所での停車も選べます。',
        'If you can do so safely, pausing at a safe place is an option.',
        'Slush. Avoid lane changes. Drive slowly.',
        '圧雪、減速、急操作回避',
        'Wet road surface. Stopping distance increases. Reduce speed.',
      ];
      for (final s in before) {
        expect(decidesForHer(s), isTrue, reason: s);
      }
      for (final s in mustPass) {
        expect(decidesForHer(s), isFalse, reason: s);
      }
    });

    test('no explainer string, in any cell, reassures her or tells her to '
        'stop, go on or turn back', () {
      final hits = <String>[];
      for (final profile in DriverProfile.values) {
        for (final condition in RoadSurfaceCondition.values) {
          final action = AlertExplainer.forConditionAndProfile(
            condition,
            profile,
          ).action;
          if (decidesForHer(action)) hits.add('($profile, $condition): $action');
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'a string decides for her. This package cannot see the road or '
            'the traffic; whether to stop or go on is hers, and "no problem" '
            'is not something it can know:\n${hits.join('\n')}',
      );
    });
  });
}
