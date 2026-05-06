/// Tests for PerformanceBudget (0.5.0).
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:offline_tiles/offline_tiles.dart';

/// Build a synthetic FrameTiming with the given total span.
///
/// Mirrors the FrameTiming constructor signature used in flutter_test:
/// `FrameTiming(timestamps: [...])`. The first timestamp is
/// vsyncStart; the last is rasterFinish; totalSpan = last - first.
FrameTiming _ft(int totalMicros) {
  // FrameTiming.timestamps order: vsyncStart, buildStart, buildFinish,
  // rasterStart, rasterFinish, rasterFinishWallTime, frameRequestNumber,
  // (vsyncOverhead). We only need totalSpan = last (rasterFinish or
  // rasterFinishWallTime) - first (vsyncStart). Pass equal spacing.
  return FrameTiming(
    vsyncStart: 0,
    buildStart: 0,
    buildFinish: totalMicros ~/ 2,
    rasterStart: totalMicros ~/ 2,
    rasterFinish: totalMicros,
    rasterFinishWallTime: totalMicros,
    frameNumber: 1,
  );
}

void main() {
  group('PerformanceBudgetConfig', () {
    test('default config: 16ms baseline budget, 0.75 warning ratio', () {
      const config = PerformanceBudgetConfig();
      expect(config.frameBudget,
          PerformanceBudgetConfig.baselineFrameBudget);
      expect(config.warningRatio, 0.75);
      expect(config.sustainedFrames, 5);
    });

    test('forProfile: experienced cohorts get baseline 16ms', () {
      for (final p in [
        DriverProfile.professional,
        DriverProfile.snowZoneExperienced,
        DriverProfile.agriculturalForestry,
      ]) {
        final config = PerformanceBudgetConfig.forProfile(p);
        expect(config.frameBudget,
            PerformanceBudgetConfig.baselineFrameBudget,
            reason: 'cohort $p should get baseline');
      }
    });

    test(
        'forProfile: visual-cognitive-margin cohorts get LARGER (more lenient) '
        'budget than baseline', () {
      final novice = PerformanceBudgetConfig.forProfile(
          DriverProfile.noviceUrban);
      final ageing = PerformanceBudgetConfig.forProfile(
          DriverProfile.ageingRural);
      final tourist = PerformanceBudgetConfig.forProfile(
          DriverProfile.foreignTouristSnowZone);

      expect(novice.frameBudget.inMicroseconds, 18000);
      expect(ageing.frameBudget.inMicroseconds, 22000);
      expect(tourist.frameBudget.inMicroseconds, 22000);

      // Caution-add-only: every cohort >= baseline.
      for (final c in [novice, ageing, tourist]) {
        expect(
          c.frameBudget.inMicroseconds >=
              PerformanceBudgetConfig.baselineFrameBudget.inMicroseconds,
          isTrue,
          reason: 'caution-add-only invariant: cohort budget >= baseline',
        );
      }
    });

    test('warningRatio out of range fails assert', () {
      expect(() => PerformanceBudgetConfig(warningRatio: 0.0),
          throwsA(isA<AssertionError>()));
      expect(() => PerformanceBudgetConfig(warningRatio: 1.0),
          throwsA(isA<AssertionError>()));
    });

    test('sustainedFrames < 1 fails assert', () {
      expect(() => PerformanceBudgetConfig(sustainedFrames: 0),
          throwsA(isA<AssertionError>()));
    });
  });

  group('PerformanceBudget', () {
    test('record() updates lastFrameTotal and snapshot', () {
      final tracker = PerformanceBudget();
      tracker.record(_ft(8000)); // 8ms
      expect(tracker.lastFrameTotal.inMicroseconds, 8000);
      final snap = tracker.budgetSnapshot;
      expect(snap.consumed.inMicroseconds, 8000);
      expect(snap.remaining.inMicroseconds, 16667 - 8000);
      tracker.dispose();
    });

    test('BudgetWarning fires once at 75% of frame budget', () async {
      final tracker = PerformanceBudget();
      final events = <PerformanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      // 75% of 16.667ms baseline = 12500.25us; record 12501us to clear
      // the >= warningRatio threshold without breaching 100%.
      tracker.record(_ft(12501));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<BudgetWarning>().length, 1);
      expect(events.whereType<BudgetExhausted>().length, 0);
      await tracker.dispose();
    });

    test(
        'BudgetExhausted fires only after sustainedFrames consecutive '
        'over-budget frames', () async {
      final tracker = PerformanceBudget(
        config: const PerformanceBudgetConfig(sustainedFrames: 3),
      );
      final events = <PerformanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      // 2 over-budget frames → exhausted does NOT fire yet.
      tracker.record(_ft(20000)); // over budget
      tracker.record(_ft(20000)); // over budget
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<BudgetExhausted>().length, 0);

      // 3rd consecutive over-budget frame → exhausted fires.
      tracker.record(_ft(20000));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<BudgetExhausted>().length, 1);
      await tracker.dispose();
    });

    test('non-over-budget frame resets the consecutive-over-budget counter',
        () async {
      final tracker = PerformanceBudget(
        config: const PerformanceBudgetConfig(sustainedFrames: 3),
      );
      final events = <PerformanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      // Two over-budget frames, one under, two over → exhausted does NOT
      // fire (counter reset by the under-budget frame).
      tracker.record(_ft(20000));
      tracker.record(_ft(20000));
      tracker.record(_ft(10000)); // under budget; counter reset
      tracker.record(_ft(20000));
      tracker.record(_ft(20000));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<BudgetExhausted>().length, 0);
      await tracker.dispose();
    });

    test('reset() clears warning + exhausted fired-once flags', () async {
      final tracker = PerformanceBudget(
        config: const PerformanceBudgetConfig(sustainedFrames: 1),
      );
      final events = <PerformanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ft(20000));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.length, 2); // warning + exhausted

      tracker.reset(BudgetResetReason.renderCycleStart);

      // Fresh cycle: warning + exhausted fire again.
      tracker.record(_ft(20000));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<BudgetWarning>().length, 2);
      expect(events.whereType<BudgetExhausted>().length, 2);
      await tracker.dispose();
    });

    test('dispose() is idempotent', () async {
      final tracker = PerformanceBudget();
      await tracker.dispose();
      await tracker.dispose();
      // Recording after dispose is no-op.
      tracker.record(_ft(1000));
    });
  });
}
