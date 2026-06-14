import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('FlutterHapticEngine — pulse grammar', () {
    test('warning renders 2 impacts, critical 3, none 0', () async {
      final calls = <HapticCuePattern>[];
      final engine = FlutterHapticEngine(
        impact: (p) async => calls.add(p),
        interPulseGap: Duration.zero,
      );

      await engine.cue(HapticCuePattern.none);
      expect(calls, isEmpty, reason: 'none performs no platform call');

      await engine.cue(HapticCuePattern.warning);
      expect(
        calls.where((p) => p == HapticCuePattern.warning).length,
        2,
        reason: 'warning is a measured double-pulse',
      );

      calls.clear();
      await engine.cue(HapticCuePattern.critical);
      expect(
        calls.where((p) => p == HapticCuePattern.critical).length,
        3,
        reason: 'critical is an urgent triple-pulse (distinct from warning)',
      );
    });
  });

  group('FlutterHapticEngine — honest degradation', () {
    test('isAvailable is true by default', () async {
      final engine = FlutterHapticEngine(impact: (_) async {});
      expect(await engine.isAvailable(), isTrue);
      expect(engine.pluginAvailable, isTrue);
    });

    test(
      'MissingPluginException flips unavailable and is NOT thrown',
      () async {
        final engine = FlutterHapticEngine(
          impact: (_) async => throw MissingPluginException(),
          interPulseGap: Duration.zero,
        );

        // cue must not throw — honest degradation, never gates audio.
        await engine.cue(HapticCuePattern.critical);

        expect(engine.pluginAvailable, isFalse);
        expect(await engine.isAvailable(), isFalse);
      },
    );

    test('after unavailable, further cues are no-ops', () async {
      var impacts = 0;
      var first = true;
      final engine = FlutterHapticEngine(
        impact: (_) async {
          if (first) {
            first = false;
            throw MissingPluginException();
          }
          impacts++;
        },
        interPulseGap: Duration.zero,
      );

      await engine.cue(HapticCuePattern.warning); // first throws -> unavailable
      await engine.cue(HapticCuePattern.warning); // now a no-op

      expect(impacts, 0);
    });

    test(
      'a non-plugin error is swallowed (cue never throws; stays available)',
      () async {
        final engine = FlutterHapticEngine(
          impact: (_) async => throw StateError('transient haptic error'),
          interPulseGap: Duration.zero,
        );

        // Must not throw into the caller (the audio path).
        await engine.cue(HapticCuePattern.warning);

        // A transient error does not falsely flag the platform missing.
        expect(engine.pluginAvailable, isTrue);
      },
    );

    test('dispose prevents further cues and reports unavailable', () async {
      final calls = <HapticCuePattern>[];
      final engine = FlutterHapticEngine(
        impact: (p) async => calls.add(p),
        interPulseGap: Duration.zero,
      );

      await engine.dispose();
      await engine.cue(HapticCuePattern.critical);

      expect(calls, isEmpty);
      expect(await engine.isAvailable(), isFalse);
    });
  });
}
