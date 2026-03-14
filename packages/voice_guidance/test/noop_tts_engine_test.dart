import 'package:flutter_test/flutter_test.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('NoOpTtsEngine', () {
    test('is available before dispose', () async {
      final engine = NoOpTtsEngine();

      expect(await engine.isAvailable(), isTrue);
    });

    test('stores spoken text history', () async {
      final engine = NoOpTtsEngine();

      await engine.speak('first');
      await engine.speak('second');

      expect(engine.spokenTexts, ['first', 'second']);
    });

    test('ignores empty speech', () async {
      final engine = NoOpTtsEngine();

      await engine.speak('   ');

      expect(engine.spokenTexts, isEmpty);
    });

    test('clamps volume', () async {
      final engine = NoOpTtsEngine();

      await engine.setVolume(1.5);
      expect(engine.volume, 1.0);

      await engine.setVolume(-0.1);
      expect(engine.volume, 0.0);
    });

    test('updates language tag', () async {
      final engine = NoOpTtsEngine();

      await engine.setLanguage('en-US');

      expect(engine.languageTag, 'en-US');
    });

    test('dispose clears history and marks unavailable', () async {
      final engine = NoOpTtsEngine();
      await engine.speak('hello');

      await engine.dispose();

      expect(engine.spokenTexts, isEmpty);
      expect(await engine.isAvailable(), isFalse);
    });

    test('ignores operations after dispose', () async {
      final engine = NoOpTtsEngine();
      await engine.dispose();

      await engine.setLanguage('en-US');
      await engine.setVolume(0.4);
      await engine.speak('text');

      expect(engine.languageTag, 'ja-JP');
      expect(engine.volume, 1.0);
      expect(engine.spokenTexts, isEmpty);
    });
  });
}
