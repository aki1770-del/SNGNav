/// Tests for DataBudget (0.2.0).
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:snow_rendering/snow_rendering.dart';
import 'package:test/test.dart';

DataFetchEvent _ev(int bytes) {
  return DataFetchEvent(
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    bytesFetched: bytes,
  );
}

void main() {
  group('DataBudgetConfig', () {
    test('default config: 4MB baseline budget, 0.75 warning ratio', () {
      const config = DataBudgetConfig();
      expect(config.budgetBytes, DataBudgetConfig.baselineBudgetBytes);
      expect(config.warningRatio, 0.75);
    });

    test('forProfile: experienced cohorts get baseline 4MB', () {
      for (final p in [
        DriverProfile.professional,
        DriverProfile.snowZoneExperienced,
        DriverProfile.agriculturalForestry,
      ]) {
        final config = DataBudgetConfig.forProfile(p);
        expect(
          config.budgetBytes,
          DataBudgetConfig.baselineBudgetBytes,
          reason: 'cohort $p should get baseline',
        );
      }
    });

    test('forProfile: bandwidth-margin cohorts get SMALLER (tighter) '
        'budget than baseline', () {
      final novice = DataBudgetConfig.forProfile(DriverProfile.noviceUrban);
      final ageing = DataBudgetConfig.forProfile(DriverProfile.ageingRural);
      final tourist = DataBudgetConfig.forProfile(
        DriverProfile.foreignTouristSnowZone,
      );

      expect(novice.budgetBytes, 3 * 1024 * 1024);
      expect(ageing.budgetBytes, 2 * 1024 * 1024);
      expect(tourist.budgetBytes, 2 * 1024 * 1024);

      // Caution-add-only: every cohort <= baseline (= less data = more
      // caution toward fidelity-drop).
      for (final c in [novice, ageing, tourist]) {
        expect(
          c.budgetBytes <= DataBudgetConfig.baselineBudgetBytes,
          isTrue,
          reason: 'caution-add-only invariant: cohort budget <= baseline',
        );
      }
    });

    test('budgetBytes <= 0 fails assert', () {
      expect(
        () => DataBudgetConfig(budgetBytes: 0),
        throwsA(isA<AssertionError>()),
      );
    });

    test('warningRatio out of range fails assert', () {
      expect(
        () => DataBudgetConfig(warningRatio: 0.0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => DataBudgetConfig(warningRatio: 1.0),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('DataBudget', () {
    test('record() adds to consumed bytes', () {
      final tracker = DataBudget();
      tracker.record(_ev(1024 * 1024)); // 1MB
      expect(tracker.consumedBytes, 1024 * 1024);
      expect(
        tracker.remainingBytes,
        DataBudgetConfig.baselineBudgetBytes - 1024 * 1024,
      );
      tracker.dispose();
    });

    test('BudgetWarning fires once at 75% consumed', () async {
      final tracker = DataBudget();
      final events = <DataBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      // 75% of 4MB = 3MB; record exactly that.
      tracker.record(_ev(3 * 1024 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<BudgetWarning>().length, 1);
      expect(events.whereType<BudgetExhausted>().length, 0);
      await tracker.dispose();
    });

    test('BudgetExhausted + RenderFidelityDrop fire (in lock-step) at 100% '
        'consumed', () async {
      final tracker = DataBudget();
      final events = <DataBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ev(4 * 1024 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(events.whereType<BudgetWarning>().length, 1);
      expect(events.whereType<BudgetExhausted>().length, 1);
      expect(events.whereType<RenderFidelityDrop>().length, 1);
      await tracker.dispose();
    });

    test('overshoot is reported on BudgetExhausted', () async {
      final tracker = DataBudget();
      final events = <DataBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ev(5 * 1024 * 1024)); // 1MB over budget
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final exhausted = events.whereType<BudgetExhausted>().single;
      expect(exhausted.overshootBytes, 1024 * 1024);
      expect(tracker.remainingBytes, 0);
      await tracker.dispose();
    });

    test('reset() clears consumption + fired-once flags', () async {
      final tracker = DataBudget();
      final events = <DataBudgetEvent>[];
      tracker.budgetEvents.listen(events.add);

      tracker.record(_ev(4 * 1024 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.length, 3); // warning + exhausted + fidelity-drop

      tracker.reset(BudgetResetReason.renderCycleStart);
      expect(tracker.consumedBytes, 0);

      // Fresh cycle.
      tracker.record(_ev(4 * 1024 * 1024));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(events.whereType<BudgetWarning>().length, 2);
      expect(events.whereType<BudgetExhausted>().length, 2);
      await tracker.dispose();
    });

    test('tighten() accepts smaller budget; rejects larger via assert', () {
      final tracker = DataBudget(
        config: const DataBudgetConfig(budgetBytes: 4 * 1024 * 1024),
      );

      // Smaller is fine (caution-add direction).
      tracker.tighten(2 * 1024 * 1024);
      expect(tracker.config.budgetBytes, 2 * 1024 * 1024);

      // Larger is rejected (would relax).
      expect(
        () => tracker.tighten(8 * 1024 * 1024),
        throwsA(isA<AssertionError>()),
      );

      tracker.dispose();
    });

    test('relax() requires affirmative confirmation', () {
      final tracker = DataBudget(
        config: const DataBudgetConfig(budgetBytes: 2 * 1024 * 1024),
      );

      // isConfirmed: false rejected.
      final unconfirmed = BudgetRelaxConfirmation(
        reason: 'network improved',
        confirmedAt: DateTime(0),
        isConfirmed: false,
      );
      expect(
        () => tracker.relax(4 * 1024 * 1024, unconfirmed),
        throwsA(isA<AssertionError>()),
      );

      // empty reason rejected.
      final blankReason = BudgetRelaxConfirmation(
        reason: '',
        confirmedAt: DateTime(0),
        isConfirmed: true,
      );
      expect(
        () => tracker.relax(4 * 1024 * 1024, blankReason),
        throwsA(isA<AssertionError>()),
      );

      // affirmative + non-empty accepted.
      final ok = BudgetRelaxConfirmation(
        reason: 'user requested high-fidelity',
        confirmedAt: DateTime(0),
        isConfirmed: true,
      );
      tracker.relax(4 * 1024 * 1024, ok);
      expect(tracker.config.budgetBytes, 4 * 1024 * 1024);

      tracker.dispose();
    });

    test('caution-add-only: negative-bytes DataFetchEvent fails assert', () {
      final tracker = DataBudget();
      expect(
        () => tracker.record(
          DataFetchEvent(
            timestamp: DateTime.fromMillisecondsSinceEpoch(0),
            bytesFetched: -1,
          ),
        ),
        throwsA(isA<AssertionError>()),
      );
      tracker.dispose();
    });

    test('dispose() is idempotent', () async {
      final tracker = DataBudget();
      await tracker.dispose();
      await tracker.dispose();
      tracker.record(_ev(100));
    });
  });
}
