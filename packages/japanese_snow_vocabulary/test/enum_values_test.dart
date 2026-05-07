import 'package:japanese_snow_vocabulary/japanese_snow_vocabulary.dart';
import 'package:test/test.dart';

void main() {
  group('JapaneseSnowSurfaceClass', () {
    test('cardinality is 6', () {
      expect(JapaneseSnowSurfaceClass.values.length, 6);
    });

    test('declaration order (load-bearing for .index comparison)', () {
      expect(JapaneseSnowSurfaceClass.values, const [
        JapaneseSnowSurfaceClass.iceBahn,
        JapaneseSnowSurfaceClass.blackIceBahn,
        JapaneseSnowSurfaceClass.snowyRoad,
        JapaneseSnowSurfaceClass.compactedSnow,
        JapaneseSnowSurfaceClass.slush,
        JapaneseSnowSurfaceClass.surfaceFrozen,
      ]);
    });

    test('names match expected', () {
      expect(JapaneseSnowSurfaceClass.iceBahn.name, 'iceBahn');
      expect(JapaneseSnowSurfaceClass.blackIceBahn.name, 'blackIceBahn');
      expect(JapaneseSnowSurfaceClass.snowyRoad.name, 'snowyRoad');
      expect(JapaneseSnowSurfaceClass.compactedSnow.name, 'compactedSnow');
      expect(JapaneseSnowSurfaceClass.slush.name, 'slush');
      expect(JapaneseSnowSurfaceClass.surfaceFrozen.name, 'surfaceFrozen');
    });

    test('byName round-trip succeeds for all six cases', () {
      for (final c in JapaneseSnowSurfaceClass.values) {
        expect(JapaneseSnowSurfaceClass.values.byName(c.name), c);
      }
    });

    test('exhaustive switch over all six cases compiles + executes', () {
      // Compile-time exhaustiveness contract for downstream consumers:
      // adding a future case to the enum without updating switches
      // would surface here.
      String describe(JapaneseSnowSurfaceClass c) {
        switch (c) {
          case JapaneseSnowSurfaceClass.iceBahn:
            return 'iceBahn';
          case JapaneseSnowSurfaceClass.blackIceBahn:
            return 'blackIceBahn';
          case JapaneseSnowSurfaceClass.snowyRoad:
            return 'snowyRoad';
          case JapaneseSnowSurfaceClass.compactedSnow:
            return 'compactedSnow';
          case JapaneseSnowSurfaceClass.slush:
            return 'slush';
          case JapaneseSnowSurfaceClass.surfaceFrozen:
            return 'surfaceFrozen';
        }
      }

      for (final c in JapaneseSnowSurfaceClass.values) {
        expect(describe(c), c.name);
      }
    });
  });
}
