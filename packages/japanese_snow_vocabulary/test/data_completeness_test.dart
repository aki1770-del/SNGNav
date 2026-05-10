import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:test/test.dart';

/// Verifies the 6-of-6-fully-populated shape established at 0.2.0 by
/// the data-fill of `compactedSnow` / `slush` / `surfaceFrozen` from
/// JAF Training + JAF FAQ148 authoritative-source citations.
///
/// At 0.1.0 this test enforced 3-of-6 populated + 3-of-6 deferred. At
/// 0.2.0 all six entries carry verbatim authoritative-source data; if
/// a future edit silently mutates the populated count without an
/// honest README + CHANGELOG amend, these tests will surface the drift.
void main() {
  group('data_completeness_test — 6-of-6 fully populated at 0.2.0', () {
    test('jafAuthoritativeData covers all six enum cases', () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        expect(
          jafAuthoritativeData.containsKey(c),
          isTrue,
          reason: 'expected jafAuthoritativeData to contain key $c',
        );
      }
      expect(jafAuthoritativeData.length, 6);
    });

    test('all six entries are fully populated at 0.2.0', () {
      final populated = jafAuthoritativeData.entries
          .where((e) => e.value.isFullyPopulated)
          .map((e) => e.key)
          .toList();
      expect(populated.length, 6);
      expect(
        populated,
        containsAll(const [
          JapaneseSnowSurfaceClass.iceBahn,
          JapaneseSnowSurfaceClass.blackIceBahn,
          JapaneseSnowSurfaceClass.snowyRoad,
          JapaneseSnowSurfaceClass.compactedSnow,
          JapaneseSnowSurfaceClass.slush,
          JapaneseSnowSurfaceClass.surfaceFrozen,
        ]),
      );
    });

    test('zero entries are null-deferred at 0.2.0', () {
      final deferred = jafAuthoritativeData.entries
          .where((e) => !e.value.isFullyPopulated)
          .map((e) => e.key)
          .toList();
      expect(deferred, isEmpty);
    });

    test('every entry has all five authoritative fields populated', () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        final entry = jafAuthoritativeData[c]!;
        expect(
          entry.authoritativeSource,
          isNotNull,
          reason: 'authoritativeSource null for $c',
        );
        expect(entry.sourceUrl, isNotNull, reason: 'sourceUrl null for $c');
        expect(
          entry.safeDrivingResponseJa,
          isNotNull,
          reason: 'safeDrivingResponseJa null for $c',
        );
        expect(
          entry.safeDrivingResponseEn,
          isNotNull,
          reason: 'safeDrivingResponseEn null for $c',
        );
        expect(
          entry.regionFrequency,
          isNotNull,
          reason: 'regionFrequency null for $c',
        );
      }
    });

    test(
      'every entry has non-empty taxonomic surface (term + romaji + en)',
      () {
        for (final c in JapaneseSnowSurfaceClass.values) {
          final entry = jafAuthoritativeData[c]!;
          expect(entry.termJa, isNotEmpty);
          expect(entry.termRomaji, isNotEmpty);
          expect(entry.labelEn, isNotEmpty);
        }
      },
    );

    test('JapaneseSnowVocabularyEntry equality is by-value across all '
        'eight fields', () {
      const a = JapaneseSnowVocabularyEntry(
        termJa: 'アイスバーン',
        termRomaji: 'aisubaan',
        labelEn: 'icy hardpack',
      );
      const b = JapaneseSnowVocabularyEntry(
        termJa: 'アイスバーン',
        termRomaji: 'aisubaan',
        labelEn: 'icy hardpack',
      );
      const c = JapaneseSnowVocabularyEntry(
        termJa: 'アイスバーン',
        termRomaji: 'aisubaan',
        labelEn: 'different label',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.hashCode, equals(b.hashCode));
    });
  });
}
