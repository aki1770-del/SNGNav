import 'package:compound_failure_advisor/compound_failure_advisor.dart';
import 'package:test/test.dart';

/// Latin tokens legitimately allowed inside a Japanese driver-facing string.
/// Ordered longest-first so `km` is consumed before `m`.
const _allowedLatinInJa = <String>['GPS', 'km', 'm'];

/// Anything left in the Latin alphabet after stripping the allowed tokens is
/// untranslated English welded into a Japanese safety sentence. Not theoretical:
/// the first draft of this very file shipped `データthat自体`. A human reader
/// skims past it; this does not.
String _latinResidue(String s) {
  var t = s;
  for (final tok in _allowedLatinInJa) {
    t = t.replaceAll(tok, '');
  }
  return t.replaceAll(RegExp('[^A-Za-z]'), '');
}

/// Every driver-facing string a locale can emit — used by the exhaustive guards
/// so a future enum value added without a translation fails here, not at HER.
List<String> _allStrings(DriveAdviceMessages m) => <String>[
      for (final a in DriveAction.values) ...[m.actionLabel(a), m.actionSentence(a)],
      for (final r in CautionReason.values) m.reasonSentence(r),
      for (final u in Unknown.values) m.unknownSentence(u),
      m.compoundingNote(),
      m.sightStoppingSpeedHint(30),
    ];

