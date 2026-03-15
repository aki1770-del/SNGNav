import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_guidance/voice_guidance.dart';

class _MockFlutterTts extends Mock implements FlutterTts {}

void main() {
  group('FlutterTtsEngine', () {
    late _MockFlutterTts flutterTts;
    late FlutterTtsEngine engine;

    setUp(() {
      flutterTts = _MockFlutterTts();
      engine = FlutterTtsEngine(flutterTts: flutterTts);
    });

    test('isAvailable returns true when language list is non-empty', () async {
      when(() => flutterTts.getLanguages).thenAnswer((_) async => ['ja-JP']);

      expect(await engine.isAvailable(), isTrue);
    });

    test('isAvailable returns false when language list is empty', () async {
      when(() => flutterTts.getLanguages).thenAnswer((_) async => <String>[]);

      expect(await engine.isAvailable(), isFalse);
    });

    test('isAvailable returns false when getLanguages throws', () async {
      when(() => flutterTts.getLanguages).thenThrow(Exception('tts unavailable'));

      expect(await engine.isAvailable(), isFalse);
    });

    test('setLanguage delegates to flutter_tts', () async {
      when(() => flutterTts.setLanguage(any())).thenAnswer((_) async => 1);

      await engine.setLanguage('ja-JP');

      verify(() => flutterTts.setLanguage('ja-JP')).called(1);
    });

    test('setVolume clamps values into range', () async {
      when(() => flutterTts.setVolume(any())).thenAnswer((_) async => 1);

      await engine.setVolume(1.2);
      await engine.setVolume(-0.3);

      verify(() => flutterTts.setVolume(1.0)).called(1);
      verify(() => flutterTts.setVolume(0.0)).called(1);
    });

    test('speak delegates non-empty input', () async {
      when(() => flutterTts.speak(any())).thenAnswer((_) async => 1);

      await engine.speak('Turn right.');

      verify(() => flutterTts.speak('Turn right.')).called(1);
    });

    test('speak ignores blank input', () async {
      when(() => flutterTts.speak(any())).thenAnswer((_) async => 1);

      await engine.speak('   ');

      verifyNever(() => flutterTts.speak(any()));
    });

    test('stop delegates to flutter_tts', () async {
      when(() => flutterTts.stop()).thenAnswer((_) async => 1);

      await engine.stop();

      verify(() => flutterTts.stop()).called(1);
    });

    test('dispose stops and prevents future calls', () async {
      when(() => flutterTts.stop()).thenAnswer((_) async => 1);
      when(() => flutterTts.speak(any())).thenAnswer((_) async => 1);

      await engine.dispose();
      await engine.speak('Ignored after dispose');

      verify(() => flutterTts.stop()).called(1);
      verifyNever(() => flutterTts.speak('Ignored after dispose'));
    });
  });
}
