import 'package:localization_fallback/localization_fallback.dart';
import 'package:test/test.dart';

/// Latin tokens that are legitimately Japanese-driver-facing and MUST be
/// allowed to appear inside a `ja` string: the receiver name and the unit
/// abbreviations a Japanese car-navigation screen actually shows.
/// Ordered longest-first so `km` is consumed before `m`.
const _allowedLatinInJa = <String>['GPS', 'km', 'm', 's'];

/// Strip the allowed tokens and the interpolated digits, then anything left in
/// the Latin alphabet is untranslated English that leaked into a Japanese
/// string. (This guard is not theoretical: the first draft of the sibling
/// package's table shipped `データthat自体` — a stray English word welded into a
/// Japanese safety sentence. A human reader skims straight past it; this
/// catches it.)
String _latinResidue(String s) {
  var t = s;
  for (final tok in _allowedLatinInJa) {
    t = t.replaceAll(tok, '');
  }
  return t.replaceAll(RegExp('[^A-Za-z]'), '');
}

/// Typographic residue: a spaced ASCII-style dash is the visible fingerprint of
/// an English sentence with Japanese words dropped into it. Japanese chip copy
/// uses 「（…）」 or a 全角 separator. It is not a Latin LETTER, so
/// [_latinResidue] never saw it — and these chips render next to the dot on her
/// screen at the exact moment the app is telling her it does not know where she
/// is, which is the one place the copy must not look machine-produced.
bool _hasDashResidue(String s) =>
    s.contains(' — ') || s.contains(' - ') || s.contains(' -- ');

