import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('NoOpHapticEngine', () {
    test('records cues in order', () async {
      final engine = NoOpHapticEngine();

      await engine.cue(HapticCuePattern.warning);
      await engine.cue(HapticCuePattern.none);
      await engine.cue(HapticCuePattern.critical);

      expect(engine.cues, <HapticCuePattern>[
        HapticCuePattern.warning,
        HapticCuePattern.none,
        HapticCuePattern.critical,
      ]);
    });

    test('tactileCues excludes none', () async {
      final engine = NoOpHapticEngine();

      await engine.cue(HapticCuePattern.none);
      await engine.cue(HapticCuePattern.warning);
      await engine.cue(HapticCuePattern.critical);

      expect(engine.tactileCues, <HapticCuePattern>[
        HapticCuePattern.warning,
        HapticCuePattern.critical,
      ]);
    });

    test('isAvailable is true until disposed', () async {
      final engine = NoOpHapticEngine();

      expect(await engine.isAvailable(), isTrue);

      await engine.dispose();

      expect(await engine.isAvailable(), isFalse);
    });

    test('cue is a no-op after dispose (and dispose clears recording)', () async {
      final engine = NoOpHapticEngine();

      await engine.cue(HapticCuePattern.warning);
      await engine.dispose();
      await engine.cue(HapticCuePattern.critical);

      expect(engine.cues, isEmpty);
    });

    test('stop does not throw', () async {
      final engine = NoOpHapticEngine();
      await engine.stop();
    });
  });
}
