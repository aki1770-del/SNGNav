// The strength of the Japanese safety words is pinned, not just their absence
// of a command.
//
// The ja sentence for DriveAction.considerStopping — the CEILING rung, the
// strongest thing this package may say, the rung that exists because of the
// recorded whiteout account — read 「休憩する」 (take a rest/break). In Japanese
// driving usage 休憩 is the FATIGUE word (休憩所、2時間ごとに休憩); it does not
// carry "get off this road, conditions are dangerous". It was materially weaker
// than the English, and it contradicted this package's own actionLabel for the
// same enum value, which correctly says 停車.
//
// A mis-calibrated Japanese safety word is worse than English: she reads it,
// believes she has understood, and under-reacts.
import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:test/test.dart';

void main() {
  group('the ja ceiling rung says 停車, never 休憩', () {
    test('considerStopping sentence contains 停車', () {
      final s = DriveAdviceMessages.ja.actionSentence(
        DriveAction.considerStopping,
      );

      expect(s, contains('停車'));
      expect(s, isNot(contains('休憩')));
    });

    test('the sentence agrees with the label (both 停車)', () {
      final label = DriveAdviceMessages.ja.actionLabel(
        DriveAction.considerStopping,
      );
      final sentence = DriveAdviceMessages.ja.actionSentence(
        DriveAction.considerStopping,
      );

      expect(label, contains('停車'));
      expect(sentence, contains('停車'));
    });

    test('it is still an invitation, never a command', () {
      final s = DriveAdviceMessages.ja.actionSentence(
        DriveAction.considerStopping,
      );

      // The package's binding: 「〜という選択肢もあります」, never
      // 「停車してください」 and never 「引き返してください」.
      expect(s, contains('選択肢'));
      expect(s, isNot(contains('停車してください')));
      expect(s, isNot(contains('引き返')));
    });
  });

  group('the ja advisory band does not under-name the top', () {
    test('the severe/extreme band admits 特別警報 may be in force', () {
      final s = DriveAdviceMessages.ja.reasonSentence(
        CautionReason.severeAdvisory,
      );

      // CautionReason.severeAdvisory covers BOTH severe and extreme. A driver
      // reading a bare 警報 while a 大雪特別警報 is in force will under-react.
      expect(s, contains('警報'));
      expect(s, contains('特別警報'));
      expect(s, isNot(contains('注意報')));
    });

    test('the moderate band still says 注意報, not 警報', () {
      final s = DriveAdviceMessages.ja.reasonSentence(
        CautionReason.moderateAdvisory,
      );

      expect(s, contains('注意報'));
    });
  });
}