void main() {
  group('forLanguage resolves and never throws', () {
    test('ja and its variants resolve to the Japanese table', () {
      for (final code in ['ja', 'ja_JP', 'ja-JP', 'JA', 'Ja_jp']) {
        expect(
          LocalizationMessages.forLanguage(code),
          same(LocalizationMessages.ja),
          reason: '$code must resolve to ja',
        );
      }
    });

    test('English is the default and the fallback for anything not carried',
        () {
      for (final code in ['en', 'en_US', 'fi', 'nb', 'xx', '', 'zz-ZZ']) {
        expect(
          LocalizationMessages.forLanguage(code),
          same(LocalizationMessages.en),
          reason: '$code must fall back to en, never to silence',
        );
      }
    });
  });

  group('every honesty state has text in every carried locale', () {
    // The loom: a future LocalizationMode / EstimateBasis added without a
    // translation fails HERE, at build time, instead of reaching a driver as a
    // blank label — a blank honesty label reads exactly like confidence.
    for (final messages in <(String, LocalizationMessages)>[
      ('en', LocalizationMessages.en),
      ('ja', LocalizationMessages.ja),
    ]) {
      final (tag, m) = messages;

      test('[$tag] every LocalizationMode has a label and an explanation', () {
        for (final mode in LocalizationMode.values) {
          expect(m.modeLabel(mode).trim(), isNotEmpty, reason: '$tag ${mode.name}');
          expect(m.modeExplanation(mode).trim(), isNotEmpty,
              reason: '$tag ${mode.name}');
        }
      });

      test('[$tag] every EstimateBasis has a label', () {
        for (final basis in EstimateBasis.values) {
          expect(m.basisLabel(basis).trim(), isNotEmpty,
              reason: '$tag ${basis.name}');
        }
      });

      test('[$tag] the absence strings are non-empty', () {
        expect(m.noPositionAtAll().trim(), isNotEmpty);
        expect(m.positionWithinRadius(150).trim(), isNotEmpty);
        expect(m.noTrustedFixFor(60).trim(), isNotEmpty);
      });
    }
  });

  group('the Japanese is actually Japanese', () {
    test('every ja string contains Japanese script', () {
      final ja = LocalizationMessages.ja;
      final japanese = RegExp(r'[぀-ヿ一-鿿]');
      final strings = <String>[
        for (final mode in LocalizationMode.values) ...[
          ja.modeLabel(mode),
          ja.modeExplanation(mode),
        ],
        for (final basis in EstimateBasis.values) ja.basisLabel(basis),
        ja.positionWithinRadius(150),
        ja.noTrustedFixFor(60),
        ja.noPositionAtAll(),
      ];
      for (final s in strings) {
        expect(s, matches(japanese), reason: 'not translated: "$s"');
      }
    });

    test('no untranslated English leaks into a ja string', () {
      final ja = LocalizationMessages.ja;
      final strings = <String>[
        for (final mode in LocalizationMode.values) ...[
          ja.modeLabel(mode),
          ja.modeExplanation(mode),
        ],
        for (final basis in EstimateBasis.values) ja.basisLabel(basis),
        ja.positionWithinRadius(150),
        ja.noTrustedFixFor(60),
        ja.noPositionAtAll(),
      ];
      for (final s in strings) {
        expect(
          _latinResidue(s),
          isEmpty,
          reason: 'English leaked into a Japanese safety string: "$s"',
        );
        expect(
          _hasDashResidue(s),
          isFalse,
          reason: 'English typography leaked into a Japanese string: "$s"',
        );
      }
    });
  });

  group('claim ceiling: position knowledge only, never a safety claim', () {
    test('no string claims the road or the driver is safe', () {
      // This package measures position. It measures NO road and NO weather.
      // A string here that says "safe" would be asserting something the
      // package cannot see — the exact defect class this wave exists to repair.
      final forbiddenJa = ['安全です', '安全に走行できます', '路面は'];
      final forbiddenEn = ['you are safe', 'it is safe', 'safe to drive'];

      final jaStrings = <String>[
        for (final mode in LocalizationMode.values) ...[
          LocalizationMessages.ja.modeLabel(mode),
          LocalizationMessages.ja.modeExplanation(mode),
        ],
        LocalizationMessages.ja.noPositionAtAll(),
      ];
      for (final s in jaStrings) {
        for (final bad in forbiddenJa) {
          expect(s.contains(bad), isFalse, reason: '"$s" must not claim "$bad"');
        }
      }

      final enStrings = <String>[
        for (final mode in LocalizationMode.values) ...[
          LocalizationMessages.en.modeLabel(mode),
          LocalizationMessages.en.modeExplanation(mode),
        ],
        LocalizationMessages.en.noPositionAtAll(),
      ];
      for (final s in enStrings) {
        for (final bad in forbiddenEn) {
          expect(s.toLowerCase().contains(bad), isFalse,
              reason: '"$s" must not claim "$bad"');
        }
      }
    });

    test('lost says plainly that we do not know where she is', () {
      // The strongest thing this package may say — and it must actually say it,
      // not hedge it into reassurance.
      expect(
        LocalizationMessages.ja.modeExplanation(LocalizationMode.lost),
        contains('分かりません'),
      );
      expect(LocalizationMessages.ja.modeLabel(LocalizationMode.lost),
          equals('現在地不明'));
      expect(
        LocalizationMessages.en.modeExplanation(LocalizationMode.lost).toLowerCase(),
        contains('do not know where you are'),
      );
    });

    test('gpsSuspect never implies the suspect fix is being used', () {
      // The controller does NOT blend a suspect fix. The text must not suggest
      // the dot came from GPS when it did not.
      expect(
        LocalizationMessages.ja.modeExplanation(LocalizationMode.gpsSuspect),
        contains('推定'),
      );
      expect(
        LocalizationMessages.en
            .modeExplanation(LocalizationMode.gpsSuspect)
            .toLowerCase(),
        contains('estimated'),
      );
    });
  });

  group('measured numbers pass through verbatim', () {
    test('the radius is restated, never rounded away or re-scaled', () {
      expect(LocalizationMessages.ja.positionWithinRadius(150), contains('150'));
      expect(LocalizationMessages.en.positionWithinRadius(150), contains('150'));
      expect(LocalizationMessages.ja.noTrustedFixFor(90), contains('90'));
      expect(LocalizationMessages.en.noTrustedFixFor(90), contains('90'));
    });
  });

  group('describeEstimate composes without claiming more than it knows', () {
    LocalizationEstimate estimate({
      required LocalizationMode mode,
      required EstimateBasis basis,
      double lat = 39.7,
      double lon = 140.1,
      double radius = 250.0,
    }) =>
        LocalizationEstimate(
          latitude: lat,
          longitude: lon,
          confidenceRadiusMeters: radius,
          mode: mode,
          secondsSinceTrustedFix: 30.0,
          basis: basis,
        );

    test('a trusted fix states the mode and offers no radius caveat', () {
      final s = LocalizationMessages.ja.describeEstimate(estimate(
        mode: LocalizationMode.gpsTrusted,
        basis: EstimateBasis.trustedGpsFix,
      ));
      expect(s, contains('GPS'));
      expect(s.contains('半径'), isFalse);
    });

    test('a degraded fix carries the radius the dot could be anywhere within',
        () {
      final s = LocalizationMessages.ja.describeEstimate(estimate(
        mode: LocalizationMode.deadReckoning,
        basis: EstimateBasis.deadReckoning,
        radius: 250.0,
      ));
      expect(s, contains('250'));
    });

    test('no plottable position degrades to 現在地不明, never to a radius', () {
      final s = LocalizationMessages.ja.describeEstimate(estimate(
        mode: LocalizationMode.lost,
        basis: EstimateBasis.unanchoredGuess,
        lat: double.nan,
        lon: double.nan,
      ));
      expect(s, equals(LocalizationMessages.ja.noPositionAtAll()));
    });

    test('composed Japanese carries no stray ASCII space between sentences', () {
      // Japanese does not space-separate sentences that already close with 。
      // A stray ASCII space is the visible fingerprint of text assembled by
      // someone who never looked at the rendered result.
      final s = LocalizationMessages.ja.describeEstimate(estimate(
        mode: LocalizationMode.deadReckoning,
        basis: EstimateBasis.deadReckoning,
      ));
      expect(s.contains('。 '), isFalse, reason: 'stray ASCII space in: "$s"');
      expect(LocalizationMessages.ja.sentenceSeparator, isEmpty);
      // English still separates its sentences.
      expect(LocalizationMessages.en.sentenceSeparator, equals(' '));
    });

    test('an infinite radius is not rendered as a number', () {
      // The bootstrap state emits an INFINITE radius. "within about Infinity m"
      // would be worse than saying nothing about the radius at all.
      final s = LocalizationMessages.en.describeEstimate(estimate(
        mode: LocalizationMode.lost,
        basis: EstimateBasis.lastKnownPosition,
        radius: double.infinity,
      ));
      expect(s.toLowerCase().contains('infinity'), isFalse);
      expect(s, contains('do not know where you are'));
    });
  });
}
