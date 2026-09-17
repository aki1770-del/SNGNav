// After the budget is exhausted, later glances emit no event,
// and the exhausted state stays readable (remainingBudget is zero) until the
// integrator resets; after a reset the next exhaustion is reported again.
// Advisory presentation only; the tracker controls nothing.
import 'package:navigation_safety/src/glance_budget_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

GlanceEvent g(int s) => GlanceEvent(
      timestamp: DateTime.utc(2026, 1, 1),
      duration: Duration(seconds: s),
      modalClass: GlanceModalClass.visual,
    );

void main() {
  test('exhaustion is a latched state, and a reset re-arms it',
      () async {
    final tracker = GlanceBudgetTracker();
    final events = <GlanceBudgetEvent>[];
    final sub = tracker.budgetEvents.listen(events.add);
    tracker.record(g(13));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<BudgetExhausted>().length, 1);
    tracker.record(g(30));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<BudgetExhausted>().length, 1);
    expect(tracker.remainingBudget, Duration.zero,
        reason: 'the silence is a latch, not a lost state');
    tracker.reset(BudgetResetReason.tripStart);
    expect(tracker.remainingBudget, const Duration(seconds: 12));
    tracker.record(g(13));
    await Future<void>.delayed(Duration.zero);
    expect(events.whereType<BudgetExhausted>().length, 2,
        reason: 'a reset must re-arm the exhaustion event');
    expect(events.whereType<BudgetWarning>().length, 2);
    await sub.cancel();
    await tracker.dispose();
  });
}
