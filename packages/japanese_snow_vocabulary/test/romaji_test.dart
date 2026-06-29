import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:test/test.dart';

/// Regression-guard for the Hepburn-style romanization carried in
/// [JapaneseSnowVocabularyEntry.termRomaji].
///
/// Founding incident: at 0.2.2 the 凍結 (とうけつ) entry shipped with
/// `termRomaji: 'kettou'` — a wrong romanization (kettou ≠ とうけつ).
/// Correct plain-ASCII Hepburn for とうけつ is `touketsu`; the package
/// convention writes long vowels out in ASCII (e.g. アイスバーン →
/// `aisubaan`, not `aisubān`), so no macron form is used. These
/// romaji-vs-kanji assertions pin the correct pairing so a future
/// mistype is caught at test time rather than shipping to consumers.
void main() {
  group('romaji_test — termRomaji matches its termJa kanji/kana', () {
    /// Expected plain-ASCII Hepburn romanization per enum case, paired
    /// with its canonical JA term. Asserting both halves makes this a
    /// true romaji-vs-kanji pairing guard.
    const expected = <JapaneseSnowSurfaceClass, ({String termJa, String romaji})>{
      JapaneseSnowSurfaceClass.iceBahn: (
        termJa: 'アイスバーン',
        romaji: 'aisubaan',
      ),
      JapaneseSnowSurfaceClass.blackIceBahn: (
        termJa: 'ブラックアイスバーン',
        romaji: 'burakku-aisubaan',
      ),
      JapaneseSnowSurfaceClass.snowyRoad: (
        termJa: '雪道',
        romaji: 'yuki-michi',
      ),
      JapaneseSnowSurfaceClass.compactedSnow: (
        termJa: '圧雪',
        romaji: 'assetsu',
      ),
      JapaneseSnowSurfaceClass.slush: (
        termJa: 'シャーベット',
        romaji: 'shabetto',
      ),
      JapaneseSnowSurfaceClass.surfaceFrozen: (
        termJa: '凍結',
        romaji: 'touketsu',
      ),
    };

    test('凍結 (surfaceFrozen) romaji is touketsu, not kettou', () {
      final entry =
          jafAuthoritativeData[JapaneseSnowSurfaceClass.surfaceFrozen]!;
      // Pair the kanji with its romanization so the assertion is a
      // romaji-vs-kanji guard, not just a string-equality on the value.
      expect(entry.termJa, '凍結');
      expect(
        entry.termRomaji,
        'touketsu',
        reason:
            '凍結 reads とうけつ → Hepburn touketsu; "kettou" is the '
            '0.2.2 regression this guard exists to catch.',
      );
      expect(
        entry.termRomaji,
        isNot('kettou'),
        reason: 'kettou is the wrong romanization for 凍結.',
      );
    });

    test('every entry pairs the correct kanji with the correct romaji', () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        final entry = jafAuthoritativeData[c]!;
        final want = expected[c]!;
        expect(
          entry.termJa,
          want.termJa,
          reason: 'termJa drift for $c',
        );
        expect(
          entry.termRomaji,
          want.romaji,
          reason: 'termRomaji drift for $c (expected ${want.romaji})',
        );
      }
    });
  });
}
