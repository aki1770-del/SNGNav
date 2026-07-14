import 'package:driving_conditions/driving_conditions.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:test/test.dart';

void main() {
  group('ConstantFleetConfidenceProvider', () {
    test('defaults to 0.8', () {
      const provider = ConstantFleetConfidenceProvider();
      expect(provider.confidence, 0.8);
    });

    test('returns the provided value', () {
      const provider = ConstantFleetConfidenceProvider(0.5);
      expect(provider.confidence, 0.5);
    });

    test('accepts 0.0 and 1.0 boundary values', () {
      const low = ConstantFleetConfidenceProvider(0.0);
      const high = ConstantFleetConfidenceProvider(1.0);
      expect(low.confidence, 0.0);
      expect(high.confidence, 1.0);
    });
  });

  group('FleetHazardConfidenceAdapter', () {
    final now = DateTime.now();
    final position = const LatLng(35.1, 136.9);

    FleetReport report(
      RoadCondition condition, {
      double confidence = 1.0,
      Duration age = Duration.zero,
    }) => FleetReport(
      vehicleId: 'v1',
      position: position,
      timestamp: now.subtract(age),
      condition: condition,
      confidence: confidence,
    );

    test('returns 0.8 when no reports', () {
      const adapter = FleetHazardConfidenceAdapter([]);
      expect(adapter.confidence, 0.8);
    });

    test('returns 0.8 when all reports are stale', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy, age: const Duration(hours: 1)),
      ]);
      expect(adapter.confidence, 0.8);
    });

    test('dry report returns 1.0', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry),
      ]);
      expect(adapter.confidence, closeTo(1.0, 1e-9));
    });

    test('wet report returns 0.7', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.wet),
      ]);
      expect(adapter.confidence, closeTo(0.7, 1e-9));
    });

    test('snowy report returns 0.4', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.snowy),
      ]);
      expect(adapter.confidence, closeTo(0.4, 1e-9));
    });

    test('icy report returns 0.1', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy),
      ]);
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('unknown report returns 0.8', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.unknown),
      ]);
      expect(adapter.confidence, closeTo(0.8, 1e-9));
    });

    test('icy conditions produce lower confidence than snowy', () {
      final icy = FleetHazardConfidenceAdapter([report(RoadCondition.icy)]);
      final snowy =
          FleetHazardConfidenceAdapter([report(RoadCondition.snowy)]);
      expect(icy.confidence, lessThan(snowy.confidence));
    });

    test('mixed dry and icy reports are weighted by observation confidence',
        () {
      // dry report weight 0.8, icy report weight 0.2
      // expected = (1.0 * 0.8 + 0.1 * 0.2) / (0.8 + 0.2) = 0.82
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry, confidence: 0.8),
        report(RoadCondition.icy, confidence: 0.2),
      ]);
      expect(adapter.confidence, closeTo(0.82, 1e-9));
    });

    test('only recent reports are used', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.icy),                               // recent
        report(RoadCondition.dry, age: const Duration(hours: 1)), // stale
      ]);
      // Only the icy report counts → 0.1
      expect(adapter.confidence, closeTo(0.1, 1e-9));
    });

    test('custom maxAge is respected', () {
      final adapter = FleetHazardConfidenceAdapter(
        [report(RoadCondition.dry, age: const Duration(minutes: 5))],
        maxAge: const Duration(minutes: 3),
      );
      // 5-minute-old report is stale at 3-minute window → returns baseline 0.8
      expect(adapter.confidence, 0.8);
    });

    test('result is clamped to [0.0, 1.0]', () {
      final adapter = FleetHazardConfidenceAdapter([
        report(RoadCondition.dry),
      ]);
      expect(adapter.confidence, inInclusiveRange(0.0, 1.0));
    });
  });

  group('FleetConfidenceProvider injection into SafetyScoreSimulator', () {
    test('simulator with icy adapter produces lower score than constant 0.8',
        () {
      final position = const LatLng(35.1, 136.9);
      final icyReports = [
        FleetReport(
          vehicleId: 'v1',
          position: position,
          timestamp: DateTime.now(),
          condition: RoadCondition.icy,
        ),
      ];

      final icyAdapter = FleetHazardConfidenceAdapter(icyReports);
      final icySimulator = SafetyScoreSimulator(provider: icyAdapter);
      final defaultSimulator = const SafetyScoreSimulator();

      final icyResult = icySimulator.simulate(
        runs: 200,
        speed: 60,
        gripFactor: 0.7,
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 500,
        seed: 42,
      );
      final defaultResult = defaultSimulator.simulate(
        runs: 200,
        speed: 60,
        gripFactor: 0.7,
        surface: RoadSurfaceState.blackIce,
        visibilityMeters: 500,
        seed: 42,
      );

      expect(
        icyResult.score.fleetConfidenceScore,
        lessThan(defaultResult.score.fleetConfidenceScore),
      );
      expect(icyResult.score.overall, lessThan(defaultResult.score.overall));
    });

    test('simulator with dry fleet reports produces higher fleet score', () {
      final position = const LatLng(35.1, 136.9);
      final dryReports = [
        FleetReport(
          vehicleId: 'v1',
          position: position,
          timestamp: DateTime.now(),
          condition: RoadCondition.dry,
        ),
      ];

      final dryAdapter = FleetHazardConfidenceAdapter(dryReports);
      final simulator = SafetyScoreSimulator(provider: dryAdapter);

      final result = simulator.simulate(
        runs: 100,
        speed: 50,
        gripFactor: 0.9,
        surface: RoadSurfaceState.dry,
        visibilityMeters: 1000,
        seed: 7,
      );

      // dry fleet → confidence 1.0 > default 0.8 → fleet score > 0.8
      expect(result.score.fleetConfidenceScore, greaterThan(0.8));
    });
  });
}
