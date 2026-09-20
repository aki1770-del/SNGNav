// The critical warning must be spoken in the voice it was written for, and the
// configured voice must survive the announcement.
//
// Measured on this bloc before the fix: the per-condition locale was set with
// `unawaited(setLanguage(...))` OUTSIDE the handler, then the announcement was
// queued. Those are two independent futures and the utterance can win, so an
// English critical black-ice warning was spoken by the Japanese engine. Nothing
// restored the configured voice afterwards either, so one override left Japanese
// turn text speaking through an English voice for the life of the session.
//
// These assert ORDER, not call counts. A count passes on the broken code.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

class _OrderRecordingTts extends Mock implements TtsEngine {}

void main() {
  late _OrderRecordingTts tts;
  late List<String> order;

  setUp(() {
    tts = _OrderRecordingTts();
    order = <String>[];
    when(() => tts.setLanguage(any())).thenAnswer((i) async {
      order.add('setLanguage:${i.positionalArguments.first}');
    });
    when(() => tts.speak(any())).thenAnswer((i) async {
      order.add('speak:${i.positionalArguments.first}');
    });
    when(() => tts.setVolume(any())).thenAnswer((_) async {});
    when(() => tts.setSpeechRate(any())).thenAnswer((_) async {});
    when(() => tts.stop()).thenAnswer((_) async => order.add('stop'));
    when(() => tts.dispose()).thenAnswer((_) async {});
    when(() => tts.isAvailable()).thenAnswer((_) async => true);
  });

  Future<void> drain() =>
      Future<void>.delayed(const Duration(milliseconds: 40));

  test('an overridden locale is applied BEFORE the utterance, not beside it',
      () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: tts,
      navigationStateStream: const Stream<NavigationState>.empty(),
      config: const VoiceGuidanceConfig(languageTag: 'ja-JP', volume: 0.8),
    );
    await drain();
    order.clear();

    bloc.add(
      const HazardAnnounced(
        message: 'Critical warning. Icy road.',
        severity: AlertSeverity.critical,
        localeTag: 'en',
      ),
    );
    await drain();

    final speakAt = order.indexWhere((e) => e.startsWith('speak:'));
    final setEnAt = order.indexOf('setLanguage:en');

    expect(setEnAt, isNot(-1),
        reason: 'the override locale was never applied at all; observed: $order');
    expect(speakAt, isNot(-1), reason: 'nothing was spoken; observed: $order');
    expect(setEnAt, lessThan(speakAt),
        reason: 'the English warning was spoken BEFORE the engine was switched '
            'to English — it went out in the previous voice. observed: $order');

    await bloc.close();
  });

  test('the configured voice is restored after an overridden announcement',
      () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: tts,
      navigationStateStream: const Stream<NavigationState>.empty(),
      config: const VoiceGuidanceConfig(languageTag: 'ja-JP', volume: 0.8),
    );
    await drain();
    order.clear();

    bloc.add(
      const HazardAnnounced(
        message: 'Critical warning. Icy road.',
        severity: AlertSeverity.critical,
        localeTag: 'en',
      ),
    );
    await drain();

    final speakAt = order.indexWhere((e) => e.startsWith('speak:'));
    final restoreAt = order.lastIndexOf('setLanguage:ja-JP');

    expect(restoreAt, isNot(-1),
        reason: 'the configured voice was never restored; every later Japanese '
            'line would speak in English. observed: $order');
    expect(restoreAt, greaterThan(speakAt),
        reason: 'restore did not follow the utterance; observed: $order');

    await bloc.close();
  });
}
