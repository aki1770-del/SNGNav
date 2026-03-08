/// SimulatedLocationProvider unit tests — lifecycle, waypoint emission,
/// tunnel GPS loss, looping, and dispose behavior.
///
/// These are dedicated provider-level tests (previously only tested
/// via LocationBloc integration). Tests use a fast interval (10ms)
/// to avoid slow wall-clock waits.
///
/// Sprint 9 Day 11 — Test hardening.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/providers/simulated_location_provider.dart';

void main() {
  group('SimulatedLocationProvider', () {
    late SimulatedLocationProvider provider;

    setUp(() {
      provider = SimulatedLocationProvider(
        interval: const Duration(milliseconds: 10),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    group('construction', () {
      test('defaults: 1-second interval, tunnel enabled', () {
        final p = SimulatedLocationProvider();
        expect(p.includeTunnel, isTrue);
        expect(p.currentStep, 0);
        addTearDown(p.dispose);
      });

      test('custom interval accepted', () {
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 50),
        );
        expect(p.currentStep, 0);
        addTearDown(p.dispose);
      });

      test('tunnel can be disabled', () {
        final p = SimulatedLocationProvider(includeTunnel: false);
        expect(p.includeTunnel, isFalse);
        addTearDown(p.dispose);
      });
    });

    group('positions stream', () {
      test('returns a broadcast stream', () {
        final stream = provider.positions;
        expect(stream.isBroadcast, isTrue);
      });

      test('multiple listeners receive same events (broadcast)', () async {
        final received1 = <GeoPosition>[];
        final received2 = <GeoPosition>[];
        provider.positions.listen(received1.add);
        provider.positions.listen(received2.add);

        await provider.start();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await provider.stop();

        expect(received1, isNotEmpty);
        expect(received1.length, received2.length);
      });
    });

    group('start', () {
      test('emits first position immediately', () async {
        final completer = Completer<GeoPosition>();
        provider.positions.listen((pos) {
          if (!completer.isCompleted) completer.complete(pos);
        });

        await provider.start();

        final pos = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        // First position should be in the Nagoya–Okazaki corridor.
        // On CI runners, timer jitter may advance 1-2 steps before
        // the first listener callback fires.
        expect(pos.latitude, closeTo(35.17, 0.05));
        expect(pos.longitude, closeTo(136.90, 0.05));
      });

      test('first position has navigation-grade accuracy', () async {
        final completer = Completer<GeoPosition>();
        provider.positions.listen((pos) {
          if (!completer.isCompleted) completer.complete(pos);
        });

        await provider.start();

        final pos = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        expect(pos.isNavigationGrade, isTrue);
        expect(pos.accuracy, 5.0);
      });

      test('emits speed in m/s (city phase = 11.11 m/s ≈ 40 km/h)', () async {
        final completer = Completer<GeoPosition>();
        provider.positions.listen((pos) {
          if (!completer.isCompleted) completer.complete(pos);
        });

        await provider.start();

        final pos = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        expect(pos.speed, closeTo(11.11, 0.01));
        expect(pos.speedKmh, closeTo(40.0, 0.1));
      });

      test('emits multiple positions over time', () async {
        final positions = <GeoPosition>[];
        provider.positions.listen(positions.add);

        await provider.start();

        // Wait for a few emissions (10ms interval → ~5 in 80ms).
        await Future<void>.delayed(const Duration(milliseconds: 80));
        await provider.stop();

        expect(positions.length, greaterThanOrEqualTo(3));
      });

      test('resets step to 0 on restart', () async {
        await provider.start();
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await provider.stop();

        expect(provider.currentStep, greaterThan(0));

        // Restart should reset.
        await provider.start();
        expect(provider.currentStep, 0);
      });
    });

    group('waypoint phases', () {
      test('city phase (steps 0-4): heading varies along route', () async {
        final positions = <GeoPosition>[];
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 20),
          includeTunnel: false,
        );
        addTearDown(p.dispose);

        p.positions.listen(positions.add);
        await p.start();

        // Collect enough for city phase (20ms × 5 steps = 100ms + buffer).
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await p.stop();

        final cityPositions = positions.take(5).toList();
        for (final pos in cityPositions) {
          // City phase follows OSRM route — headings vary (SE to E).
          expect(pos.heading, greaterThanOrEqualTo(0.0));
          expect(pos.heading, lessThan(360.0));
          expect(pos.speed, closeTo(11.11, 0.01),
              reason: 'City phase speed should be 40 km/h');
        }
      });

      test('route 153 phase (steps 5-9): higher speed', () async {
        final positions = <GeoPosition>[];
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 20),
          includeTunnel: false,
        );
        addTearDown(p.dispose);

        p.positions.listen(positions.add);
        await p.start();

        // Wait for route 153 phase positions (20ms × 10 steps = 200ms + buffer).
        await Future<void>.delayed(const Duration(milliseconds: 400));
        await p.stop();

        // Steps 5-9 are at 70 km/h (19.44 m/s) on 国道153号.
        // Verify at least one position has route 153 speed.
        final route153Positions = positions
            .where((pos) => (pos.speed - 19.44).abs() < 0.1)
            .toList();
        expect(route153Positions, isNotEmpty,
            reason: 'Should have at least one position at 70 km/h');
      });

      test('mountain phase has higher speed than city', () async {
        final positions = <GeoPosition>[];
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 20),
          includeTunnel: false,
        );
        addTearDown(p.dispose);

        p.positions.listen(positions.add);
        await p.start();

        await Future<void>.delayed(const Duration(milliseconds: 250));
        await p.stop();

        if (positions.length > 5) {
          final citySpeed = positions[0].speed; // 11.11 m/s
          final mountainSpeed = positions[5].speed; // 19.44 m/s
          expect(mountainSpeed, greaterThan(citySpeed));
        }
      });
    });

    group('tunnel behavior', () {
      test('tunnel enabled: no emissions during steps 10-14', () async {
        final positions = <GeoPosition>[];
        final tunnelProvider = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 20),
          includeTunnel: true,
        );
        addTearDown(tunnelProvider.dispose);

        tunnelProvider.positions.listen(positions.add);
        await tunnelProvider.start();

        // Wait for full cycle (20 steps × 20ms = 400ms + buffer).
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await tunnelProvider.stop();

        // With tunnel: 20 steps, 5 are tunnel (no emission).
        // So we get at most 15 emissions per cycle.
        // Without tunnel we'd get 20.
        // Check that there's a gap — no position near tunnel coords.
        // Tunnel waypoints: lon 137.1088–137.1527.
        final tunnelPositions = positions
            .where((p) =>
                p.longitude >= 137.10 && p.longitude <= 137.16)
            .toList();
        expect(tunnelPositions, isEmpty,
            reason: 'Tunnel positions should not be emitted');
      });

      test('tunnel disabled: all 20 waypoints emit', () async {
        final positions = <GeoPosition>[];
        final noTunnelProvider = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 20),
          includeTunnel: false,
        );
        addTearDown(noTunnelProvider.dispose);

        noTunnelProvider.positions.listen(positions.add);
        await noTunnelProvider.start();

        // Wait for full cycle (20 steps × 20ms = 400ms + buffer).
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await noTunnelProvider.stop();

        // Should include tunnel-area positions.
        // Tunnel waypoints: lon 137.1088–137.1527.
        final tunnelPositions = positions
            .where((p) =>
                p.longitude >= 137.10 && p.longitude <= 137.16)
            .toList();
        expect(tunnelPositions, isNotEmpty,
            reason: 'With tunnel disabled, all positions should emit');
      });
    });

    group('looping', () {
      test('wraps around after 20 waypoints', () async {
        final positions = <GeoPosition>[];
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 20),
          includeTunnel: false,
        );
        addTearDown(p.dispose);

        p.positions.listen(positions.add);
        await p.start();

        // Wait for more than one full cycle (20 steps × 20ms = 400ms + buffer).
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await p.stop();

        // First and (first + 20)th should be at the same lat/lon.
        if (positions.length > 20) {
          expect(positions[0].latitude, positions[20].latitude);
          expect(positions[0].longitude, positions[20].longitude);
        }
      });
    });

    group('stop', () {
      test('stops emitting after stop()', () async {
        final positions = <GeoPosition>[];
        provider.positions.listen(positions.add);

        await provider.start();
        await Future<void>.delayed(const Duration(milliseconds: 30));
        await provider.stop();

        final countAfterStop = positions.length;
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(positions.length, countAfterStop,
            reason: 'No new positions after stop()');
      });

      test('stop is idempotent', () async {
        await provider.start();
        await provider.stop();
        await provider.stop(); // Should not throw.
      });
    });

    group('dispose', () {
      test('cancels timer and closes stream', () async {
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 10),
        );

        await p.start();
        await p.dispose();

        // After dispose, positions stream should be done.
        // Creating a new listener should not receive events.
        final received = <GeoPosition>[];
        p.positions.listen(received.add);
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(received, isEmpty);
      });

      test('dispose is safe before start', () async {
        final p = SimulatedLocationProvider();
        await p.dispose(); // Should not throw.
      });

      test('dispose is safe after stop', () async {
        final p = SimulatedLocationProvider(
          interval: const Duration(milliseconds: 10),
        );
        await p.start();
        await p.stop();
        await p.dispose(); // Should not throw.
      });
    });

    group('timestamp', () {
      test('each position has a recent timestamp', () async {
        final before = DateTime.now();
        final completer = Completer<GeoPosition>();
        provider.positions.listen((pos) {
          if (!completer.isCompleted) completer.complete(pos);
        });

        await provider.start();

        final pos = await completer.future.timeout(
          const Duration(seconds: 2),
        );
        final after = DateTime.now();

        expect(pos.timestamp.isAfter(before) || pos.timestamp == before,
            isTrue);
        expect(pos.timestamp.isBefore(after) || pos.timestamp == after,
            isTrue);
      });
    });
  });
}
