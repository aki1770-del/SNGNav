/// Tests for FleetReport, FleetProvider, FleetEvent, FleetState, and FleetBloc.
///
/// Coverage:
///   - FleetReport model: enums, hazard detection, recency, equality
///   - FleetState: convenience getters, hazard aggregation
///   - FleetEvent: equality
///   - FleetBloc: start, stop, report reception, stale pruning, error handling
///
/// Architecture reference: A63 v3.0 §4.8 (fleet consent gate).
/// Sprint 8 Day 4.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/bloc/fleet_bloc.dart';
import 'package:sngnav_snow_scene/bloc/fleet_event.dart';
import 'package:sngnav_snow_scene/bloc/fleet_state.dart';
import 'package:sngnav_snow_scene/models/fleet_report.dart';
import 'package:sngnav_snow_scene/providers/fleet_provider.dart';

// ---------------------------------------------------------------------------
// Mock FleetProvider
// ---------------------------------------------------------------------------

class _MockFleetProvider implements FleetProvider {
  final _controller = StreamController<FleetReport>.broadcast();
  bool started = false;

  @override
  Stream<FleetReport> get reports => _controller.stream;

  @override
  Future<void> startListening() async {
    started = true;
  }

  @override
  Future<void> stopListening() async {
    started = false;
  }

  @override
  void dispose() {
    _controller.close();
  }

  void emitReport(FleetReport report) {
    _controller.add(report);
  }

  void emitError(String message) {
    _controller.addError(Exception(message));
  }
}

class _FailingFleetProvider implements FleetProvider {
  @override
  Stream<FleetReport> get reports => const Stream.empty();

  @override
  Future<void> startListening() async {
    throw Exception('Fleet connection failed');
  }

  @override
  Future<void> stopListening() async {}

  @override
  void dispose() {}
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

FleetReport _report({
  String id = 'V-001',
  double lat = 35.170,
  double lon = 136.882,
  RoadCondition condition = RoadCondition.dry,
  double confidence = 0.9,
  DateTime? timestamp,
}) {
  return FleetReport(
    vehicleId: id,
    position: LatLng(lat, lon),
    timestamp: timestamp ?? DateTime.now(),
    condition: condition,
    confidence: confidence,
  );
}

void main() {
  // -------------------------------------------------------------------------
  // FleetReport model
  // -------------------------------------------------------------------------

  group('FleetReport', () {
    test('dry report is not a hazard', () {
      final report = _report(condition: RoadCondition.dry);
      expect(report.isHazard, false);
    });

    test('wet report is not a hazard', () {
      final report = _report(condition: RoadCondition.wet);
      expect(report.isHazard, false);
    });

    test('snowy report is a hazard', () {
      final report = _report(condition: RoadCondition.snowy);
      expect(report.isHazard, true);
    });

    test('icy report is a hazard', () {
      final report = _report(condition: RoadCondition.icy);
      expect(report.isHazard, true);
    });

    test('unknown report is not a hazard', () {
      final report = _report(condition: RoadCondition.unknown);
      expect(report.isHazard, false);
    });

    test('recent report is recent', () {
      final report = _report(timestamp: DateTime.now());
      expect(report.isRecent(), true);
    });

    test('old report is not recent', () {
      final report = _report(
        timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
      );
      expect(report.isRecent(), false);
    });

    test('equality by value', () {
      final timestamp = DateTime(2026, 2, 27, 12, 0);
      final a = FleetReport(
        vehicleId: 'V-001',
        position: const LatLng(35.170, 136.882),
        timestamp: timestamp,
        condition: RoadCondition.snowy,
        confidence: 0.9,
      );
      final b = FleetReport(
        vehicleId: 'V-001',
        position: const LatLng(35.170, 136.882),
        timestamp: timestamp,
        condition: RoadCondition.snowy,
        confidence: 0.9,
      );
      expect(a, equals(b));
    });

    test('different condition ≠ equal', () {
      final timestamp = DateTime(2026, 2, 27);
      final dry = _report(condition: RoadCondition.dry, timestamp: timestamp);
      final icy = _report(condition: RoadCondition.icy, timestamp: timestamp);
      expect(dry, isNot(equals(icy)));
    });

    test('all RoadCondition values exist', () {
      expect(RoadCondition.values, hasLength(5));
    });

    test('toString includes vehicleId and condition', () {
      final report = _report(condition: RoadCondition.snowy);
      expect(report.toString(), contains('V-001'));
      expect(report.toString(), contains('snowy'));
    });
  });

  // -------------------------------------------------------------------------
  // FleetState
  // -------------------------------------------------------------------------

  group('FleetState', () {
    test('idle state has no reports', () {
      const state = FleetState.idle();
      expect(state.status, FleetStatus.idle);
      expect(state.activeReports, isEmpty);
      expect(state.isListening, false);
      expect(state.hasHazards, false);
    });

    test('listening state with reports', () {
      final report = _report(condition: RoadCondition.snowy);
      final state = FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-001': report},
      );
      expect(state.isListening, true);
      expect(state.vehicleCount, 1);
      expect(state.hasHazards, true);
      expect(state.hazardReports, hasLength(1));
    });

    test('hazardReports filters non-hazard reports', () {
      final state = FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _report(id: 'V-001', condition: RoadCondition.dry),
          'V-002': _report(id: 'V-002', condition: RoadCondition.snowy),
          'V-003': _report(id: 'V-003', condition: RoadCondition.icy),
        },
      );
      expect(state.hazardReports, hasLength(2));
      expect(state.vehicleCount, 3);
    });

