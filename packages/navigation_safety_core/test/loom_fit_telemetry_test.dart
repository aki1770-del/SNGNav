/// Tests for `LoomFitTelemetry` emit-only telemetry stream.
library;

import 'dart:async';

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('LoomFitTelemetryRecord', () {
    test('alertSequence is defensively copied (unmodifiable)', () {
      final src = <DateTime>[DateTime(2026, 5, 4, 10, 0, 0)];
      final r = LoomFitTelemetryRecord(
        profileClass: DriverProfile.snowZoneExperienced,
        ambientThreshold: 'icy_road_30km',
        alertSequence: src,
        responseLatency: const Duration(milliseconds: 800),
        outcome: LoomFitOutcome.fired,
      );

      // Mutating the source must not affect the record.
      src.add(DateTime(2026, 5, 4, 10, 0, 30));
      expect(r.alertSequence.length, 1);

      // The record's list itself is unmodifiable.
      expect(
        () => r.alertSequence.add(DateTime(2026, 5, 4)),
        throwsUnsupportedError,
      );
    });
  });

  group('LoomFitTelemetry', () {
    test('record + listen returns the record on the stream', () async {
      final t = LoomFitTelemetry();
      final completer = Completer<LoomFitTelemetryRecord>();
      final sub = t.records.listen(completer.complete);

      final r = LoomFitTelemetryRecord(
        profileClass: DriverProfile.ageingRural,
        ambientThreshold: 'black_ice_temp_2c',
        alertSequence: <DateTime>[DateTime(2026, 5, 4, 11, 0, 0)],
        responseLatency: null,
        outcome: LoomFitOutcome.fired,
      );
      t.record(r);

      final got = await completer.future.timeout(const Duration(seconds: 1));
      expect(got.profileClass, DriverProfile.ageingRural);
      expect(got.ambientThreshold, 'black_ice_temp_2c');
      expect(got.outcome, LoomFitOutcome.fired);
      expect(got.responseLatency, isNull);

      await sub.cancel();
      await t.dispose();
    });

    test('multiple records arrive in order', () async {
      final t = LoomFitTelemetry();
      final received = <LoomFitOutcome>[];
      final sub = t.records.listen((r) => received.add(r.outcome));

      final base = DateTime(2026, 5, 4, 12);
      t.record(LoomFitTelemetryRecord(
        profileClass: DriverProfile.noviceUrban,
        ambientThreshold: null,
        alertSequence: <DateTime>[base],
        responseLatency: null,
        outcome: LoomFitOutcome.coldStart,
      ));
      t.record(LoomFitTelemetryRecord(
        profileClass: DriverProfile.noviceUrban,
        ambientThreshold: null,
        alertSequence: <DateTime>[base, base.add(const Duration(seconds: 5))],
        responseLatency: null,
        outcome: LoomFitOutcome.fired,
      ));
      t.record(LoomFitTelemetryRecord(
        profileClass: DriverProfile.noviceUrban,
        ambientThreshold: null,
        alertSequence: <DateTime>[base, base.add(const Duration(seconds: 5))],
        responseLatency: null,
        outcome: LoomFitOutcome.droppedByThrottle,
      ));

      // Drain microtasks so broadcast deliveries land.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(received, <LoomFitOutcome>[
        LoomFitOutcome.coldStart,
        LoomFitOutcome.fired,
        LoomFitOutcome.droppedByThrottle,
      ]);

      await sub.cancel();
      await t.dispose();
    });

    test('broadcast stream allows multiple listeners', () async {
      final t = LoomFitTelemetry();
      final aOutcomes = <LoomFitOutcome>[];
      final bOutcomes = <LoomFitOutcome>[];
      final aSub = t.records.listen((r) => aOutcomes.add(r.outcome));
      final bSub = t.records.listen((r) => bOutcomes.add(r.outcome));

      t.record(LoomFitTelemetryRecord(
        profileClass: DriverProfile.professional,
        ambientThreshold: 'visibility_floor_320m',
        alertSequence: const <DateTime>[],
        responseLatency: null,
        outcome: LoomFitOutcome.criticalBypass,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(aOutcomes, <LoomFitOutcome>[LoomFitOutcome.criticalBypass]);
      expect(bOutcomes, <LoomFitOutcome>[LoomFitOutcome.criticalBypass]);

      await aSub.cancel();
      await bSub.cancel();
      await t.dispose();
    });

    test('all four outcome enum values can be emitted', () async {
      final t = LoomFitTelemetry();
      final received = <LoomFitOutcome>{};
      final sub = t.records.listen((r) => received.add(r.outcome));

      for (final outcome in LoomFitOutcome.values) {
        t.record(LoomFitTelemetryRecord(
          profileClass: DriverProfile.foreignTouristSnowZone,
          ambientThreshold: null,
          alertSequence: const <DateTime>[],
          responseLatency: null,
          outcome: outcome,
        ));
      }

      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(received, LoomFitOutcome.values.toSet());

      await sub.cancel();
      await t.dispose();
    });

    test('dispose closes the stream', () async {
      final t = LoomFitTelemetry();
      final doneCompleter = Completer<void>();
      final sub = t.records.listen(
        (_) {},
        onDone: doneCompleter.complete,
      );

      await t.dispose();
      await doneCompleter.future.timeout(const Duration(seconds: 1));
      await sub.cancel();
    });

    test('record after dispose silently no-ops', () async {
      final t = LoomFitTelemetry();
      await t.dispose();
      // No throw — the package boundary swallows post-dispose calls so
      // a late integrator emit cannot crash the consuming app.
      t.record(LoomFitTelemetryRecord(
        profileClass: DriverProfile.agriculturalForestry,
        ambientThreshold: null,
        alertSequence: const <DateTime>[],
        responseLatency: null,
        outcome: LoomFitOutcome.fired,
      ));
    });

    test('dispose is idempotent', () async {
      final t = LoomFitTelemetry();
      await t.dispose();
      // Second dispose must not throw.
      await t.dispose();
    });

    test('record with null ambientThreshold + null responseLatency works',
        () async {
      final t = LoomFitTelemetry();
      final completer = Completer<LoomFitTelemetryRecord>();
      final sub = t.records.listen(completer.complete);

      t.record(LoomFitTelemetryRecord(
        profileClass: DriverProfile.snowZoneExperienced,
        ambientThreshold: null,
        alertSequence: const <DateTime>[],
        responseLatency: null,
        outcome: LoomFitOutcome.coldStart,
      ));

      final got = await completer.future.timeout(const Duration(seconds: 1));
      expect(got.ambientThreshold, isNull);
      expect(got.responseLatency, isNull);
      expect(got.alertSequence, isEmpty);
      expect(got.outcome, LoomFitOutcome.coldStart);

      await sub.cancel();
      await t.dispose();
    });
  });
}
