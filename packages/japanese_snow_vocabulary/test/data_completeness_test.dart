import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:test/test.dart';

/// Verifies the 3-of-6-fully-populated + 3-of-6-null-deferred shape
/// honest-disclosed in the 0.1.0 README / CHANGELOG /
/// `KNOWN_LIMITATIONS.md`. If a future edit silently mutates the
/// fully-populated count without an honest README + CHANGELOG amend,
/// these tests will surface the drift.
void main() {
  group('data_completeness_test — 3-of-6 populated + 3-of-6 deferred', () {
    test('jafAuthoritativeData covers all six enum cases', () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        expect(jafAuthoritativeData.containsKey(c), isTrue,
            reason: 'expected jafAuthoritativeData to contain key $c');
      }
      expect(jafAuthoritativeData.length, 6);
    });

    test('exactly three entries are fully populated at 0.1.0', () {
      final populated = jafAuthoritativeData.entries
          .where((e) => e.value.isFullyPopulated)
          .map((e) => e.key)
          .toList();
      expect(populated.length, 3);
      expect(populated, containsAll(const [
        JapaneseSnowSurfaceClass.iceBahn,
        JapaneseSnowSurfaceClass.blackIceBahn,
        JapaneseSnowSurfaceClass.snowyRoad,
      ]));
    });

    test('exactly three entries are null-deferred at 0.1.0', () {
      final deferred = jafAuthoritativeData.entries
          .where((e) => !e.value.isFullyPopulated)
          .map((e) => e.key)
          .toList();
      expect(deferred.length, 3);
      expect(deferred, containsAll(const [
        JapaneseSnowSurfaceClass.compactedSnow,
        JapaneseSnowSurfaceClass.slush,
        JapaneseSnowSurfaceClass.surfaceFrozen,
      ]));
    });

    test('every fully-populated entry has all five authoritative fields',
        () {
      for (final c in const [
        JapaneseSnowSurfaceClass.iceBahn,
        JapaneseSnowSurfaceClass.blackIceBahn,
        JapaneseSnowSurfaceClass.snowyRoad,
      ]) {
        final entry = jafAuthoritativeData[c]!;
        expect(entry.authoritativeSource, isNotNull);
        expect(entry.sourceUrl, isNotNull);
        expect(entry.safeDrivingResponseJa, isNotNull);
        expect(entry.safeDrivingResponseEn, isNotNull);
        expect(entry.regionFrequency, isNotNull);
      }
    });

    test('every null-deferred entry has all five authoritative fields null',
        () {
      for (final c in const [
        JapaneseSnowSurfaceClass.compactedSnow,
        JapaneseSnowSurfaceClass.slush,
        JapaneseSnowSurfaceClass.surfaceFrozen,
      ]) {
        final entry = jafAuthoritativeData[c]!;
        expect(entry.authoritativeSource, isNull);
        expect(entry.sourceUrl, isNull);
        expect(entry.safeDrivingResponseJa, isNull);
        expect(entry.safeDrivingResponseEn, isNull);
        expect(entry.regionFrequency, isNull);
      }
    });

    test('every entry has non-empty taxonomic surface (term + romaji + en)',
        () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        final entry = jafAuthoritativeData[c]!;
        expect(entry.termJa, isNotEmpty);
        expect(entry.termRomaji, isNotEmpty);
        expect(entry.labelEn, isNotEmpty);
      }
    });

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
