/// Delivery-observation invariants (SOTIF-VG-001..006).
///
/// These lock the difference between "we spoke" and "she was warned". Each
/// test names the invariant it holds and was proven RED against the code as
/// shipped at 936fb2b before the guard landed — see
/// `SOTIF_INSUFFICIENCIES.md` for the measured pre-fix behaviour of each row.
library;

import 'dart:io' show ProcessException;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:voice_guidance/voice_guidance.dart' hide LinuxTtsEngine;
// The barrel resolves `LinuxTtsEngine` to the non-IO stub under static
// analysis (`linux_tts_engine_unsupported.dart`), which has a different
// constructor. Import the IO implementation directly, as
// `linux_tts_engine_test.dart` already does.
import 'package:voice_guidance/src/linux_tts_engine.dart';

class _MockFlutterTts extends Mock implements FlutterTts {}

void main() {
  group('INV-1 freshness — lastDelivery describes THIS speak or nothing', () {
    late _MockFlutterTts tts;
    late FlutterTtsEngine engine;
    late void Function() fireCompletion;

    setUp(() {
      tts = _MockFlutterTts();
      engine = FlutterTtsEngine(flutterTts: tts);
      when(() => tts.awaitSpeakCompletion(any())).thenAnswer((_) async => 1);
      when(() => tts.setCompletionHandler(any())).thenAnswer((inv) {
        fireCompletion = inv.positionalArguments.first as void Function();
      });
      when(() => tts.setErrorHandler(any())).thenAnswer((_) {});
      when(() => tts.setCancelHandler(any())).thenAnswer((_) {});
      when(() => tts.speak(any())).thenAnswer((_) async => 1);
      when(() => tts.stop()).thenAnswer((_) async => 1);
    });

    test('an utterance the platform never received is NOT delivered', () async {
      await engine.speak('Bridge ahead may be frozen.');
      fireCompletion();
      expect(engine.lastDelivery, SpeechDelivery.delivered);

      when(() => tts.setLanguage(any())).thenThrow(MissingPluginException());
      await engine.setLanguage('ja-JP');
      expect(engine.pluginAvailable, isFalse);

      await engine.speak('Black ice. Slow down now.');

      verifyNever(() => tts.speak('Black ice. Slow down now.'));
      expect(engine.lastDelivery, isNot(SpeechDelivery.delivered));
      expect(engine.lastDelivery, SpeechDelivery.unknown);
    });

    test('a blank utterance does not inherit the prior success', () async {
      await engine.speak('Bridge ahead may be frozen.');
      fireCompletion();
      expect(engine.lastDelivery, SpeechDelivery.delivered);

      await engine.speak('   ');

      expect(engine.lastDelivery, SpeechDelivery.unknown);
    });

    test('INV-4 a disposed engine reports nothing delivered', () async {
      await engine.speak('Bridge ahead may be frozen.');
      fireCompletion();
      await engine.dispose();

      await engine.speak('Post-dispose warning.');

      expect(engine.lastDelivery, SpeechDelivery.unknown);
    });
  });

  group('INV-2/INV-3 attribution — a verdict resolves only its own utterance',
      () {
    late _MockFlutterTts tts;
    late FlutterTtsEngine engine;
    late void Function() fireCompletion;
    late void Function() fireCancel;
    late void Function(dynamic) fireError;

    setUp(() {
      tts = _MockFlutterTts();
      engine = FlutterTtsEngine(flutterTts: tts);
      when(() => tts.awaitSpeakCompletion(any())).thenAnswer((_) async => 1);
      when(() => tts.setCompletionHandler(any())).thenAnswer((inv) {
        fireCompletion = inv.positionalArguments.first as void Function();
      });
      when(() => tts.setCancelHandler(any())).thenAnswer((inv) {
        fireCancel = inv.positionalArguments.first as void Function();
      });
      when(() => tts.setErrorHandler(any())).thenAnswer((inv) {
        fireError = inv.positionalArguments.first as void Function(dynamic);
      });
      when(() => tts.speak(any())).thenAnswer((_) async => 1);
      when(() => tts.stop()).thenAnswer((_) async => 1);
    });

    test('a late verdict for utterance 1 does not credit utterance 2',
        () async {
      await engine.speak('First warning.');
      await engine.speak('Second warning.');

      // Utterance 1's completion finally arrives. The platform callback
      // carries no utterance id (flutter_tts-4.2.5 lib/flutter_tts.dart:614
      // calls `completionHandler!()` with no arguments), so identity is held
      // on our side or nowhere.
      fireCompletion();

      expect(engine.lastDelivery, SpeechDelivery.unknown);
    });

    test('the CURRENT utterance still resolves normally', () async {
      await engine.speak('Only warning.');
      fireCompletion();

      expect(engine.lastDelivery, SpeechDelivery.delivered);
    });

    test('a second verdict cannot re-resolve a closed utterance', () async {
      await engine.speak('Only warning.');
      fireError('platform error');
      expect(engine.lastDelivery, SpeechDelivery.failed);

      fireCompletion();

      expect(engine.lastDelivery, SpeechDelivery.failed,
          reason: 'INV-3: no upgrade to delivered after a terminal verdict');
    });

    test('INV-5 a cancelled utterance is failed, not unknown', () async {
      await engine.speak('Interrupted warning.');
      expect(engine.lastDelivery, SpeechDelivery.unknown);

      fireCancel();

      expect(engine.lastDelivery, SpeechDelivery.failed,
          reason: 'a KNOWN non-delivery must not read as unobservable');
    });
  });

  group('INV-6 availability is not a tautology (HER IVI target)', () {
    test('isAvailable() is false when the binary is not on PATH', () async {
      final engine = LinuxTtsEngine(
        executable: 'spd-say-does-not-exist-xyz',
      );

      expect(await engine.isAvailable(), isFalse);
    });

    test('isAvailable() is false for an absolute path that does not exist',
        () async {
      final engine = LinuxTtsEngine(executable: '/nonexistent/bin/spd-say');

      expect(await engine.isAvailable(), isFalse);
    });

    test('isAvailable() is true for a binary that really is on PATH', () async {
      final engine = LinuxTtsEngine(executable: 'sh');

      expect(await engine.isAvailable(), isTrue);
    });
  });

  group('RESIDUAL (open, documented) — the IVI engine is unobservable', () {
    test('LinuxTtsEngine cannot be asked whether she was warned', () async {
      final engine = LinuxTtsEngine(
        executable: 'spd-say-does-not-exist-xyz',
        startProcess: (String e, List<String> a) async =>
            throw ProcessException(e, a, 'ENOENT', 2),
      );

      await engine.speak('Black ice. Slow down now.');

      // AoU-VG-003: this is the residual, asserted so it cannot be forgotten.
      // When LinuxTtsEngine becomes DeliveryObservable this test goes RED and
      // the SEooC assumption must be revised in the same change.
      expect(engine, isNot(isA<DeliveryObservable>()));
    });
  });
}
