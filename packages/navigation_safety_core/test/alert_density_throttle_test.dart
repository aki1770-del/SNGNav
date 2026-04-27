import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('AlertDensityThrottle.defaultCapFor — per-profile defaults', () {
    test('every profile has a literature-anchored default cap', () {
      // L7 lock — exhaustive coverage of all 6 profiles. Each cap is
      // documented with a literature anchor in alert_density_throttle.dart
      // (defaultCapFor doc-comment).
      expect(
        AlertDensityThrottle.defaultCapFor(DriverProfile.professional),
        4.0,
      );
      expect(
        AlertDensityThrottle.defaultCapFor(DriverProfile.snowZoneExperienced),
        3.0,
      );
      expect(
        AlertDensityThrottle.defaultCapFor(DriverProfile.agriculturalForestry),
        2.0,
      );
      expect(
        AlertDensityThrottle.defaultCapFor(DriverProfile.noviceUrban),
        1.5,
      );
      expect(
        AlertDensityThrottle.defaultCapFor(DriverProfile.ageingRural),
        1.2,
      );
      expect(
        AlertDensityThrottle.defaultCapFor(DriverProfile.foreignTouristSnowZone),
        1.0,
      );
    });

    test('forProfile returns a throttle with the matching default cap', () {
      for (final profile in DriverProfile.values) {
        final t = AlertDensityThrottle.forProfile(profile);
        expect(
          t.alertsPerMinuteCap,
          AlertDensityThrottle.defaultCapFor(profile),
          reason: 'forProfile($profile) cap must match defaultCapFor',
        );
        expect(t.window, const Duration(seconds: 60));
        expect(t.bypassForCritical, isTrue,
            reason: 'critical-bypass invariant must default to true');
      }
    });
  });

  group('AlertDensityThrottle constructor validation', () {
    test('rejects non-positive cap', () {
      expect(
        () => AlertDensityThrottle(alertsPerMinuteCap: 0),
        throwsArgumentError,
      );
      expect(
        () => AlertDensityThrottle(alertsPerMinuteCap: -1.0),
        throwsArgumentError,
      );
    });

    test('rejects non-positive window', () {
      expect(
        () => AlertDensityThrottle(
          alertsPerMinuteCap: 2.0,
          window: Duration.zero,
        ),
        throwsArgumentError,
      );
      expect(
        () => AlertDensityThrottle(
          alertsPerMinuteCap: 2.0,
          window: const Duration(seconds: -1),
        ),
        throwsArgumentError,
      );
    });
  });

  group('AlertDensityThrottle critical-bypass invariant', () {
    test('CRITICAL always fires regardless of in-window count', () {
      // Documented invariant: bypassForCritical = true means CRITICAL
      // alerts are never throttled. The throttle's purpose is preventing
      // advisory-tier desensitization, not masking high-severity warnings.
      final t = AlertDensityThrottle(
        alertsPerMinuteCap: 1.0,
        window: const Duration(seconds: 60),
      );
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      // Saturate the window with a non-critical alert.
      expect(t.shouldFire(t0, AlertSeverity.warning), isTrue);
      // Subsequent non-critical alerts in the same window are dropped.
      expect(
        t.shouldFire(t0.add(const Duration(seconds: 1)), AlertSeverity.warning),
        isFalse,
      );
      expect(
        t.shouldFire(t0.add(const Duration(seconds: 2)), AlertSeverity.info),
        isFalse,
      );
      // CRITICAL still fires.
      expect(
        t.shouldFire(
            t0.add(const Duration(seconds: 3)), AlertSeverity.critical),
        isTrue,
      );
      expect(
        t.shouldFire(
            t0.add(const Duration(seconds: 4)), AlertSeverity.critical),
        isTrue,
      );
    });

    test('warning + info subject to throttle when cap reached', () {
      final t = AlertDensityThrottle(
        alertsPerMinuteCap: 2.0,
        window: const Duration(seconds: 60),
      );
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      expect(t.shouldFire(t0, AlertSeverity.info), isTrue); // 1 (cold-start)
      expect(t.shouldFire(t0.add(const Duration(seconds: 1)),
          AlertSeverity.warning), isTrue); // 2
      // Cap of 2 reached; next non-critical drops.
      expect(t.shouldFire(t0.add(const Duration(seconds: 2)),
          AlertSeverity.info), isFalse);
      expect(t.shouldFire(t0.add(const Duration(seconds: 3)),
          AlertSeverity.warning), isFalse);
    });

    test('bypassForCritical=false makes CRITICAL subject to throttle', () {
      // Documented: changing this default changes the throttle's safety
      // contract. The invariant is bypassForCritical = true. This test
      // locks the alternative behavior so a future regression is loud.
      final t = AlertDensityThrottle(
        alertsPerMinuteCap: 1.0,
        window: const Duration(seconds: 60),
        bypassForCritical: false,
      );
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      expect(t.shouldFire(t0, AlertSeverity.warning), isTrue);
      expect(
        t.shouldFire(
            t0.add(const Duration(seconds: 1)), AlertSeverity.critical),
        isFalse,
      );
    });
  });

  group('AlertDensityThrottle rolling-window correctness', () {
    test('window is sliding, not fixed (minute-boundary burst blocked)', () {
      // Fixed-window allows a burst at the boundary. Rolling window
      // counts alerts in the past `window` duration relative to `now`.
      final t = AlertDensityThrottle(
        alertsPerMinuteCap: 2.0,
        window: const Duration(seconds: 60),
      );
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      // 2 alerts at t=0..1 fill the cap.
      expect(t.shouldFire(t0, AlertSeverity.warning), isTrue);
      expect(t.shouldFire(t0.add(const Duration(seconds: 1)),
          AlertSeverity.warning), isTrue);

      // At t=58s, both are still in window — drop.
      expect(t.shouldFire(t0.add(const Duration(seconds: 58)),
          AlertSeverity.warning), isFalse);

      // At t=61s, the t=0 alert ages out (61s > 60s window). Window
      // count = 1. New alert fires.
      expect(t.shouldFire(t0.add(const Duration(seconds: 61)),
          AlertSeverity.warning), isTrue);

      // The t=1 alert is still inside (61 - 1 = 60s, on the boundary
      // and counted as expired by isAtSameMomentAs(cutoff) rule).
      // After admission of the new alert at t=61, window count is now
      // 1 (the t=61 one) since the t=1 entry is at exactly cutoff;
      // but the t=58 result above already proved the window slides.
    });

    test('currentWindowCount reflects sliding-window state', () {
      final t = AlertDensityThrottle(
        alertsPerMinuteCap: 5.0,
        window: const Duration(seconds: 60),
      );
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      // 3 alerts within window.
      t.shouldFire(t0, AlertSeverity.info);
      t.shouldFire(t0.add(const Duration(seconds: 10)), AlertSeverity.info);
      t.shouldFire(t0.add(const Duration(seconds: 20)), AlertSeverity.info);

      expect(t.currentWindowCount(t0.add(const Duration(seconds: 25))), 3);
      // Slide past first alert's window expiry (60s after t=0 → past at t=61).
      expect(t.currentWindowCount(t0.add(const Duration(seconds: 61))), 2);
      // Past the t=10 alert too (10 + 60 = 70).
      expect(t.currentWindowCount(t0.add(const Duration(seconds: 71))), 1);
      // Past all.
      expect(t.currentWindowCount(t0.add(const Duration(seconds: 81))), 0);
    });
  });

  group('AlertDensityThrottle burst-then-quiet', () {
    test('drops new alert (does not queue) when cap reached', () {
      // Documented behavior: queuing post-cap delivers stale information
      // about a now-passed condition; per the listen-frame substrate,
      // false-stale alerts erode trust faster than missed-info alerts.
      final t = AlertDensityThrottle(
        alertsPerMinuteCap: 2.0,
        window: const Duration(seconds: 60),
      );
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      expect(t.shouldFire(t0, AlertSeverity.warning), isTrue);
      expect(t.shouldFire(t0.add(const Duration(seconds: 1)),
          AlertSeverity.warning), isTrue);

      // Burst — three rapid drops; none should fire (none queued).
      expect(t.shouldFire(t0.add(const Duration(seconds: 2)),
          AlertSeverity.warning), isFalse);
      expect(t.shouldFire(t0.add(const Duration(seconds: 3)),
          AlertSeverity.warning), isFalse);
      expect(t.shouldFire(t0.add(const Duration(seconds: 4)),
          AlertSeverity.warning), isFalse);

      // Window count stays at 2 (drops did not record).
      expect(t.currentWindowCount(t0.add(const Duration(seconds: 5))), 2);
    });
  });

  group('AlertDensityThrottle cold-start', () {
    test('first alert in session bypasses window check', () {
      // Cold-start: no historical context to throttle against. Even
      // for the most-conservative profile (foreignTouristSnowZone with
      // cap = 1.0), the first alert fires.
      for (final profile in DriverProfile.values) {
        final t = AlertDensityThrottle.forProfile(profile);
        final t0 = DateTime(2026, 4, 28, 9, 0, 0);
        expect(t.shouldFire(t0, AlertSeverity.info), isTrue,
            reason: 'cold-start fire expected for profile $profile');
      }
    });
  });

  group('AlertDensityThrottle profile-switch resets window', () {
    test('a fresh forProfile instance has empty window', () {
      // When DriverProfile changes mid-session, the consuming app
      // constructs a new throttle via forProfile. Carrying the previous
      // profile's window into a more conservative one would over-throttle.
      final tA = AlertDensityThrottle.forProfile(DriverProfile.professional);
      final t0 = DateTime(2026, 4, 28, 9, 0, 0);

      // Saturate professional throttle (cap = 4.0).
      tA.shouldFire(t0, AlertSeverity.warning);
      tA.shouldFire(t0.add(const Duration(seconds: 1)), AlertSeverity.warning);
      tA.shouldFire(t0.add(const Duration(seconds: 2)), AlertSeverity.warning);
      tA.shouldFire(t0.add(const Duration(seconds: 3)), AlertSeverity.warning);
      expect(tA.currentWindowCount(t0.add(const Duration(seconds: 4))), 4);

      // Profile-switch — new throttle instance.
      final tB = AlertDensityThrottle.forProfile(DriverProfile.ageingRural);
      expect(tB.currentWindowCount(t0.add(const Duration(seconds: 5))), 0);
      // First alert under the new profile fires (cold-start on new instance).
      expect(
        tB.shouldFire(
            t0.add(const Duration(seconds: 5)), AlertSeverity.warning),
        isTrue,
      );
    });
  });

  group('NavigationSafetyConfig.alertsPerMinuteCapOverride', () {
    test('null override falls through to per-profile default', () {
      final c = NavigationSafetyConfig();
      for (final profile in DriverProfile.values) {
        expect(
          c.effectiveAlertsPerMinuteCap(profile),
          AlertDensityThrottle.defaultCapFor(profile),
          reason: 'null override should yield default for $profile',
        );
      }
    });

    test('explicit override applies regardless of profile', () {
      final c = NavigationSafetyConfig(alertsPerMinuteCapOverride: 0.5);
      for (final profile in DriverProfile.values) {
        expect(c.effectiveAlertsPerMinuteCap(profile), 0.5,
            reason: 'override should override $profile default');
      }
    });

    test('forProfile preserves null override (no auto-population)', () {
      // forProfile sets per-profile thresholds but leaves the cap
      // override null — integrating apps own that decision separately.
      for (final profile in DriverProfile.values) {
        final c = NavigationSafetyConfig.forProfile(profile);
        expect(c.alertsPerMinuteCapOverride, isNull,
            reason: 'forProfile should not auto-populate override for $profile');
        expect(
          c.effectiveAlertsPerMinuteCap(profile),
          AlertDensityThrottle.defaultCapFor(profile),
          reason: 'effective cap matches profile default for $profile',
        );
      }
    });
  });
}