    test('toString includes vehicle count and hazard count', () {
      final state = FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _report(condition: RoadCondition.icy),
        },
      );
      expect(state.toString(), contains('1 vehicles'));
      expect(state.toString(), contains('1 hazards'));
    });
  });

  // -------------------------------------------------------------------------
  // FleetEvent
  // -------------------------------------------------------------------------

  group('FleetEvent', () {
    test('FleetListenStarted equality', () {
      expect(
        const FleetListenStarted(),
        equals(const FleetListenStarted()),
      );
    });

    test('FleetListenStopped equality', () {
      expect(
        const FleetListenStopped(),
        equals(const FleetListenStopped()),
      );
    });

    test('FleetReportReceived equality', () {
      final timestamp = DateTime(2026, 2, 27);
      final report = _report(timestamp: timestamp);
      expect(
        FleetReportReceived(report),
        equals(FleetReportReceived(report)),
      );
    });

    test('FleetErrorOccurred equality', () {
      expect(
        const FleetErrorOccurred('fail'),
        equals(const FleetErrorOccurred('fail')),
      );
    });
  });

  // -------------------------------------------------------------------------
  // FleetBloc
  // -------------------------------------------------------------------------

  group('FleetBloc', () {
    late _MockFleetProvider provider;
    late FleetBloc bloc;

    setUp(() {
      provider = _MockFleetProvider();
      bloc = FleetBloc(provider: provider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('initial state is idle', () {
      expect(bloc.state.status, FleetStatus.idle);
      expect(bloc.state.activeReports, isEmpty);
    });

    blocTest<FleetBloc, FleetState>(
      'start emits listening',
      build: () => FleetBloc(provider: _MockFleetProvider()),
      act: (bloc) => bloc.add(const FleetListenStarted()),
      expect: () => [
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'stop after start emits idle',
      build: () => FleetBloc(provider: _MockFleetProvider()),
      act: (bloc) async {
        bloc.add(const FleetListenStarted());
        await Future<void>.delayed(const Duration(milliseconds: 30));
        bloc.add(const FleetListenStopped());
      },
      expect: () => [
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.idle)
            .having((s) => s.activeReports, 'reports', isEmpty),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'report received updates active reports',
      build: () {
        final p = _MockFleetProvider();
        final b = FleetBloc(provider: p);
        // Schedule report emission after start.
        Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
          p.emitReport(_report(condition: RoadCondition.snowy));
        });
        return b;
      },
      act: (bloc) async {
        bloc.add(const FleetListenStarted());
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [
        // listening (on start)
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
        // listening with report
        isA<FleetState>()
            .having((s) => s.vehicleCount, 'vehicles', 1)
            .having((s) => s.hasHazards, 'hazards', true),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'multiple vehicles tracked independently',
      build: () {
        final p = _MockFleetProvider();
        final b = FleetBloc(provider: p);
        Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
          p.emitReport(_report(id: 'V-001', condition: RoadCondition.dry));
        });
        Future<void>.delayed(const Duration(milliseconds: 80)).then((_) {
          p.emitReport(_report(id: 'V-002', condition: RoadCondition.icy));
        });
        return b;
      },
      act: (bloc) async {
        bloc.add(const FleetListenStarted());
        await Future<void>.delayed(const Duration(milliseconds: 150));
      },
      expect: () => [
        // listening
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
        // V-001 received
        isA<FleetState>()
            .having((s) => s.vehicleCount, 'vehicles', 1)
            .having((s) => s.hasHazards, 'hazards', false),
        // V-002 received
        isA<FleetState>()
            .having((s) => s.vehicleCount, 'vehicles', 2)
            .having((s) => s.hasHazards, 'hazards', true),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'upsert: new report from same vehicle replaces old',
      build: () {
        final p = _MockFleetProvider();
        final b = FleetBloc(provider: p);
        Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
          p.emitReport(_report(condition: RoadCondition.dry));
        });
        Future<void>.delayed(const Duration(milliseconds: 80)).then((_) {
          p.emitReport(_report(condition: RoadCondition.icy));
        });
        return b;
      },
      act: (bloc) async {
        bloc.add(const FleetListenStarted());
        await Future<void>.delayed(const Duration(milliseconds: 150));
      },
      expect: () => [
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
        // V-001 dry
        isA<FleetState>()
            .having((s) => s.vehicleCount, 'vehicles', 1)
            .having((s) => s.hasHazards, 'hazards', false),
        // V-001 updated to icy (still 1 vehicle, now hazard)
        isA<FleetState>()
            .having((s) => s.vehicleCount, 'vehicles', 1)
            .having((s) => s.hasHazards, 'hazards', true),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'stale reports are pruned',
      build: () {
        final p = _MockFleetProvider();
        final b = FleetBloc(provider: p);
        Future<void>.delayed(const Duration(milliseconds: 50)).then((_) {
          // Old report — 20 minutes ago.
          // Pruning happens on insertion, so V-OLD is pruned immediately.
          // The emitted state (0 vehicles, listening) equals the prior
          // listening state — bloc_test deduplicates it.
          p.emitReport(_report(
            id: 'V-OLD',
            condition: RoadCondition.icy,
            timestamp: DateTime.now().subtract(const Duration(minutes: 20)),
          ));
        });
        Future<void>.delayed(const Duration(milliseconds: 80)).then((_) {
          // Fresh report — survives pruning.
          p.emitReport(_report(id: 'V-NEW', condition: RoadCondition.dry));
        });
        return b;
      },
      act: (bloc) async {
        bloc.add(const FleetListenStarted());
        await Future<void>.delayed(const Duration(milliseconds: 150));
      },
      expect: () => [
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
        // V-OLD was pruned on insertion (stale). V-NEW is fresh — only V-NEW present.
        isA<FleetState>()
            .having((s) => s.vehicleCount, 'vehicles', 1)
            .having(
              (s) => s.activeReports.containsKey('V-OLD'),
              'V-OLD pruned',
              false,
            )
            .having(
              (s) => s.activeReports.containsKey('V-NEW'),
              'V-NEW present',
              true,
            ),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'error on start emits error state',
      build: () => FleetBloc(provider: _FailingFleetProvider()),
      act: (bloc) => bloc.add(const FleetListenStarted()),
      expect: () => [
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.listening),
        isA<FleetState>()
            .having((s) => s.status, 'status', FleetStatus.error)
            .having((s) => s.errorMessage, 'error', isNotNull),
      ],
    );

    blocTest<FleetBloc, FleetState>(
      'double start is ignored (idempotent)',
      build: () => FleetBloc(provider: _MockFleetProvider()),
      seed: () => const FleetState(status: FleetStatus.listening),
      act: (bloc) => bloc.add(const FleetListenStarted()),
      expect: () => [],
    );
  });
}
