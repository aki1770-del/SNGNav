/// Tests for VoiceGuidanceBloc 0.6.0 budget-aware pacing.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:voice_guidance/voice_guidance.dart';

class _MockTtsEngine extends Mock implements TtsEngine {}

GlanceEvent _ev(int millis) => GlanceEvent(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      duration: Duration(milliseconds: millis),
      modalClass: GlanceModalClass.visual,
    );

void main() {
  late _MockTtsEngine ttsEngine;
  late StreamController<NavigationState> navController;

  setUp(() {
    ttsEngine = _MockTtsEngine();
    navController = StreamController<NavigationState>.broadcast();
    when(() => ttsEngine.setLanguage(any())).thenAnswer((_) async {});
    when(() => ttsEngine.setVolume(any())).thenAnswer((_) async {});
    when(() => ttsEngine.setSpeechRate(any())).thenAnswer((_) async {});
    when(() => ttsEngine.speak(any())).thenAnswer((_) async {});
    when(() => ttsEngine.stop()).thenAnswer((_) async {});
    when(() => ttsEngine.dispose()).thenAnswer((_) async {});
    when(() => ttsEngine.isAvailable()).thenAnswer((_) async => true);
  });

  tearDown(() async {
    await navController.close();
  });

  test(
      'back-compat: null glanceBudgetTracker + null budgetAwarePace -> '
      'init applies plain config.speakingRate', () async {
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
      config: const VoiceGuidanceConfig(speakingRate: 0.85),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    verify(() => ttsEngine.setSpeechRate(0.85)).called(1);
    await bloc.close();
  });

  test(
      'with tracker + budgetAwarePace: init applies maxPace*baseline '
      '(full budget remaining)', () async {
    final tracker = GlanceBudgetTracker();
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
      config: const VoiceGuidanceConfig(
        speakingRate: 1.0,
        budgetAwarePace: BudgetAwarePaceProfile(),
      ),
      glanceBudgetTracker: tracker,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    // remaining=1.0 -> maxPace=1.0; effective=1.0*1.0=1.0.
    verify(() => ttsEngine.setSpeechRate(1.0)).called(1);
    await bloc.close();
    await tracker.dispose();
  });

  test(
      'on BudgetExhausted: bloc reapplies effective rate at minPace*baseline',
      () async {
    final tracker = GlanceBudgetTracker();
    final bloc = VoiceGuidanceBloc(
      ttsEngine: ttsEngine,
      navigationStateStream: navController.stream,
      config: const VoiceGuidanceConfig(
        speakingRate: 1.0,
        budgetAwarePace: BudgetAwarePaceProfile(),
      ),
      glanceBudgetTracker: tracker,
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    clearInteractions(ttsEngine);

    // Consume the entire budget; budgetEvents fires Warning + Exhausted.
    tracker.record(_ev(12000));
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Two budget events -> two setSpeechRate calls (warning + exhausted).
    // Both should apply the budget-aware-reduced rate; at exhaustion
    // the rate equals minPace * baseline = 0.7 * 1.0 = 0.7.
    final captured = verify(() => ttsEngine.setSpeechRate(captureAny()))
        .captured
        .cast<double>();
    expect(captured.length, greaterThanOrEqualTo(1));
    // Last applied rate should be 0.7 (minPace * baseline 1.0).
    expect(captured.last, closeTo(0.7, 1e-9));
    // Caution-add-only: every applied rate must be <= 1.0 (baseline).
    for (final r in captured) {
      expect(r <= 1.0, isTrue, reason: 'rate $r exceeds baseline 1.0');
    }

    await bloc.close();
    await tracker.dispose();
  });
}
