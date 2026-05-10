/// Tests for per-profile modal-alert duration primitive (0.7.0).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

void main() {
  group('modalAlertDurationFor', () {
    test('snowZoneExperienced -> engine-base 5000ms (multiplier 1.0)', () {
      final d = modalAlertDurationFor(DriverProfile.snowZoneExperienced);
      expect(d, kModalAlertDurationBase);
      expect(d.inMilliseconds, 5000);
    });

    test('professional -> engine-base 5000ms (multiplier 1.0)', () {
      final d = modalAlertDurationFor(DriverProfile.professional);
      expect(d.inMilliseconds, 5000);
    });

    test('agriculturalForestry -> 6000ms (multiplier 1.2)', () {
      final d = modalAlertDurationFor(DriverProfile.agriculturalForestry);
      expect(d.inMilliseconds, 6000);
    });

    test('noviceUrban -> 6500ms (multiplier 1.3)', () {
      final d = modalAlertDurationFor(DriverProfile.noviceUrban);
      expect(d.inMilliseconds, 6500);
    });

    test('ageingRural -> 7500ms (multiplier 1.5)', () {
      final d = modalAlertDurationFor(DriverProfile.ageingRural);
      expect(d.inMilliseconds, 7500);
    });

    test('foreignTouristSnowZone -> 7500ms (multiplier 1.5)', () {
      final d = modalAlertDurationFor(DriverProfile.foreignTouristSnowZone);
      expect(d.inMilliseconds, 7500);
    });

    test('multipliers are conservative-only (>= 1.0 for all profiles)', () {
      for (final entry in kModalAlertDurationMultiplierByProfile.entries) {
        expect(
          entry.value,
          greaterThanOrEqualTo(1.0),
          reason:
              'Profile ${entry.key} got multiplier ${entry.value}; '
              'conservative-only direction requires >= 1.0',
        );
      }
    });

    test('every DriverProfile has a multiplier entry', () {
      for (final p in DriverProfile.values) {
        expect(
          kModalAlertDurationMultiplierByProfile.containsKey(p),
          isTrue,
          reason:
              'DriverProfile $p has no multiplier entry; modal-alert '
              'duration would fall back to engine-base.',
        );
      }
    });

    test(
      'returned Duration scales linearly with engine-base (sanity check)',
      () {
        // multiplier 1.5 = 1.5x engine-base
        final ageingRural = modalAlertDurationFor(DriverProfile.ageingRural);
        expect(
          ageingRural.inMicroseconds,
          (kModalAlertDurationBase.inMicroseconds * 1.5).round(),
        );
      },
    );

    test('severity-not-profile invariant preserved at primitive boundary', () {
      // Sanity: this primitive consumes ONLY DriverProfile, not
      // AlertSeverity. If a future change adds severity to the API,
      // it would couple presentation-class state to severity-class
      // gating, which the per-package SAFETY_BOUNDARY.md §6 invariant
      // forbids. This test exists as a documentation-class lock.
      // The function signature is single-arg DriverProfile.
      final d = modalAlertDurationFor(DriverProfile.ageingRural);
      expect(d, isA<Duration>());
    });
  });
}
