/// DeadReckoningProvider integration tests — GPS → DR → GPS transitions.
///
/// Tests the decorator pattern: DeadReckoningProvider wraps a mock
/// LocationProvider and extrapolates when GPS goes silent.
///
/// Sprint 9 Day 2 — E9-1 baseline tests.
/// Safety: ASIL-QM — display only.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/models/geo_position.dart';
import 'package:sngnav_snow_scene/providers/dead_reckoning_provider.dart';
import 'package:sngnav_snow_scene/providers/location_provider.dart';

// ---------------------------------------------------------------------------
// Mock inner provider — controllable GPS source
// ---------------------------------------------------------------------------

class MockLocationProvider implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }

  void emitPosition(GeoPosition pos) => _controller.add(pos);
  void emitError(Object error) => _controller.addError(error);
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _baseTime = DateTime(2026, 2, 28, 10, 0, 0);

/// Good GPS fix — driving north at 50 km/h.
final _gpsFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 13.89, // ~50 km/h
  heading: 0.0, // due north
  timestamp: _baseTime,
);

/// Updated GPS fix — slightly further north.
final _gpsFixUpdated = GeoPosition(
  latitude: 35.1720,
  longitude: 136.8815,
  accuracy: 3.0,
  speed: 16.67, // ~60 km/h
  heading: 0.0,
  timestamp: _baseTime.add(const Duration(seconds: 5)),
);

