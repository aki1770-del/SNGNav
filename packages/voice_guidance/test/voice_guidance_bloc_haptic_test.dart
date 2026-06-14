import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:navigation_safety_enums/navigation_safety_enums.dart' as nse;
import 'package:voice_guidance/voice_guidance.dart';

class _MockTtsEngine extends Mock implements TtsEngine {}

Future<void> _drain() async {
  await Future<void>.delayed(const Duration(milliseconds: 30));
}

void _stubTts(_MockTtsEngine tts) {
  when(() => tts.setLanguage(any())).thenAnswer((_) async {});
  when(() => tts.setVolume(any())).thenAnswer((_) async {});
  when(() => tts.setSpeechRate(any())).thenAnswer((_) async {});
  when(() => tts.speak(any())).thenAnswer((_) async {});
  when(() => tts.stop()).thenAnswer((_) async {});
  when(() => tts.dispose()).thenAnswer((_) async {});
  when(() => tts.isAvailable()).thenAnswer((_) async => true);
}

void main() {
  late _MockTtsEngine ttsEngine;
  late NoOpHapticEngine hapticEngine;
  late StreamController<NavigationState> navController;

  setUp(() {
    ttsEngine = _MockTtsEngine();
    hapticEngine = NoOpHapticEngine();
    navController = StreamController<NavigationState>.broadcast();
    _stubTts(ttsEngine);
  });

  tearDown(() async {
    await navController.close();
  });

  test(
    'warning hazard fires the warning cue ADDITIVELY beside the audio',
    () async {
      final bloc = VoiceGuidanceBloc(
        ttsEngine: ttsEngine,
        navigationStateStream: navController.stream,
        hapticEngine: hapticEngine,
      );

      navController.add(
        const NavigationState(
          status: NavigationStatus.navigating,
          alertMessage: '圧雪路です。速度を落としてください。',
          alertSeverity: AlertSeverity.warning,
        ),
      );
      await _drain();

      // Severity-coupling lock: warning severity -> warning cue.
      expect(hapticEngine.cues, <nse.HapticCuePattern>[
        nse.HapticCuePattern.warning,
      ]);
      // Audio still fired — the haptic is additive, never gating.
      verify(() => ttsEngine.speak(any())).called(1);

      await bloc.close();
    },
  );

  test('critical hazard fires the critical cue', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
      hapticEngine: hapticEngine,
    );

    navController.add(
      const NavigationState(
        status: NavigationStatus.navigating,
        alertMessage: 'ホワイトアウト。引き返すことを検討してください。',
        alertSeverity: AlertSeverity.critical,
      ),
    );
    await _drain();

    expect(hapticEngine.cues, <nse.HapticCuePattern>[
      nse.HapticCuePattern.critical,
    ]);
    verify(() => ttsEngine.speak(any())).called(1);

    await bloc.close();
  });

  test(
    'deaf-cue SET == hearing-warning SET (off the same severity gate)',
    () async {
      // Drive a fresh bloc through every AlertSeverity; collect which
      // severities produce an audio announcement (the hearing warning set)
      // and which produce a tactile cue (the deaf cue set). They must be
      // EQUAL — no reduced subset for the driver who cannot hear.
      final spokenSeverities = <AlertSeverity>{};
      final tactileSeverities = <AlertSeverity>{};

      for (final severity in AlertSeverity.values) {
        final tts = _MockTtsEngine();
        _stubTts(tts);
        var spoke = false;
        when(() => tts.speak(any())).thenAnswer((_) async {
          spoke = true;
        });

        final haptic = NoOpHapticEngine();
        final ctrl = StreamController<NavigationState>.broadcast();
        final bloc = VoiceGuidanceBloc(
          ttsEngine: tts,
          navigationStateStream: ctrl.stream,
          hapticEngine: haptic,
        );

        ctrl.add(
          NavigationState(
            status: NavigationStatus.navigating,
            alertMessage: 'msg-${severity.name}',
            alertSeverity: severity,
          ),
        );
        await _drain();

        if (spoke) spokenSeverities.add(severity);
        if (haptic.tactileCues.isNotEmpty) tactileSeverities.add(severity);

        await bloc.close();
        await ctrl.close();
      }

      expect(
        tactileSeverities,
        equals(spokenSeverities),
        reason: 'deaf tactile-cue set must equal hearing warning set',
      );
      expect(
        spokenSeverities,
        equals(<AlertSeverity>{
          AlertSeverity.warning,
          AlertSeverity.critical,
        }),
      );
    },
  );

  test(
    'back-compat: no haptic engine -> audio path unchanged, no crash',
    () async {
      final bloc = VoiceGuidanceBloc(
        ttsEngine: ttsEngine,
        navigationStateStream: navController.stream,
        // No haptic engine supplied — pre-0.7.0 back-compat path.
      );

      navController.add(
        const NavigationState(
          status: NavigationStatus.navigating,
          alertMessage: '圧雪路です。速度を落としてください。',
          alertSeverity: AlertSeverity.warning,
        ),
      );
      await _drain();

      verify(() => ttsEngine.speak(any())).called(1);

      await bloc.close();
    },
  );
}
