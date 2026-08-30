// The third state: reachable, and proven to break nobody.
//
// Guards the 2026-08-30 widening. `isAvailable()` cannot say "could not tell",
// so a failed probe answers `false` and an integrator reads "this device has
// no speech". AvailabilityReporting adds the third answer as an OPT-IN
// capability — measured to be the only shape that does not break `implements`.
import 'package:test/test.dart';
import 'package:voice_guidance/voice_guidance.dart';

/// A pre-2026-08-30 implementer. It has never heard of AvailabilityReporting.
class LegacyTts implements TtsEngine {
  LegacyTts(this._available);
  final bool _available;
  @override
  Future<bool> isAvailable() async => _available;
  @override
  Future<void> setLanguage(String languageTag) async {}
  @override
  Future<void> setVolume(double volume) async {}
  @override
  Future<void> setSpeechRate(double rate) async {}
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// An engine whose probe genuinely failed: not "no", but "could not tell".
class UnknownTts extends LegacyTts implements AvailabilityReporting {
  UnknownTts() : super(false);
  @override
  Future<bool?> readAvailability() async => null;
}

void main() {
  group('AvailabilityReporting — the third state', () {
    test('⚑ NON-BREAKING: a legacy implementer still compiles and runs', () {
      // The proof is that this file compiles at all: LegacyTts implements
      // TtsEngine and does NOT implement readAvailability. A default method on
      // TtsEngine would have made this a compile error — measured 2026-08-30,
      // it broke LinuxTtsEngine immediately.
      expect(LegacyTts(true), isA<TtsEngine>());
      expect(LegacyTts(true), isNot(isA<AvailabilityReporting>()));
    });

    test('a caller can detect the capability and fall back honestly', () async {
      // Written the way an integrator actually would: probe, then delegate.
      Future<bool?> read(TtsEngine e) async {
        if (e is AvailabilityReporting) {
          return (e as AvailabilityReporting).readAvailability();
        }
        return null; // honest unknown — never a fabricated `false`
      }
      // legacy engine → caller gets null (unknown), never a fabricated answer
      expect(await read(LegacyTts(true)), isNull);
      // capable engine → gets the real third state
      expect(await read(UnknownTts()), isNull);
    });

    test('⚑ null is NOT collapsible to false — the two answers differ',
        () async {
      final e = UnknownTts();
      expect(await e.readAvailability(), isNull,
          reason: 'could-not-tell must survive as null');
      expect(await e.isAvailable(), isFalse,
          reason: 'the two-state API can only say false — the defect this '
              'capability routes around');
      expect(await e.readAvailability(), isNot(equals(await e.isAvailable())));
    });
  });
}