/// GPS fix with no speed/heading — cannot extrapolate.
final _gpsFixNoSpeed = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  timestamp: _baseTime,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DeadReckoningProvider — GPS passthrough', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('start calls inner provider start', () async {
      await provider.start();
      expect(mockGps.started, isTrue);
    });

    test('stop calls inner provider stop', () async {
      await provider.start();
      await provider.stop();
      expect(mockGps.stopped, isTrue);
    });

    test('dispose calls inner provider dispose', () async {
      await provider.start();
      await provider.dispose();
      expect(mockGps.disposed, isTrue);
    });

    test('GPS positions pass through to output stream', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(positions.length, equals(1));
      expect(positions[0], equals(_gpsFix));

      await sub.cancel();
    });

    test('multiple GPS positions pass through in order', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(positions.length, equals(2));
      expect(positions[0], equals(_gpsFix));
      expect(positions[1], equals(_gpsFixUpdated));

      await sub.cancel();
    });

    test('DR is not active when GPS is flowing', () async {
      await provider.start();

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.isDrActive, isFalse);
    });
  });

  group('DeadReckoningProvider — GPS loss triggers DR', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('DR activates after GPS timeout', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // Send one GPS fix, then go silent.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.isDrActive, isFalse);

      // Wait for GPS timeout (500ms) + first DR emission + scheduling buffer.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      expect(provider.isDrActive, isTrue);
      // Should have: 1 GPS + at least 1 DR position
      expect(positions.length, greaterThanOrEqualTo(2));

      await sub.cancel();
    });

    test('DR positions have degraded accuracy', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // Wait for DR to kick in and emit a few positions.
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // DR positions should have accuracy > base (5.0m).
      final drPositions = positions.skip(1).toList(); // skip GPS fix
      expect(drPositions, isNotEmpty);
      for (final pos in drPositions) {
        expect(pos.accuracy, greaterThan(5.0));
      }

      await sub.cancel();
    });

    test('DR positions move north when heading is 0°', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      // Wait for GPS timeout + DR emission + buffer.
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // DR should have produced positions north of the GPS fix.
      final drPositions = positions.skip(1).toList();
      expect(drPositions, isNotEmpty);

      for (final pos in drPositions) {
        expect(pos.latitude, greaterThanOrEqualTo(_gpsFix.latitude));
      }

      await sub.cancel();
    });

    test('DR does not activate when speed/heading are NaN', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // Send fix without speed/heading.
      mockGps.emitPosition(_gpsFixNoSpeed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Wait past GPS timeout — DR should NOT activate.
      await Future<void>.delayed(const Duration(milliseconds: 800));

      expect(provider.isDrActive, isFalse);
      // Only the original GPS fix should be in the stream.
      expect(positions.length, equals(1));

      await sub.cancel();
    });
  });

  group('DeadReckoningProvider — GPS recovery', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('GPS recovery stops DR and resumes passthrough', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // GPS fix → silence → DR activates.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(provider.isDrActive, isTrue);

      // GPS comes back.
      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(provider.isDrActive, isFalse);

      // Last position should be the GPS fix, not a DR estimate.
      expect(positions.last, equals(_gpsFixUpdated));

      await sub.cancel();
    });

    test('multiple GPS-loss cycles work correctly', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // Cycle 1: GPS → tunnel → GPS
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(provider.isDrActive, isTrue);

      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.isDrActive, isFalse);

      // Cycle 2: GPS → tunnel → GPS
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(provider.isDrActive, isTrue);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(provider.isDrActive, isFalse);

      await sub.cancel();
    });
  });

  group('DeadReckoningProvider — safety boundary', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('DR positions have increasing accuracy values', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      // Wait for GPS timeout + multiple DR emissions.
      await Future<void>.delayed(const Duration(milliseconds: 2000));

      final drPositions = positions.skip(1).toList();
      if (drPositions.length >= 2) {
        // Each successive DR position should have equal or higher accuracy value.
        for (var i = 1; i < drPositions.length; i++) {
          expect(
            drPositions[i].accuracy,
            greaterThanOrEqualTo(drPositions[i - 1].accuracy),
          );
        }
      }

      await sub.cancel();
    });
  });

  group('DeadReckoningProvider — error handling', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('GPS error propagates when DR is not active', () async {
      await provider.start();

      final errors = <Object>[];
      final sub = provider.positions.listen(
        (_) {},
        onError: errors.add,
      );

      mockGps.emitError(Exception('D-Bus connection lost'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(errors.length, equals(1));
      expect(errors[0].toString(), contains('D-Bus connection lost'));

      await sub.cancel();
    });

    test('GPS error suppressed when DR is active', () async {
      await provider.start();

      final errors = <Object>[];
      final sub = provider.positions.listen(
        (_) {},
        onError: errors.add,
      );

      // Get DR active first.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(provider.isDrActive, isTrue);

      // GPS error while DR is running — should be suppressed.
      mockGps.emitError(Exception('D-Bus timeout'));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(errors, isEmpty);

      await sub.cancel();
    });
  });

  group('DeadReckoningProvider — state inspection', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('currentState is null before any GPS fix', () async {
      await provider.start();
      expect(provider.currentState, isNull);
    });

    test('currentState updates after GPS fix', () async {
      await provider.start();

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.currentState, isNotNull);
      expect(provider.currentState!.latitude, equals(35.1709));
      expect(provider.currentState!.speed, equals(13.89));
    });

    test('currentState is null after fix without speed', () async {
      await provider.start();

      mockGps.emitPosition(_gpsFixNoSpeed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // fromGeoPosition returns null for NaN speed → currentState is null.
      expect(provider.currentState, isNull);
    });
  });

  // =========================================================================
  // Kalman mode tests — Sprint 10 Day 2
  // =========================================================================

  group('DeadReckoningProvider — Kalman mode GPS passthrough', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('kalmanFilter is available in Kalman mode', () async {
      await provider.start();
      expect(provider.kalmanFilter, isNotNull);
    });

    test('kalmanFilter is null in linear mode', () async {
      final linear = DeadReckoningProvider(
        inner: MockLocationProvider(),
        mode: DeadReckoningMode.linear,
      );
      await linear.start();
      expect(linear.kalmanFilter, isNull);
      await linear.dispose();
    });

    test('GPS positions emit filtered output', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(positions.length, equals(1));
      // Kalman filter initialises from first fix — output should match.
      expect(positions[0].latitude, closeTo(35.1709, 0.001));
      expect(positions[0].longitude, closeTo(136.8815, 0.001));
      expect(positions[0].speed, closeTo(13.89, 1.0));

      await sub.cancel();
    });

    test('multiple GPS fixes produce smoothed output', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // Send two GPS fixes.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(positions.length, equals(2));
      // Second position should be between first and raw measurement
      // (Kalman fusion smooths the transition).
      expect(positions[1].latitude, greaterThanOrEqualTo(35.1709));
      expect(positions[1].latitude, lessThanOrEqualTo(35.1725));

      await sub.cancel();
    });

    test('GPS fix without speed/heading passes through raw', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFixNoSpeed);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(positions.length, equals(1));
      // Raw passthrough — speed is NaN.
      expect(positions[0].speed.isNaN, isTrue);

      await sub.cancel();
    });
  });

  group('DeadReckoningProvider — Kalman mode DR', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('DR activates after GPS timeout in Kalman mode', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.isDrActive, isFalse);

      // Wait for GPS timeout + one DR emission.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(provider.isDrActive, isTrue);
      expect(positions.length, greaterThan(1));

      await sub.cancel();
    });

    test('Kalman DR positions have growing accuracy', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      mockGps.emitPosition(_gpsFix);
      // Wait for GPS timeout + multiple DR emissions.
      await Future<void>.delayed(const Duration(milliseconds: 2000));

      final drPositions = positions.skip(1).toList();
      if (drPositions.length >= 2) {
        for (var i = 1; i < drPositions.length; i++) {
          expect(
            drPositions[i].accuracy,
            greaterThanOrEqualTo(drPositions[i - 1].accuracy),
            reason: 'Kalman DR accuracy should degrade over time',
          );
        }
      }

      await sub.cancel();
    });

    test('GPS recovery stops Kalman DR', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // Start with GPS.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Wait for DR.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(provider.isDrActive, isTrue);

      // GPS recovery.
      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(provider.isDrActive, isFalse);

      await sub.cancel();
    });

    test('Kalman filter does not activate without initialisation', () async {
      await provider.start();

      // Emit fix without speed — filter won't initialise.
      mockGps.emitPosition(_gpsFixNoSpeed);
      await Future<void>.delayed(const Duration(milliseconds: 900));

      // DR should NOT activate (filter not initialised).
      expect(provider.isDrActive, isFalse);
    });
  });

  group('DeadReckoningProvider — Kalman mode accuracy recovery', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('accuracy recovers after GPS fix post-tunnel', () async {
      await provider.start();

      final positions = <GeoPosition>[];
      final sub = provider.positions.listen(positions.add);

      // GPS fix.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final preAccuracy = positions.last.accuracy;

      // GPS lost → DR.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final drAccuracy = positions.last.accuracy;
      expect(drAccuracy, greaterThan(preAccuracy));

      // GPS recovery.
      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final postAccuracy = positions.last.accuracy;

      expect(postAccuracy, lessThan(drAccuracy),
          reason: 'GPS fix should recover accuracy');

      await sub.cancel();
    });
  });
}
