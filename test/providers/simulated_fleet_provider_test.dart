/// SimulatedFleetProvider unit tests.
///
/// Tests:
///   1. Emits a report on startListening
///   2. Reports contain valid vehicle IDs
///   3. Reports alternate through simulated vehicles
///   4. Reports have valid positions (Nagoya region)
///   5. Reports have valid confidence (0.7–1.0)
///   6. Stop prevents further emissions
///   7. Reports include hazard conditions (snowy/icy) for mountain vehicles
///   8. Reports are recent
///
/// Sprint 8 Day 4.
library;

import 'dart:async';

import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/providers/simulated_fleet_provider.dart';

void main() {
  group('SimulatedFleetProvider', () {
    late SimulatedFleetProvider provider;

    setUp(() {
      provider = SimulatedFleetProvider(
        interval: const Duration(milliseconds: 50),
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('emits a report on startListening', () async {
      final completer = Completer<FleetReport>();
      provider.reports.first.then(completer.complete);

      await provider.startListening();
      final report = await completer.future.timeout(
        const Duration(seconds: 2),
      );

      expect(report, isNotNull);
      expect(report.vehicleId, isNotEmpty);
    });

    test('reports contain valid vehicle IDs', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
      await provider.stopListening();

      expect(reports, isNotEmpty);
      for (final report in reports) {
        expect(report.vehicleId, startsWith('V-'));
      }
    });

    test('reports alternate through simulated vehicles', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      await sub.cancel();
      await provider.stopListening();

      // 50ms interval over 800ms → ~16 reports cycling through 5 vehicles
      final ids = reports.map((r) => r.vehicleId).toSet();
      expect(ids.length, greaterThan(1));
    });

    test('reports have valid positions in Nagoya region', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
      await provider.stopListening();

      for (final report in reports) {
        // Nagoya–Mikawa region: lat 34.9–35.3, lon 136.7–137.5
        expect(report.position.latitude, inInclusiveRange(34.9, 35.3));
        expect(report.position.longitude, inInclusiveRange(136.7, 137.5));
      }
    });

    test('reports have valid confidence range (0.7–1.0)', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await sub.cancel();
      await provider.stopListening();

      for (final report in reports) {
        expect(report.confidence, inInclusiveRange(0.7, 1.0));
      }
    });

    test('stopListening prevents further emissions', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await provider.stopListening();
      final countAfterStop = reports.length;

      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();

      // No new reports after stop
      expect(reports.length, countAfterStop);
    });

    test('mountain vehicles report hazard conditions', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      // Collect enough reports to see mountain vehicles
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await sub.cancel();
      await provider.stopListening();

      // At least some reports should be hazards (snowy/icy)
      final hazards = reports.where((r) => r.isHazard).toList();
      expect(hazards, isNotEmpty);
    });

    test('reports are recent', () async {
      final reports = <FleetReport>[];
      final sub = provider.reports.listen(reports.add);

      await provider.startListening();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await sub.cancel();
      await provider.stopListening();

      for (final report in reports) {
        expect(report.isRecent(), true);
      }
    });
  });
}
