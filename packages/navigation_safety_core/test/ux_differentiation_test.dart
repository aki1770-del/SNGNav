/// Tests for the activated `assertUxDifferentiated()` hook + the
/// supporting registration registry.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('UX differentiation registry', () {
    setUp(debugClearUxDifferentiatorRegistry);

    test('empty registry: no tags registered for any profile', () {
      for (final p in DriverProfile.values) {
        expect(registeredUxDifferentiators(p), isEmpty);
      }
    });

    test('registerUxDifferentiator records the tag for that profile only', () {
      registerUxDifferentiator(
        DriverProfile.foreignTouristSnowZone,
        'voice_guidance:speakingRate',
      );
      expect(
        registeredUxDifferentiators(DriverProfile.foreignTouristSnowZone),
        contains('voice_guidance:speakingRate'),
      );
      expect(
        registeredUxDifferentiators(DriverProfile.snowZoneExperienced),
        isEmpty,
      );
    });

    test('registerUxDifferentiator is idempotent on (profile,tag) pair', () {
      registerUxDifferentiator(
        DriverProfile.ageingRural,
        'voice_guidance:speakingRate',
      );
      registerUxDifferentiator(
        DriverProfile.ageingRural,
        'voice_guidance:speakingRate',
      );
      expect(
        registeredUxDifferentiators(DriverProfile.ageingRural),
        hasLength(1),
      );
    });

    test('registerUxDifferentiator accumulates distinct tags per profile', () {
      registerUxDifferentiator(
        DriverProfile.noviceUrban,
        'voice_guidance:speakingRate',
      );
      registerUxDifferentiator(
        DriverProfile.noviceUrban,
        'navigation_safety:modalDuration',
      );
      registerUxDifferentiator(
        DriverProfile.noviceUrban,
        'navigation_safety:explainer',
      );
      expect(
        registeredUxDifferentiators(DriverProfile.noviceUrban),
        hasLength(3),
      );
    });

    test('registeredUxDifferentiators returns an unmodifiable view', () {
      registerUxDifferentiator(
        DriverProfile.professional,
        'voice_guidance:speakingRate',
      );
      final view = registeredUxDifferentiators(DriverProfile.professional);
      expect(() => view.add('mutation-attempt'), throwsUnsupportedError);
    });
  });

  group('assertUxDifferentiated', () {
    setUp(debugClearUxDifferentiatorRegistry);

    test(
      'debug build: throws AssertionError when no differentiator is registered',
      () {
        expect(
          () => assertUxDifferentiated(DriverProfile.foreignTouristSnowZone),
          throwsA(
            isA<AssertionError>().having(
              (e) => e.message.toString(),
              'message',
              allOf(
                contains('foreignTouristSnowZone'),
                contains('registerUxDifferentiator'),
              ),
            ),
          ),
        );
      },
    );

    test(
      'debug build: returns normally when at least one tag is registered',
      () {
        registerUxDifferentiator(
          DriverProfile.foreignTouristSnowZone,
          'voice_guidance:speakingRate',
        );
        // No throw expected.
        assertUxDifferentiated(DriverProfile.foreignTouristSnowZone);
      },
    );

    test('passes for one profile, fails for another in the same registry', () {
      registerUxDifferentiator(
        DriverProfile.snowZoneExperienced,
        'voice_guidance:speakingRate',
      );
      // Registered profile passes.
      assertUxDifferentiated(DriverProfile.snowZoneExperienced);
      // Unregistered profile fails.
      expect(
        () => assertUxDifferentiated(DriverProfile.ageingRural),
        throwsA(isA<AssertionError>()),
      );
    });

    test('error message references published evidence anchors', () {
      try {
        assertUxDifferentiated(DriverProfile.ageingRural);
        fail('expected AssertionError');
      } on AssertionError catch (e) {
        final msg = e.message.toString();
        expect(msg, contains('38669900'));
        expect(msg, contains('PMC7283540'));
      }
    });
  });
}
