import 'package:flutter_test/flutter_test.dart';
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('VoiceGuidanceConfig', () {
    test('has expected defaults', () {
      const config = VoiceGuidanceConfig();

      expect(config.enabled, isTrue);
      expect(config.languageTag, 'ja-JP');
      expect(config.volume, 1.0);
      expect(config.maneuverLeadDistanceMeters, 120.0);
      expect(config.minAnnouncementIntervalSeconds, 3);
    });

    test('supports copyWith updates', () {
      const config = VoiceGuidanceConfig();

      final updated = config.copyWith(
        enabled: false,
        languageTag: 'en-US',
        volume: 0.5,
        maneuverLeadDistanceMeters: 80,
        minAnnouncementIntervalSeconds: 1,
      );

      expect(updated.enabled, isFalse);
      expect(updated.languageTag, 'en-US');
      expect(updated.volume, 0.5);
      expect(updated.maneuverLeadDistanceMeters, 80);
      expect(updated.minAnnouncementIntervalSeconds, 1);
    });

    test('is equatable', () {
      const a = VoiceGuidanceConfig(languageTag: 'ja-JP');
      const b = VoiceGuidanceConfig(languageTag: 'ja-JP');
      const c = VoiceGuidanceConfig(languageTag: 'en-US');

      expect(a, b);
      expect(a == c, isFalse);
    });

    test('asserts on invalid volume', () {
      expect(
        () => VoiceGuidanceConfig(volume: -0.1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => VoiceGuidanceConfig(volume: 1.1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('asserts on invalid distances or intervals', () {
      expect(
        () => VoiceGuidanceConfig(maneuverLeadDistanceMeters: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => VoiceGuidanceConfig(minAnnouncementIntervalSeconds: -1),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
