import 'package:flutter_test/flutter_test.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('VoiceGuidanceState', () {
    test('idle constructor sets expected defaults', () {
      const state = VoiceGuidanceState.idle();

      expect(state.status, VoiceGuidanceStatus.idle);
      expect(state.lastSpokenText, isNull);
      expect(state.lastHazardMessage, isNull);
      expect(state.lastManeuverIndex, isNull);
      expect(state.isMuted, isFalse);
    });

    test('isMuted reflects muted status', () {
      const muted = VoiceGuidanceState(status: VoiceGuidanceStatus.muted);
      const active = VoiceGuidanceState(status: VoiceGuidanceStatus.idle);

      expect(muted.isMuted, isTrue);
      expect(active.isMuted, isFalse);
    });

    test('copyWith updates provided fields', () {
      const state = VoiceGuidanceState(
        status: VoiceGuidanceStatus.idle,
        lastSpokenText: 'a',
        lastHazardMessage: 'b',
        lastManeuverIndex: 1,
      );

      final updated = state.copyWith(
        status: VoiceGuidanceStatus.speaking,
        lastSpokenText: 'next',
        lastHazardMessage: 'hazard',
        lastManeuverIndex: 3,
      );

      expect(updated.status, VoiceGuidanceStatus.speaking);
      expect(updated.lastSpokenText, 'next');
      expect(updated.lastHazardMessage, 'hazard');
      expect(updated.lastManeuverIndex, 3);
    });

    test('copyWith keeps existing values when omitted', () {
      const state = VoiceGuidanceState(
        status: VoiceGuidanceStatus.idle,
        lastSpokenText: 'keep',
        lastHazardMessage: 'haz',
        lastManeuverIndex: 2,
      );

      final updated = state.copyWith(status: VoiceGuidanceStatus.speaking);

      expect(updated.status, VoiceGuidanceStatus.speaking);
      expect(updated.lastSpokenText, 'keep');
      expect(updated.lastHazardMessage, 'haz');
      expect(updated.lastManeuverIndex, 2);
    });

    test('equatable comparison works', () {
      const a = VoiceGuidanceState(
        status: VoiceGuidanceStatus.idle,
        lastSpokenText: 'x',
        lastHazardMessage: 'y',
        lastManeuverIndex: 4,
      );
      const b = VoiceGuidanceState(
        status: VoiceGuidanceStatus.idle,
        lastSpokenText: 'x',
        lastHazardMessage: 'y',
        lastManeuverIndex: 4,
      );
      const c = VoiceGuidanceState(
        status: VoiceGuidanceStatus.speaking,
        lastSpokenText: 'x',
        lastHazardMessage: 'y',
        lastManeuverIndex: 4,
      );

      expect(a, b);
      expect(a == c, isFalse);
    });
  });
}
