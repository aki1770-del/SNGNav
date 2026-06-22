import 'dart:math' as math;

import 'package:position_integrity/position_integrity.dart';
import 'package:test/test.dart';

/// Metres per degree of latitude under the monitor's own earth radius
/// (R = 6_371_000 m), so a north-only offset is an EXACT metre distance.
final double _mPerLatDeg = 6371000 * math.pi / 180;

PositionFix _fix(
  double northMetres,
  DateTime t, {
  double accuracy = 5.0,
  double baseLat = 39.7, // Akita
  double baseLon = 140.1,
}) =>
    PositionFix(
      latitude: baseLat + northMetres / _mPerLatDeg,
      longitude: baseLon,
      accuracyMetres: accuracy,
      timestamp: t,
    );

void main() {
  final t0 = DateTime(2026, 1, 1, 7, 0, 0);
  DateTime at(double seconds) =>
      t0.add(Duration(milliseconds: (seconds * 1000).round()));

  test('first fix is trusted with nothing to compare against', () {
    final m = PositionIntegrityMonitor();
    final v = m.update(_fix(0, at(0)));
    expect(v.status, IntegrityStatus.trusted);
    expect(v.recommendedSource, SourceHint.gps);
    expect(v.gateResults, isEmpty);
    expect(v.hasViolation, isFalse);
  });

  test('smooth driving stays trusted', () {
    final m = PositionIntegrityMonitor();
    for (var i = 0; i < 6; i++) {
      final v = m.update(_fix(i * 20.0, at(i.toDouble()))); // 20 m/s north
      expect(v.status, IntegrityStatus.trusted,
          reason: 'fix $i should be clean: ${v.reason}');
      expect(v.recommendedSource, SourceHint.gps);
    }
  });

  test('a 200 m teleport at 1 Hz fails on impossible speed', () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    final v = m.update(_fix(200, at(1))); // 200 m in 1 s = 200 m/s
    expect(v.status, IntegrityStatus.failed);
    expect(v.gateResults[GateId.impossibleSpeed], isFalse);
    expect(v.violatedGates, contains(GateId.impossibleSpeed));
    expect(v.reason, contains('impossible speed'));
  });

  group('source handoff on a fault honours DR freshness', () {
    PositionIntegrityMonitor primed() {
      final m = PositionIntegrityMonitor();
      m.update(_fix(0, at(0)));
      return m;
    }

    test('no DR age known -> conservative hold', () {
      final v = primed().update(_fix(200, at(1)));
      expect(v.status, IntegrityStatus.failed);
      expect(v.recommendedSource, SourceHint.hold);
    });

    test('fresh DR -> recommend dead reckoning', () {
      final v = primed().update(_fix(200, at(1)),
          deadReckoningAge: const Duration(seconds: 5));
      expect(v.recommendedSource, SourceHint.deadReckoning);
    });

    test('DR age exactly at the max age is still fresh (boundary)', () {
      final v = primed().update(_fix(200, at(1)),
          deadReckoningAge: const Duration(seconds: 20));
      expect(v.recommendedSource, SourceHint.deadReckoning);
    });

    test('stale DR -> hold, never hand off to a degraded source', () {
      final v = primed().update(_fix(200, at(1)),
          deadReckoningAge: const Duration(seconds: 60));
      expect(v.recommendedSource, SourceHint.hold);
    });
  });

  test('a large jump in a sub-minSpeedDelta delta fails on the teleport gate',
      () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    // 40 m in 0.05 s — too brief to trust a computed speed; absolute jump gate.
    final v = m.update(_fix(40, at(0.05)));
    expect(v.status, IntegrityStatus.failed);
    expect(v.gateResults[GateId.teleport], isFalse);
    expect(v.gateResults.containsKey(GateId.impossibleSpeed), isFalse,
        reason: 'rate gates are not evaluated in the degenerate regime');
    expect(v.reason, contains('teleport'));
  });

  test('an impossible speed under teleport distance is still caught at >=0.1s',
      () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    // 29 m in 0.2 s = 145 m/s — under the 30 m teleport floor, but the delta is
    // long enough to compute a speed, so impossibleSpeed must catch it.
    final v = m.update(_fix(29, at(0.2)));
    expect(v.status, IntegrityStatus.failed);
    expect(v.gateResults[GateId.impossibleSpeed], isFalse);
  });

  test('impossible acceleration is suspect once, failed when sustained', () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0))); // init
    m.update(_fix(10, at(1))); // speed 10
    expect(m.update(_fix(20, at(2))).status, IntegrityStatus.trusted); // accel 0
    final s1 = m.update(_fix(50, at(3))); // speed 30, accel 20 -> suspect
    expect(s1.status, IntegrityStatus.suspect);
    expect(s1.gateResults[GateId.impossibleAccel], isFalse);
    final s2 = m.update(_fix(95, at(4))); // speed 45, accel 15 -> failed
    expect(s2.status, IntegrityStatus.failed);
    expect(s2.reason, contains('sustained'));
  });

  test('a legitimate fix after an impossible-speed fault is not flagged', () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    m.update(_fix(200, at(1))); // impossible speed -> failed
    // 20 m/s resumes; the accel baseline must not have been seeded with 200 m/s.
    final v = m.update(_fix(220, at(2)));
    expect(v.status, IntegrityStatus.trusted, reason: v.reason);
  });

  group('stationary jitter', () {
    // accuracy 2 m -> jitter threshold = max(5, 3*2) = 6 m.
    PositionIntegrityMonitor parkedWandering() {
      final m = PositionIntegrityMonitor();
      m.update(_fix(0, at(0), accuracy: 2)); // init
      m.update(_fix(0, at(1), accuracy: 2)); // speed 0
      m.update(_fix(8, at(2), accuracy: 2)); // 8 m step (accel 8, not > 8)
      return m;
    }

    test('is flagged suspect, not failed', () {
      // window [0,0,8,0] -> net ~0 (stationary) but an 8 m step.
      final v = parkedWandering().update(_fix(0, at(3), accuracy: 2));
      expect(v.status, IntegrityStatus.suspect);
      expect(v.gateResults[GateId.stationaryJitter], isFalse);
      expect(v.recommendedSource, SourceHint.gps);
    });

    test('never escalates to failed even when sustained', () {
      final m = PositionIntegrityMonitor();
      // Equal-magnitude 8 m steps that keep returning to origin: the window net
      // stays ~0 (stationary) while a step exceeds the 6 m jitter threshold,
      // and the constant 8 m/s speed never trips impossible acceleration. So
      // every settled fix is pure jitter — and jitter must never reach failed.
      const heights = [0, 8, 0, 0, 8, 0, 0, 8];
      IntegrityVerdict? last;
      for (var i = 0; i < heights.length; i++) {
        final v = m.update(_fix(heights[i].toDouble(), at(i.toDouble()),
            accuracy: 2));
        expect(v.status, isNot(IntegrityStatus.failed),
            reason: 'fix $i must not fail on jitter alone: ${v.reason}');
        last = v;
      }
      expect(last!.status, IntegrityStatus.suspect,
          reason: 'sustained jitter stays suspect: ${last.reason}');
      expect(last.recommendedSource, SourceHint.gps);
    });
  });

  test('a non-finite fix fails without poisoning later acceleration checks', () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    m.update(_fix(20, at(1))); // establish a clean 20 m/s baseline
    final bad = m.update(PositionFix(
      latitude: double.nan,
      longitude: 140.1,
      accuracyMetres: 5,
      timestamp: at(2),
    ));
    expect(bad.status, IntegrityStatus.failed);
    expect(bad.reason, contains('non-finite'));
    // The NaN must not have advanced state: a real impossible jump still fails.
    final v = m.update(_fix(400, at(3))); // 380 m in 1 s from the last GOOD fix
    expect(v.status, IntegrityStatus.failed);
  });

  test('an out-of-order or duplicate fix is suspect and does not corrupt state',
      () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    m.update(_fix(20, at(1))); // clean baseline at t=1, position 20 m
    // A fix stamped earlier (t=0.5) must be skipped, not adopted as baseline.
    final ooo = m.update(_fix(1000, at(0.5)));
    expect(ooo.status, IntegrityStatus.suspect);
    expect(ooo.reason, contains('out-of-order'));
    // The next in-order fix is still compared against the t=1 baseline (20 m),
    // so a smooth 20 m step is clean — the stale fix did not corrupt the state.
    final v = m.update(_fix(40, at(2)));
    expect(v.status, IntegrityStatus.trusted, reason: v.reason);
  });

  test('haversine handles east-west movement, not just north-south', () {
    final m = PositionIntegrityMonitor();
    // ~0.01 deg east at 39.7N is ~855 m; in 1 s that is ~855 m/s -> impossible.
    m.update(PositionFix(
        latitude: 39.7, longitude: 140.10, accuracyMetres: 5, timestamp: at(0)));
    final v = m.update(PositionFix(
        latitude: 39.7, longitude: 140.11, accuracyMetres: 5, timestamp: at(1)));
    expect(v.status, IntegrityStatus.failed,
        reason: 'a ~855 m east jump in 1 s must fail: ${v.reason}');
    expect(v.gateResults[GateId.impossibleSpeed], isFalse);
  });

  test('reset clears state so prior fixes cannot fault the next one', () {
    final m = PositionIntegrityMonitor();
    m.update(_fix(0, at(0)));
    m.update(_fix(20, at(1)));
    expect(m.isInitialized, isTrue);
    m.reset();
    expect(m.isInitialized, isFalse);
    // A jump that WOULD have failed against the pre-reset baseline is now the
    // first fix again -> trusted, proving the baseline was cleared.
    expect(m.update(_fix(100000, at(2))).status, IntegrityStatus.trusted);
  });
}
