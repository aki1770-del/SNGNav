import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart' show DriverProfile;
import 'package:voice_guidance/voice_guidance.dart';

void main() {
  group('VoiceGuidanceConfig', () {
    test('has expected defaults', () {
      const config = VoiceGuidanceConfig();

      expect(config.enabled, isTrue);
      expect(config.languageTag, 'ja-JP');
      expect(config.volume, 1.0);
      expect(config.speakingRate, 1.0);
      expect(config.maneuverLeadDistanceMeters, 120.0);
      expect(config.minAnnouncementIntervalSeconds, 3);
    });

    test('supports copyWith updates', () {
      const config = VoiceGuidanceConfig();

      final updated = config.copyWith(
        enabled: false,
        languageTag: 'en-US',
        volume: 0.5,
        speakingRate: 0.8,
        maneuverLeadDistanceMeters: 80,
        minAnnouncementIntervalSeconds: 1,
      );

      expect(updated.enabled, isFalse);
      expect(updated.languageTag, 'en-US');
      expect(updated.volume, 0.5);
      expect(updated.speakingRate, 0.8);
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

    test('asserts on invalid speakingRate', () {
      expect(
        () => VoiceGuidanceConfig(speakingRate: 0.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => VoiceGuidanceConfig(speakingRate: 2.5),
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

  group('VoiceGuidanceConfig per-profile speakingRate', () {
    test('snowZoneExperienced returns 1.0 (engine-base rate)', () {
      expect(
        VoiceGuidanceConfig.speakingRateForProfile(
            DriverProfile.snowZoneExperienced),
        1.0,
      );
    });

    test('professional + agriculturalForestry return 1.0', () {
      expect(
        VoiceGuidanceConfig.speakingRateForProfile(DriverProfile.professional),
        1.0,
      );
      expect(
        VoiceGuidanceConfig.speakingRateForProfile(
            DriverProfile.agriculturalForestry),
        1.0,
      );
    });

    test('noviceUrban returns 0.85', () {
      expect(
        VoiceGuidanceConfig.speakingRateForProfile(DriverProfile.noviceUrban),
        0.85,
      );
    });

    test('ageingRural returns 0.70', () {
      expect(
        VoiceGuidanceConfig.speakingRateForProfile(DriverProfile.ageingRural),
        0.70,
      );
    });

    test('foreignTouristSnowZone returns 0.70', () {
      expect(
        VoiceGuidanceConfig.speakingRateForProfile(
            DriverProfile.foreignTouristSnowZone),
        0.70,
      );
    });

    test('forProfile returns a config with the correct per-profile rate', () {
      const base = VoiceGuidanceConfig(volume: 0.7, languageTag: 'en-US');
      final tuned = base.forProfile(DriverProfile.foreignTouristSnowZone);
      expect(tuned.speakingRate, 0.70);
      // Other fields preserved.
      expect(tuned.volume, 0.7);
      expect(tuned.languageTag, 'en-US');
    });

    test('all DriverProfile values have a published multiplier', () {
      for (final profile in DriverProfile.values) {
        expect(
          kSpeakingRateMultiplierByProfile.containsKey(profile),
          isTrue,
          reason:
              'DriverProfile.${profile.name} must have a published multiplier',
        );
      }
    });
  });
}
