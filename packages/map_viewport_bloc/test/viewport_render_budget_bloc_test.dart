/// Tests for ViewportRenderBudgetBloc (0.4.0).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';

/// Synthetic event types whose runtime-type names match the upstream
/// names ('BudgetWarning' / 'BudgetExhausted'). The bloc inspects
/// runtime-type via `runtimeType.toString()` so we can drive it from
/// test-class events without importing offline_tiles or snow_rendering.
class BudgetWarning {
  const BudgetWarning();
}

class BudgetExhausted {
  const BudgetExhausted();
}

void main() {
  group('ViewportRenderConfig', () {
    test('default config: LOW floor', () {
      const config = ViewportRenderConfig();
      expect(config.floor, RenderFidelityFloor.low);
    });

    test('forProfile: experienced cohorts get LOW floor; visual-cognitive-'
        'margin cohorts get MEDIUM floor', () {
      for (final p in [
        DriverProfile.professional,
        DriverProfile.snowZoneExperienced,
        DriverProfile.agriculturalForestry,
      ]) {
        final config = ViewportRenderConfig.forProfile(p);
        expect(
          config.floor,
          RenderFidelityFloor.low,
          reason: 'cohort $p should get LOW floor',
        );
      }
      for (final p in [
        DriverProfile.noviceUrban,
        DriverProfile.ageingRural,
        DriverProfile.foreignTouristSnowZone,
      ]) {
        final config = ViewportRenderConfig.forProfile(p);
        expect(
          config.floor,
          RenderFidelityFloor.medium,
          reason: 'cohort $p should get MEDIUM floor',
        );
      }
    });
  });

  group('ViewportRenderBudgetBloc', () {
    test('initial state: HIGH fidelity, no warnings observed', () {
      final bloc = ViewportRenderBudgetBloc();
      expect(bloc.state.fidelity, RenderFidelity.high);
      expect(bloc.state.performanceWarningSeen, isFalse);
      expect(bloc.state.dataExhaustedSeen, isFalse);
      bloc.close();
    });

    test('PerformanceBudget Warning → MEDIUM fidelity', () async {
      final bloc = ViewportRenderBudgetBloc();
      bloc.add(const ViewportPerformanceBudgetWarning());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.medium);
      expect(bloc.state.performanceWarningSeen, isTrue);
      await bloc.close();
    });

    test('DataBudget Warning → MEDIUM fidelity', () async {
      final bloc = ViewportRenderBudgetBloc();
      bloc.add(const ViewportDataBudgetWarning());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.medium);
      expect(bloc.state.dataWarningSeen, isTrue);
      await bloc.close();
    });

    test(
      'PerformanceBudget Exhausted → LOW fidelity (LOW floor cohort)',
      () async {
        final bloc = ViewportRenderBudgetBloc(); // LOW floor default
        bloc.add(const ViewportPerformanceBudgetExhausted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.fidelity, RenderFidelity.low);
        await bloc.close();
      },
    );

    test('caution-add-direction-wins: PerformanceBudget Exhausted + '
        'DataBudget Warning → LOW (Exhausted wins)', () async {
      final bloc = ViewportRenderBudgetBloc();
      bloc.add(const ViewportDataBudgetWarning());
      bloc.add(const ViewportPerformanceBudgetExhausted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.low);
      await bloc.close();
    });

    test('per-cohort floor: ageingRural cohort never drops to LOW even when '
        'both budgets exhaust', () async {
      final bloc = ViewportRenderBudgetBloc(
        config: ViewportRenderConfig.forProfile(DriverProfile.ageingRural),
      );
      bloc.add(const ViewportPerformanceBudgetExhausted());
      bloc.add(const ViewportDataBudgetExhausted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // Without floor, fidelity would be LOW. With MEDIUM floor:
      expect(bloc.state.fidelity, RenderFidelity.medium);
      expect(bloc.state.performanceExhaustedSeen, isTrue);
      expect(bloc.state.dataExhaustedSeen, isTrue);
      await bloc.close();
    });

    test('reset event returns fidelity to HIGH and clears flags', () async {
      final bloc = ViewportRenderBudgetBloc();
      bloc.add(const ViewportPerformanceBudgetExhausted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.low);

      bloc.add(const ViewportBudgetReset());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.high);
      expect(bloc.state.performanceExhaustedSeen, isFalse);
      await bloc.close();
    });

    test(
      'attachPerformanceBudgetStream: dispatches on upstream events',
      () async {
        final bloc = ViewportRenderBudgetBloc();
        final controller = StreamController<Object>.broadcast();
        bloc.attachPerformanceBudgetStream(controller.stream);

        controller.add(const BudgetWarning());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.fidelity, RenderFidelity.medium);

        controller.add(const BudgetExhausted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(bloc.state.fidelity, RenderFidelity.low);

        await controller.close();
        await bloc.close();
      },
    );

    test('attachDataBudgetStream: dispatches on upstream events', () async {
      final bloc = ViewportRenderBudgetBloc();
      final controller = StreamController<Object>.broadcast();
      bloc.attachDataBudgetStream(controller.stream);

      controller.add(const BudgetWarning());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.medium);
      expect(bloc.state.dataWarningSeen, isTrue);

      await controller.close();
      await bloc.close();
    });

    test('auto-relax-forbidden: bloc never raises fidelity in response to '
        'a stream event (only reset does)', () async {
      final bloc = ViewportRenderBudgetBloc();
      bloc.add(const ViewportDataBudgetExhausted());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(bloc.state.fidelity, RenderFidelity.low);

      // No upstream event should ever raise fidelity above the
      // current state. Sending a Warning AFTER an Exhausted does not
      // raise fidelity.
      bloc.add(const ViewportPerformanceBudgetWarning());
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(
        bloc.state.fidelity,
        RenderFidelity.low,
        reason: 'auto-relax forbidden: Exhausted-state persists',
      );
      await bloc.close();
    });
  });
}
