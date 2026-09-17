// Characterization, not a behaviour change: the tracker pools every glance
// since the last reset into one 12 s budget, and each event class fires at
// most once per cycle. NHTSA's 12 s is a per-task completion criterion
// (78 FR 24818). If reset is called only at trip boundaries, the budget is
// a per-trip budget, and after the first exhaustion later glances in that
// trip emit nothing.
import 'package:navigation_safety/src/glance_budget_tracker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('three 5 s tasks in one trip: one warning, one exhaustion, then silence',
      () async {
    final tracker = GlanceBudgetTracker();
    final events = <GlanceBudgetEvent>[];
    final sub = tracker.budgetEvents.listen(events.add);
    final t0 = DateTime.utc(2026, 1, 1);
    for (var task = 0; task < 3; task++) {
      tracker.record(GlanceEvent(
        timestamp: t0.add(Duration(minutes: task * 10)),
        duration: const Duration(seconds: 5),
        modalClass: GlanceModalClass.visual,
      ));
      await Future<void>.delayed(Duration.zero);
    }
    // Each task alone (5 s) is inside NHTSA's per-task 12 s.
    expect(events.whereType<BudgetWarning>().length, 1);
    expect(events.whereType<BudgetExhausted>().length, 1);
    final countAfterThirdTask = events.length;
    tracker.record(GlanceEvent(
      timestamp: t0.add(const Duration(minutes: 40)),
      duration: const Duration(seconds: 30),
      modalClass: GlanceModalClass.visual,
    ));
    await Future<void>.delayed(Duration.zero);
    expect(events.length, countAfterThirdTask,
        reason: 'a 30 s glance after exhaustion emits nothing');
    await sub.cancel();
    await tracker.dispose();
  });
}
