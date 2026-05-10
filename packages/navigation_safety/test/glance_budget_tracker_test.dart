/// Tests for GlanceBudgetTracker (0.9.0).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:navigation_safety/navigation_safety.dart';

GlanceEvent _ev(int millis, {GlanceModalClass cls = GlanceModalClass.visual}) {
  return GlanceEvent(
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    duration: Duration(milliseconds: millis),
    modalClass: cls,
  );
}

void main() {
  group('GlanceBudgetTracker', () {
    test('default config: 12s total budget, 75% warning ratio', () {
      final tracker = GlanceBudgetTracker();
      expect(tracker.totalBudget, const Duration(seconds: 12));
      expect(tracker.consumed, Duration.zero);
      expect(tracker.remainingBudget, const Duration(seconds: 12));
      tracker.dispose();
    });

    test('record() adds to consumed budget', () {
      final tracker = GlanceBudgetTracker();
      tracker.record(_ev(2000));
      expect(tracker.consumed, const Duration(seconds: 2));
      expect(tracker.remainingBudget, const Duration(seconds: 10));
      tracker.dispose();
    });

    test('BudgetWarning fires once at 75% consumed (default ratio)', () async {
      final tracker = GlanceBudgetTracker();
      final events = <GlanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      // 0/12 -> 6/12 (50%; no fire) -> 9/12 (75%; warning fires).
      tracker.record(_ev(6000));
      tracker.record(_ev(3000));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<BudgetWarning>().length, 1);
      expect(events.whereType<BudgetExhausted>().length, 0);
      final warning = events.whereType<BudgetWarning>().first;
      expect(warning.consumed, const Duration(seconds: 9));
      expect(warning.remaining, const Duration(seconds: 3));
      await tracker.dispose();
    });

    test('BudgetExhausted fires once at 100% consumed', () async {
      final tracker = GlanceBudgetTracker();
      final events = <GlanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ev(12000));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<BudgetWarning>().length, 1);
      expect(events.whereType<BudgetExhausted>().length, 1);
      final exhausted = events.whereType<BudgetExhausted>().first;
      expect(exhausted.consumed, const Duration(seconds: 12));
      expect(exhausted.overshoot, Duration.zero);
      expect(tracker.remainingBudget, Duration.zero);
      await tracker.dispose();
    });

    test('remainingBudget clamps to zero on overshoot; '
        'BudgetExhausted overshoot is positive', () async {
      final tracker = GlanceBudgetTracker();
      final events = <GlanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ev(15000));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(tracker.remainingBudget, Duration.zero);
      final exhausted = events.whereType<BudgetExhausted>().single;
      expect(exhausted.overshoot, const Duration(seconds: 3));
      await tracker.dispose();
    });

    test('reset() clears consumption and warning/exhausted flags', () async {
      final tracker = GlanceBudgetTracker();
      final events = <GlanceBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ev(12000));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.length, 2);

      tracker.reset(BudgetResetReason.tripStart);
      expect(tracker.consumed, Duration.zero);
      expect(tracker.remainingBudget, const Duration(seconds: 12));

      // After reset a fresh cycle can fire warning + exhausted again.
      tracker.record(_ev(12000));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<BudgetWarning>().length, 2);
      expect(events.whereType<BudgetExhausted>().length, 2);
      await tracker.dispose();
    });

    test('dispose() is idempotent', () async {
      final tracker = GlanceBudgetTracker();
      await tracker.dispose();
      await tracker.dispose();
      // Recording after dispose is no-op (does not throw).
      tracker.record(_ev(1000));
    });

    test('caution-add-only: negative-duration GlanceEvent fails assert '
        '(debug-mode)', () {
      final tracker = GlanceBudgetTracker();
      expect(
        () => tracker.record(
          GlanceEvent(
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            duration: const Duration(milliseconds: -1),
            modalClass: GlanceModalClass.visual,
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
      tracker.dispose();
    });

    test('NHTSAGlanceBudgetConfig.warningRatio out of range fails assert', () {
      expect(
        () => NHTSAGlanceBudgetConfig(warningRatio: 0.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => NHTSAGlanceBudgetConfig(warningRatio: 1.0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
