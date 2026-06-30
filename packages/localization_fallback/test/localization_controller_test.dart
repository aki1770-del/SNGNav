import 'package:localization_fallback/localization_fallback.dart';
import 'package:test/test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 8, 0, 0);

  RawFix fix(
    double lat,
    double lon, {
    double acc = 6,
    int seconds = 0,
  }) =>
      RawFix(
        latitude: lat,
        longitude: lon,
        accuracyMeters: acc,
        timestamp: t0.add(Duration(seconds: seconds)),
      );

  // A constant-velocity DR seam crawling north from a fixed point.
  DeadReckoningSeam northSeam(double lat, double lon, double mps) =>
      (asOf) {
        final dt = asOf.difference(t0).inMicroseconds / 1e6;
        return DeadReckoningEstimate(
          latitude: lat + (mps * dt) / 111320.0,
          longitude: lon,
        );
      };

  group('state transitions', () {
    test('first trusted fix → gpsTrusted at receiver accuracy', () {
      final c = LocalizationController();
      final e = c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      expect(e.mode, LocalizationMode.gpsTrusted);
      expect(e.confidenceRadiusMeters, 6);
      expect(e.secondsSinceTrustedFix, 0);
      expect(e.basis, EstimateBasis.trustedGpsFix);
      expect(e.isConfident, isTrue);
    });

    test('trusted → suspect enters gpsSuspect, not gpsTrusted', () {
      final c = LocalizationController(
          deadReckoningSeam: northSeam(39.70, 140.10, 10));
      c.onFix(fix(39.70, 140.10), trust: TrustSignal.trusted);
      final e = c.onFix(fix(39.71, 140.11, seconds: 3),
          trust: TrustSignal.suspect);
      expect(e.mode, LocalizationMode.gpsSuspect);
      expect(e.isConfident, isFalse);
    });

    test('trusted → failed enters deadReckoning', () {
      final c = LocalizationController(
          deadReckoningSeam: northSeam(39.70, 140.10, 10));
      c.onFix(fix(39.70, 140.10), trust: TrustSignal.trusted);
      final e =
          c.onFix(fix(39.70, 140.10, seconds: 3), trust: TrustSignal.failed);
      expect(e.mode, LocalizationMode.deadReckoning);
      expect(e.basis, EstimateBasis.deadReckoning);
    });

    test('poll after a long gap degrades to dead reckoning', () {
      final c = LocalizationController(
          deadReckoningSeam: northSeam(39.70, 140.10, 10));
      c.onFix(fix(39.70, 140.10), trust: TrustSignal.trusted);
      final e = c.poll(t0.add(const Duration(seconds: 8)));
      expect(e.mode, LocalizationMode.deadReckoning);
      expect(e.secondsSinceTrustedFix, closeTo(8, 0.001));
    });
  });

  group('honesty contract', () {
    test('radius is monotonic non-decreasing while not trusted', () {
      final c = LocalizationController(
        config: const LocalizationConfig(
          driftRateMetersPerSecond: 4,
          maxTrustworthyRadiusMeters: 5000, // keep out of lost for this test
          maxDeadReckoningSeconds: 5000,
        ),
        deadReckoningSeam: northSeam(39.70, 140.10, 10),
      );
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      var prev = -1.0;
      for (var s = 1; s <= 60; s++) {
        final e = c.poll(t0.add(Duration(seconds: s)));
        expect(e.confidenceRadiusMeters, greaterThanOrEqualTo(prev),
            reason: 'radius shrank at t+${s}s');
        prev = e.confidenceRadiusMeters;
      }
    });

    test('a seam that under-reports accuracy cannot shrink the radius', () {
      // Seam always claims a tiny 1 m accuracy; growth model must dominate and
      // monotonicity must hold.
      DeadReckoningEstimate? lyingSeam(DateTime asOf) =>
          const DeadReckoningEstimate(
            latitude: 39.70,
            longitude: 140.10,
            estimatedAccuracyMeters: 1.0,
          );
      final c = LocalizationController(
        config: const LocalizationConfig(
            driftRateMetersPerSecond: 5,
            maxTrustworthyRadiusMeters: 100000,
            maxDeadReckoningSeconds: 100000),
        deadReckoningSeam: lyingSeam,
      );
      c.onFix(fix(39.70, 140.10, acc: 10), trust: TrustSignal.trusted);
      final a = c.poll(t0.add(const Duration(seconds: 10)));
      final b = c.poll(t0.add(const Duration(seconds: 20)));
      expect(a.confidenceRadiusMeters, greaterThan(10));
      expect(b.confidenceRadiusMeters,
          greaterThanOrEqualTo(a.confidenceRadiusMeters));
    });

    test('confidently-wrong suspect fix is NOT blended into the position', () {
      // Held at last trusted point (no seam), so the wild jump must be ignored.
      final c = LocalizationController();
      c.onFix(fix(39.7000, 140.1000), trust: TrustSignal.trusted);
      final e = c.onFix(
        fix(39.9999, 140.9999, acc: 3, seconds: 4), // confident + far wrong
        trust: TrustSignal.suspect,
      );
      // Position stays at last trusted (no seam wired → lastKnownPosition).
      expect(e.latitude, closeTo(39.7000, 1e-9));
      expect(e.longitude, closeTo(140.1000, 1e-9));
      expect(e.basis, EstimateBasis.lastKnownPosition);
      expect(e.mode, isNot(LocalizationMode.gpsTrusted));
    });

    test('a failed fix never produces a confident estimate', () {
      final c = LocalizationController();
      c.onFix(fix(39.70, 140.10), trust: TrustSignal.trusted);
      final e = c.onFix(fix(39.70, 140.10, acc: 2, seconds: 3),
          trust: TrustSignal.failed);
      expect(e.isConfident, isFalse);
    });

    test('non-finite geometry is forced to failed even if marked trusted', () {
      final c = LocalizationController();
      c.onFix(fix(39.70, 140.10), trust: TrustSignal.trusted);
      final e = c.onFix(
        RawFix(
          latitude: double.nan,
          longitude: 140.10,
          accuracyMeters: 5,
          timestamp: t0.add(const Duration(seconds: 3)),
        ),
        trust: TrustSignal.trusted, // caller lies; we must not believe it
      );
      expect(e.mode, isNot(LocalizationMode.gpsTrusted));
      // Falls back to last-known trusted position.
      expect(e.latitude, closeTo(39.70, 1e-9));
    });

    test('every estimate carries a basis', () {
      final c = LocalizationController(
          deadReckoningSeam: northSeam(39.70, 140.10, 10));
      final basisSeen = <EstimateBasis>{};
      basisSeen.add(c.onFix(fix(39.70, 140.10), trust: TrustSignal.trusted).basis);
      basisSeen.add(c.poll(t0.add(const Duration(seconds: 8))).basis);
      expect(basisSeen, contains(EstimateBasis.trustedGpsFix));
      expect(basisSeen, contains(EstimateBasis.deadReckoning));
    });
  });

  group('lost horizon', () {
    test('radius beyond maxTrustworthyRadius → lost', () {
      final c = LocalizationController(
        config: const LocalizationConfig(
          driftRateMetersPerSecond: 50, // grows fast
          maxTrustworthyRadiusMeters: 200,
          maxDeadReckoningSeconds: 100000,
        ),
        deadReckoningSeam: northSeam(39.70, 140.10, 10),
      );
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      final e = c.poll(t0.add(const Duration(seconds: 30))); // ~1506 m radius
      expect(e.mode, LocalizationMode.lost);
      expect(e.confidenceRadiusMeters, greaterThan(200));
      // lost still returns a usable position, not NaN, because we had a baseline.
      expect(e.latitude.isFinite, isTrue);
    });

    test('time beyond maxDeadReckoningSeconds → lost', () {
      final c = LocalizationController(
        config: const LocalizationConfig(
          driftRateMetersPerSecond: 0.1, // radius stays tiny
          maxTrustworthyRadiusMeters: 100000,
          maxDeadReckoningSeconds: 60,
        ),
        deadReckoningSeam: northSeam(39.70, 140.10, 1),
      );
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      final ok = c.poll(t0.add(const Duration(seconds: 30)));
      expect(ok.mode, LocalizationMode.deadReckoning);
      final lost = c.poll(t0.add(const Duration(seconds: 90)));
      expect(lost.mode, LocalizationMode.lost);
    });

    test('no trusted baseline ever → lost (unanchored guess or NaN)', () {
      final c = LocalizationController();
      // poll with nothing seen → lost + NaN, honest.
      final p = c.poll(t0);
      expect(p.mode, LocalizationMode.lost);
      expect(p.basis, EstimateBasis.unanchoredGuess);
      expect(p.confidenceRadiusMeters, double.infinity);

      // a failed first fix → lost, coarse guess at huge radius, never confident.
      final f = c.onFix(fix(39.70, 140.10, acc: 5, seconds: 1),
          trust: TrustSignal.failed);
      expect(f.mode, LocalizationMode.lost);
      expect(f.basis, EstimateBasis.unanchoredGuess);
      expect(f.confidenceRadiusMeters,
          greaterThanOrEqualTo(c.config.maxTrustworthyRadiusMeters));
    });
  });

  group('reconvergence', () {
    test('a trusted fix after lost reconverges and shrinks the radius', () {
      final c = LocalizationController(
        config: const LocalizationConfig(
          driftRateMetersPerSecond: 20,
          maxTrustworthyRadiusMeters: 300,
          maxDeadReckoningSeconds: 120,
        ),
        deadReckoningSeam: northSeam(39.70, 140.10, 10),
      );
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      final lost = c.poll(t0.add(const Duration(seconds: 60)));
      expect(lost.mode, LocalizationMode.lost);
      expect(lost.confidenceRadiusMeters, greaterThan(300));

      final back = c.onFix(fix(39.7050, 140.1040, acc: 7, seconds: 65),
          trust: TrustSignal.trusted);
      expect(back.mode, LocalizationMode.gpsTrusted);
      expect(back.confidenceRadiusMeters, 7); // ONLY a trusted fix may shrink it
      expect(back.secondsSinceTrustedFix, 0);
      expect(back.basis, EstimateBasis.trustedGpsFix);
    });

    test('radius floor resets after reconvergence (new degradation starts low)',
        () {
      final c = LocalizationController(
        config: const LocalizationConfig(
          driftRateMetersPerSecond: 5,
          maxTrustworthyRadiusMeters: 100000,
          maxDeadReckoningSeconds: 100000,
        ),
        deadReckoningSeam: northSeam(39.70, 140.10, 10),
      );
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      final grown = c.poll(t0.add(const Duration(seconds: 60)));
      expect(grown.confidenceRadiusMeters, greaterThan(100));
      // reconverge
      c.onFix(fix(39.70, 140.10, acc: 6, seconds: 61),
          trust: TrustSignal.trusted);
      // degrade again briefly: radius must start small again, not at old floor.
      final fresh = c.poll(t0.add(const Duration(seconds: 63)));
      expect(fresh.confidenceRadiusMeters, lessThan(grown.confidenceRadiusMeters));
    });
  });

  group('trusted-path honesty horizon (finding #1)', () {
    test('a trusted fix whose accuracy exceeds the horizon is NOT confident', () {
      final c = LocalizationController(
        config: const LocalizationConfig(maxTrustworthyRadiusMeters: 500),
      );
      // Single-constellation fix in a deep canyon: tagged trusted, 2 km accuracy.
      final e = c.onFix(fix(39.70, 140.10, acc: 2000),
          trust: TrustSignal.trusted);
      expect(e.isConfident, isFalse);
      expect(e.mode, LocalizationMode.lost);
      // Still adopted as the baseline position + radius (honest, just not tight).
      expect(e.confidenceRadiusMeters, 2000);
      expect(e.basis, EstimateBasis.trustedGpsFix);
    });

    test('a precise trusted fix is still confident (regression guard)', () {
      final c = LocalizationController(
        config: const LocalizationConfig(maxTrustworthyRadiusMeters: 500),
      );
      final e = c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      expect(e.isConfident, isTrue);
      expect(e.mode, LocalizationMode.gpsTrusted);
    });
  });

  group('timestamp sanity (findings #4 / #7 / #8)', () {
    test('an out-of-order trusted fix does not snap the dot or rewind the clock',
        () {
      final c = LocalizationController();
      c.onFix(fix(39.7000, 140.1000, acc: 6, seconds: 30),
          trust: TrustSignal.trusted);
      // A delayed/replayed trusted fix stamped EARLIER, at a far-away position.
      final e = c.onFix(fix(39.9999, 140.9999, acc: 3, seconds: 5),
          trust: TrustSignal.trusted);
      // Not presented as a current confident dot.
      expect(e.isConfident, isFalse);
      expect(e.mode, isNot(LocalizationMode.gpsTrusted));
      // Dot stays at the last good baseline, not the stale coordinates.
      expect(e.latitude, closeTo(39.7000, 1e-9));
      expect(e.longitude, closeTo(140.1000, 1e-9));
      // The clock was not rewound: a later poll still measures from t+30s.
      final p = c.poll(t0.add(const Duration(seconds: 40)));
      expect(p.secondsSinceTrustedFix, closeTo(10, 0.001));
    });

    test('an identical-timestamp trusted fix is treated as non-current', () {
      final c = LocalizationController();
      c.onFix(fix(39.70, 140.10, acc: 6, seconds: 10),
          trust: TrustSignal.trusted);
      final e = c.onFix(fix(39.80, 140.20, acc: 4, seconds: 10),
          trust: TrustSignal.trusted);
      expect(e.isConfident, isFalse);
      expect(e.latitude, closeTo(39.70, 1e-9)); // duplicate ignored, not snapped
    });

    test('out-of-order poll cannot drive a negative elapsed time (clamp)', () {
      final c = LocalizationController();
      c.onFix(fix(39.70, 140.10, acc: 6, seconds: 30),
          trust: TrustSignal.trusted);
      final e = c.poll(t0.add(const Duration(seconds: 10))); // before baseline
      expect(e.secondsSinceTrustedFix, 0.0); // clamped, never negative
      expect(e.confidenceRadiusMeters, greaterThanOrEqualTo(6));
    });
  });

  group('frozen-path speed floor (finding #13)', () {
    test('last known speed widens the radius when the dot is frozen', () {
      // No seam: the dot freezes at last-known. A 25 m/s vehicle must grow the
      // circle far faster than the gentle 2 m/s drift default alone would.
      final cSlow = LocalizationController(
        config: const LocalizationConfig(
            driftRateMetersPerSecond: 2, maxTrustworthyRadiusMeters: 1e9),
      );
      final cFast = LocalizationController(
        config: const LocalizationConfig(
            driftRateMetersPerSecond: 2, maxTrustworthyRadiusMeters: 1e9),
      );
      RawFix moving(double speed) => RawFix(
            latitude: 39.70,
            longitude: 140.10,
            accuracyMeters: 6,
            timestamp: t0,
            speedMps: speed,
          );
      cSlow.onFix(moving(0), trust: TrustSignal.trusted);
      cFast.onFix(moving(25), trust: TrustSignal.trusted);
      final slow = cSlow.poll(t0.add(const Duration(seconds: 60)));
      final fast = cFast.poll(t0.add(const Duration(seconds: 60)));
      // 25 m/s * 60s ≈ 1500 m, vs 2 m/s * 60s ≈ 120 m.
      expect(fast.confidenceRadiusMeters,
          greaterThan(slow.confidenceRadiusMeters * 5));
      expect(fast.confidenceRadiusMeters, greaterThan(1400));
    });
  });

  group('lost is terminal until reconvergence (resurrection guard)', () {
    // Config where only the TIME horizon (not the radius) can trigger lost, so
    // we can probe whether a non-monotonic clock un-loses us.
    LocalizationController timeLostController() => LocalizationController(
          config: const LocalizationConfig(
            driftRateMetersPerSecond: 0.1, // radius stays tiny → never lost on radius
            maxTrustworthyRadiusMeters: 100000,
            maxDeadReckoningSeconds: 60,
          ),
          deadReckoningSeam: northSeam(39.70, 140.10, 1),
        );

    test('a backwards / out-of-order poll cannot un-lose a time-triggered lost',
        () {
      final c = timeLostController();
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      final lost = c.poll(t0.add(const Duration(seconds: 90)));
      expect(lost.mode, LocalizationMode.lost, reason: 'should be lost at t+90s');
      // Clock jumps backwards (NTP correction / replayed tick). Without the
      // lost-latch this resurrected to deadReckoning — a confidence increase
      // with NO trusted fix, violating the honesty contract.
      final back = c.poll(t0.add(const Duration(seconds: 30)));
      expect(back.mode, LocalizationMode.lost,
          reason: 'lost must stay lost until a TRUSTED fix re-acquires');
    });

    test('a suspect fix after lost does not silently restore gpsSuspect', () {
      final c = timeLostController();
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      expect(c.poll(t0.add(const Duration(seconds: 90))).mode,
          LocalizationMode.lost);
      // An earlier-stamped suspect fix used to un-lose to gpsSuspect.
      final e = c.onFix(fix(39.70, 140.10, acc: 5, seconds: 35),
          trust: TrustSignal.suspect);
      expect(e.mode, LocalizationMode.lost,
          reason: 'a non-trusted fix can never re-acquire from lost');
      expect(e.isConfident, isFalse);
    });

    test('a failed fix after lost stays lost', () {
      final c = timeLostController();
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      expect(c.poll(t0.add(const Duration(seconds: 90))).mode,
          LocalizationMode.lost);
      final e = c.onFix(fix(39.70, 140.10, acc: 5, seconds: 35),
          trust: TrustSignal.failed);
      expect(e.mode, LocalizationMode.lost);
    });

    test('ONLY a fresh trusted fix re-acquires after lost (latch clears)', () {
      final c = timeLostController();
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      expect(c.poll(t0.add(const Duration(seconds: 90))).mode,
          LocalizationMode.lost);
      // A genuine, newer trusted fix is the one and only way back.
      final back = c.onFix(fix(39.7005, 140.1005, acc: 7, seconds: 100),
          trust: TrustSignal.trusted);
      expect(back.mode, LocalizationMode.gpsTrusted);
      expect(back.confidenceRadiusMeters, 7);
      // ...and after re-acquisition we may degrade to a non-lost state again.
      final dr = c.poll(t0.add(const Duration(seconds: 102)));
      expect(dr.mode, LocalizationMode.deadReckoning);
    });
  });

  group('garbage configured drift cannot fabricate precision (release hardening)',
      () {
    // DEBUG guard: LocalizationConfig asserts driftRate >= 0, so a garbage value
    // is rejected at construction time when asserts are enabled (as they are
    // under `dart test`). This locks in that the config validates its input.
    //
    // RELEASE guard (NOT reachable from this asserted suite — asserts are
    // STRIPPED in release / `dart run`): if a release build still supplies a
    // garbage drift, the controller's _degraded() clamps the radius to never
    // fall below the last trusted accuracy (no false 0 m "exactly here" dot) and
    // forces `lost`. That path is verified out-of-band with asserts disabled,
    // because here the constructor throws before the controller can run.
    for (final rate in <double>[
      double.nan,
      double.negativeInfinity,
      -5.0,
    ]) {
      test('drift=$rate is rejected at construction (debug assert guard)', () {
        expect(
          () => LocalizationConfig(driftRateMetersPerSecond: rate),
          throwsA(isA<AssertionError>()),
        );
      });
    }

    test('a sane positive drift is unaffected (regression guard)', () {
      final c = LocalizationController(
        config: const LocalizationConfig(
          driftRateMetersPerSecond: 2,
          maxTrustworthyRadiusMeters: 100000,
          maxDeadReckoningSeconds: 100000,
        ),
      );
      c.onFix(fix(39.70, 140.10, acc: 6), trust: TrustSignal.trusted);
      final e = c.poll(t0.add(const Duration(seconds: 30)));
      expect(e.mode, LocalizationMode.deadReckoning); // sane drift → not forced lost
      expect(e.confidenceRadiusMeters, closeTo(6 + 2 * 30, 0.001));
    });
  });

  group('unanchored coarse guess (finding #9)', () {
    test('a suspect first fix plants the dot on the fix coords at huge radius',
        () {
      final c = LocalizationController(
        config: const LocalizationConfig(maxTrustworthyRadiusMeters: 500),
      );
      final e = c.onFix(fix(39.70, 140.10, acc: 5), trust: TrustSignal.suspect);
      expect(e.mode, LocalizationMode.lost);
      expect(e.basis, EstimateBasis.unanchoredGuess);
      // The coordinates come straight from the (untrusted) fix...
      expect(e.latitude, closeTo(39.70, 1e-9));
      expect(e.longitude, closeTo(140.10, 1e-9));
      // ...but only as a coarse guess at >= the trustworthy horizon.
      expect(e.confidenceRadiusMeters, greaterThanOrEqualTo(500));
      expect(e.isConfident, isFalse);
      expect(e.hasPosition, isTrue);
    });

    test('poll with nothing ever seen has no plottable position', () {
      final c = LocalizationController();
      final e = c.poll(t0);
      expect(e.hasPosition, isFalse); // lat/lon are NaN — integrators fail safe
      expect(e.mode, LocalizationMode.lost);
    });
  });
}