void main() {
  group('forLanguage resolves and never throws', () {
    test('ja and its variants resolve to the Japanese table', () {
      for (final code in ['ja', 'ja_JP', 'ja-JP', 'JA', 'Ja_jp']) {
        expect(DriveAdviceMessages.forLanguage(code), same(DriveAdviceMessages.ja),
            reason: '$code must resolve to ja');
      }
    });

    test('English is the default and the fallback for anything not carried', () {
      for (final code in ['en', 'en_US', 'fi', 'nb', 'xx', '']) {
        expect(DriveAdviceMessages.forLanguage(code), same(DriveAdviceMessages.en),
            reason: '$code must fall back to en, never to silence');
      }
    });
  });

  group('every advisory value has text in every carried locale', () {
    for (final entry in <(String, DriveAdviceMessages)>[
      ('en', DriveAdviceMessages.en),
      ('ja', DriveAdviceMessages.ja),
    ]) {
      final (tag, m) = entry;

      test('[$tag] every DriveAction, CautionReason and Unknown is covered', () {
        for (final a in DriveAction.values) {
          expect(m.actionLabel(a).trim(), isNotEmpty, reason: '$tag ${a.name}');
          expect(m.actionSentence(a).trim(), isNotEmpty, reason: '$tag ${a.name}');
        }
        for (final r in CautionReason.values) {
          expect(m.reasonSentence(r).trim(), isNotEmpty, reason: '$tag ${r.name}');
        }
        for (final u in Unknown.values) {
          expect(m.unknownSentence(u).trim(), isNotEmpty, reason: '$tag ${u.name}');
        }
        expect(m.compoundingNote().trim(), isNotEmpty);
        expect(m.sightStoppingSpeedHint(30).trim(), isNotEmpty);
      });
    }
  });

  group('the Japanese is actually Japanese', () {
    test('every ja string contains Japanese script', () {
      final japanese = RegExp(r'[぀-ヿ一-鿿]');
      for (final s in _allStrings(DriveAdviceMessages.ja)) {
        expect(s, matches(japanese), reason: 'not translated: "$s"');
      }
    });

    test('no untranslated English leaks into a ja string', () {
      for (final s in _allStrings(DriveAdviceMessages.ja)) {
        expect(_latinResidue(s), isEmpty,
            reason: 'English leaked into a Japanese safety string: "$s"');
      }
    });
  });

  group('WORDING DISCIPLINE: the package cannot tell her to turn back', () {
    // The enum has structurally no abort rung. The STRINGS must not smuggle one
    // back in — a translation is exactly where a missing rung gets re-added by
    // accident, because the translator is reaching for a natural phrase.
    test('no string in any locale tells her to turn back or abandon the drive',
        () {
      const forbiddenJa = ['引き返', '戻ってください', '運転を中止', '走行を中止', '危険です'];
      const forbiddenEn = [
        'turn back',
        'turn around',
        'do not drive',
        'abort',
        'go back',
      ];
      for (final s in _allStrings(DriveAdviceMessages.ja)) {
        for (final bad in forbiddenJa) {
          expect(s.contains(bad), isFalse,
              reason: 'turn-back / abort language in "$s" (forbidden: $bad)');
        }
      }
      for (final s in _allStrings(DriveAdviceMessages.en)) {
        for (final bad in forbiddenEn) {
          expect(s.toLowerCase().contains(bad), isFalse,
              reason: 'turn-back / abort language in "$s" (forbidden: $bad)');
        }
      }
    });

    test('considerStopping is an invitation she owns, never a command', () {
      // 「停車してください」 (an imperative) would convert the ceiling from an
      // option into an order — the package's stated ceiling is a *reversible*
      // invitation.
      final ja = DriveAdviceMessages.ja.actionSentence(DriveAction.considerStopping);
      expect(ja.contains('停車してください'), isFalse);
      expect(ja, contains('選択肢'));
      expect(ja, contains('判断はあなた'));

      final en =
          DriveAdviceMessages.en.actionSentence(DriveAction.considerStopping).toLowerCase();
      expect(en.contains('stop now'), isFalse);
      expect(en, contains('option'));
    });
  });

  group('WORDING DISCIPLINE: continueDriving is never an assertion of safety', () {
    // continueDriving is the ABSENCE of a raised concern. If the string reads as
    // "the road is fine", the package has asserted a safety it cannot see — the
    // precise defect class of this whole wave (absence presented as a confident
    // positive), reappearing at the language layer.
    test('ja explicitly disclaims the safety reading', () {
      final s = DriveAdviceMessages.ja.actionSentence(DriveAction.continueDriving);
      expect(s, contains('安全であることを示すものではありません'));
      expect(DriveAdviceMessages.ja.actionLabel(DriveAction.continueDriving),
          isNot(contains('安全')));
    });

    test('en explicitly disclaims the safety reading', () {
      final s =
          DriveAdviceMessages.en.actionSentence(DriveAction.continueDriving).toLowerCase();
      expect(s, contains('not a statement that the road is safe'));
      expect(DriveAdviceMessages.en.actionLabel(DriveAction.continueDriving).toLowerCase(),
          isNot(contains('safe')));
    });
  });

  group('WORDING DISCIPLINE: unknown is never rendered as clear', () {
    // The heart of the honesty contract: "we have no reading" must never be
    // said in words that a driver hears as "visibility is fine".
    test('unknownVisibility states an absence, not good visibility', () {
      final ja = DriveAdviceMessages.ja.unknownSentence(Unknown.noVisibilityReading);
      expect(ja, contains('ありません'));
      expect(ja.contains('良好'), isFalse);
      expect(ja.contains('視界は良い'), isFalse);
      // It says out loud what it does NOT mean.
      expect(ja, contains('視界が良いという意味ではなく'));

      final en = DriveAdviceMessages.en
          .unknownSentence(Unknown.noVisibilityReading)
          .toLowerCase();
      expect(en, contains('not that visibility is good'));
    });

    test('the unknownVisibility REASON also refuses to claim good visibility', () {
      final ja = DriveAdviceMessages.ja.reasonSentence(CautionReason.unknownVisibility);
      expect(ja, contains('ありません'));
      expect(ja.contains('良好'), isFalse);
    });

    test('noPositionAtAll says plainly that we do not know where she is', () {
      expect(DriveAdviceMessages.ja.unknownSentence(Unknown.noPositionAtAll),
          contains('分かりません'));
      expect(
          DriveAdviceMessages.en
              .unknownSentence(Unknown.noPositionAtAll)
              .toLowerCase(),
          contains('do not know where you are'));
    });
  });

  group('WORDING DISCIPLINE: 警報 and 注意報 are not interchangeable', () {
    // These are JMA terms of art. 警報 = warning (severe/extreme);
    // 注意報 = advisory (moderate). Swapping them either cries wolf or
    // under-warns a real severe advisory — both are safety defects in Japanese
    // that are invisible to an English-reading reviewer.
    test('severeAdvisory uses 警報 and moderateAdvisory uses 注意報', () {
      final severe = DriveAdviceMessages.ja.reasonSentence(CautionReason.severeAdvisory);
      final moderate =
          DriveAdviceMessages.ja.reasonSentence(CautionReason.moderateAdvisory);
      expect(severe, contains('警報'));
      expect(moderate, contains('注意報'));
      expect(moderate.contains('警報'), isFalse,
          reason: 'a moderate advisory must not be announced as a 警報 (warning)');
    });
  });

  group('the compounding note carries the reason this package exists', () {
    test('it names both dangers and says they stack', () {
      final ja = DriveAdviceMessages.ja.compoundingNote();
      expect(ja, contains('現在地'));
      expect(ja, contains('視界不良'));
      expect(ja, contains('重なる'));

      final en = DriveAdviceMessages.en.compoundingNote().toLowerCase();
      expect(en, contains('position'));
      expect(en, contains('visibility'));
      expect(en, contains('more dangerous than either one alone'));
    });
  });

  group('measured numbers pass through verbatim', () {
    test('the sight-stopping hint restates the speed and disclaims safety', () {
      final ja = DriveAdviceMessages.ja.sightStoppingSpeedHint(30);
      expect(ja, contains('30'));
      // It must not read as "30 km/h is safe".
      expect(ja, contains('保証するものではありません'));

      final en = DriveAdviceMessages.en.sightStoppingSpeedHint(30);
      expect(en, contains('30'));
      expect(en.toLowerCase(), contains('not a speed we are telling you is safe'));
    });
  });

  group('the table composes with a real advisory (end to end)', () {
    test('a compound-failure moment renders a complete Japanese caution', () {
      // The moment this package exists for: her position is lost AND she cannot
      // see. Render the whole advisory in Japanese and assert every part reached
      // her — the action, a WHY, and the compounding note.
      final advice = adviseInDrive(const DriveSituation(
        positionTrust: PositionTrust.lost,
        confidenceRadiusMeters: 800.0,
        secondsSinceTrustedFix: 240.0,
        hasPosition: true,
        visibilityMeters: 80.0, // whiteout band
        visibilityAgeSeconds: 10.0,
        advisorySeverity: AdvisoryLevel.severe,
        speedMetersPerSecond: 15.0,
      ));

      final m = DriveAdviceMessages.forLanguage('ja_JP');

      expect(advice.action, DriveAction.considerStopping);
      expect(advice.compounding, isTrue);

      final rendered = <String>[
        m.actionSentence(advice.action),
        for (final r in advice.reasons) m.reasonSentence(r),
        for (final u in advice.unknowns) m.unknownSentence(u),
        if (advice.compounding) m.compoundingNote(),
      ].join('\n');

      expect(rendered, contains('選択肢')); // the invitation, not a command
      expect(rendered, contains('視界不良')); // the WHY she can read
      expect(rendered, contains('重なる')); // the compounding, stated
      expect(rendered.contains('引き返'), isFalse); // never
      // And nothing in the whole rendered advisory leaked English.
      expect(_latinResidue(rendered), isEmpty);
    });
  });
}
