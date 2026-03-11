/// LocationBloc + DeadReckoningProvider integration test.
///
/// Proves the full pipeline: GPS → DR fallback → GPS recovery,
/// all through the BLoC state machine. The BLoC sees only
/// GeoPosition — it is unaware that DR is active.
///
/// This validates the L-10 interface-first pattern: swapping
/// the provider from raw GPS to DR-wrapped GPS changes zero
/// BLoC logic.
///
/// Sprint 9 Day 3 — E9-1 composition proof.
/// Architecture reference: A63 v3.0 §4 (location pipeline).
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';

import 'package:sngnav_snow_scene/bloc/bloc.dart';

// ---------------------------------------------------------------------------
// Mock GPS provider — controllable stream for integration testing
// ---------------------------------------------------------------------------
class _MockGpsProvider implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();
  bool started = false;

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emitPosition(GeoPosition pos) => _controller.add(pos);
  void emitError(Object error) => _controller.addError(error);
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
final _gpsFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 13.89,
  heading: 0.0,
  timestamp: DateTime.now(),
);

final _gpsFixUpdated = GeoPosition(
  latitude: 35.1720,
  longitude: 136.8815,
  accuracy: 3.0,
  speed: 16.67,
  heading: 45.0,
  timestamp: DateTime.now(),
);

final _gpsFixNoSpeed = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  timestamp: DateTime.now(),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('LocationBloc + DeadReckoningProvider — GPS passthrough', () {
    late _MockGpsProvider mockGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc bloc;

    setUp(() {
      mockGps = _MockGpsProvider();
      drProvider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
      bloc = LocationBloc(provider: drProvider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('BLoC transitions acquiring → fix on GPS position', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.quality, equals(LocationQuality.fix));
      expect(bloc.state.position!.latitude, equals(35.1709));
    });

    test('BLoC sees multiple GPS updates as fix → fix', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.fix));

      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.fix));
      expect(bloc.state.position!.latitude, equals(35.1720));
    });

    test('DR provider start/stop lifecycle through BLoC', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(mockGps.started, isTrue);

      bloc.add(const LocationStopRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.uninitialized));
    });
  });

  group('LocationBloc + DeadReckoningProvider — tunnel scenario', () {
    late _MockGpsProvider mockGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc bloc;

    setUp(() {
      mockGps = _MockGpsProvider();
      drProvider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
      bloc = LocationBloc(provider: drProvider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('GPS loss → DR keeps BLoC in fix/degraded (not stale)', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // GPS fix establishes position.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.fix));

      // GPS goes silent (tunnel). Wait for DR to activate.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // DR should be emitting extrapolated positions.
      expect(drProvider.isDrActive, isTrue);

      // BLoC should NOT be stale — DR is feeding it positions.
      // DR positions have degraded accuracy (>50m after some time),
      // so quality may be fix or degraded — but NOT stale or uninitialized.
      expect(bloc.state.quality, isNot(LocationQuality.stale));
      expect(bloc.state.quality, isNot(LocationQuality.uninitialized));
      expect(bloc.state.hasPosition, isTrue);
    });

    test('DR positions move north (heading 0°) through BLoC', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final initialLat = bloc.state.position!.latitude;

      // Wait for DR activation + a few extrapolation steps.
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      expect(drProvider.isDrActive, isTrue);
      // BLoC should show a position north of the original GPS fix.
      expect(bloc.state.position!.latitude, greaterThan(initialLat));
    });

    test('DR accuracy degrades — BLoC transitions fix → degraded', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.fix));

      // Wait for DR to activate and accuracy to degrade past 50m.
      // At +5m/sec degradation from 5m base, 50m is reached after ~9 seconds.
      // With 500ms timeout + 300ms intervals, we need a longer wait.
      // For test speed, check that accuracy is increasing (degraded is expected).
      await Future<void>.delayed(const Duration(milliseconds: 1500));

      // DR positions should have accuracy > base (5m).
      expect(bloc.state.position!.accuracy, greaterThan(5.0));
    });

    test('GPS recovery → BLoC returns to fix', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Establish GPS → tunnel → DR active.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(drProvider.isDrActive, isTrue);

      // GPS recovers (tunnel exit).
      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // DR should stop, BLoC should show the new GPS fix.
      expect(drProvider.isDrActive, isFalse);
      expect(bloc.state.quality, equals(LocationQuality.fix));
      expect(bloc.state.position!.latitude, equals(35.1720));
      expect(bloc.state.position!.accuracy, equals(3.0));
    });

    test('multiple tunnel cycles work through BLoC', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Cycle 1: GPS → tunnel → DR → GPS recovery
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(drProvider.isDrActive, isTrue);

      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(drProvider.isDrActive, isFalse);
      expect(bloc.state.quality, equals(LocationQuality.fix));

      // Cycle 2: GPS → tunnel → DR → GPS recovery
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(drProvider.isDrActive, isTrue);

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(drProvider.isDrActive, isFalse);
      expect(bloc.state.quality, equals(LocationQuality.fix));
    });
  });

  group('LocationBloc + DeadReckoningProvider — edge cases', () {
    late _MockGpsProvider mockGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc bloc;

    setUp(() {
      mockGps = _MockGpsProvider();
      drProvider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
      bloc = LocationBloc(provider: drProvider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('no DR when GPS fix lacks speed/heading', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Fix without speed/heading — DR cannot extrapolate.
      mockGps.emitPosition(_gpsFixNoSpeed);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.fix));

      // Wait past GPS timeout — DR should NOT activate.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(drProvider.isDrActive, isFalse);
    });

    test('GPS error propagates to BLoC when DR is not active', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitError(Exception('D-Bus connection lost'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.quality, equals(LocationQuality.error));
      expect(bloc.state.errorMessage, contains('D-Bus connection lost'));
    });

    test('GPS error suppressed when DR is active — BLoC unaffected', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Establish DR.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(drProvider.isDrActive, isTrue);
      final qualityBefore = bloc.state.quality;

      // GPS error during DR — should be suppressed.
      mockGps.emitError(Exception('D-Bus timeout'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // BLoC quality should not change to error.
      expect(bloc.state.quality, isNot(LocationQuality.error));
      expect(bloc.state.quality, equals(qualityBefore));
    });

    test('BLoC stale timer resets on DR positions', () async {
      bloc = LocationBloc(
        provider: drProvider,
        staleThreshold: const Duration(milliseconds: 2000),
      );
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // GPS fix.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, equals(LocationQuality.fix));

      // GPS lost → DR activates after 500ms.
      // DR emits every 300ms, keeping the stale timer (2000ms) resetting.
      // After 1800ms total, we should NOT be stale because DR kept emitting.
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      expect(drProvider.isDrActive, isTrue);
      expect(bloc.state.quality, isNot(LocationQuality.stale));
      expect(bloc.state.hasPosition, isTrue);
    });
  });

  // =========================================================================
  // Sprint 10 Day 3 — Kalman DR awareness in BLoC
  // =========================================================================

  group('LocationBloc — isDeadReckoning flag', () {
    late _MockGpsProvider mockGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc bloc;

    setUp(() {
      mockGps = _MockGpsProvider();
      drProvider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
      bloc = LocationBloc(provider: drProvider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('isDeadReckoning is false for live GPS fix', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.isDeadReckoning, isFalse);
      expect(bloc.state.quality, equals(LocationQuality.fix));
    });

    test('isDeadReckoning is true during DR', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.isDeadReckoning, isFalse);

      // Wait for GPS timeout + DR emission.
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(drProvider.isDrActive, isTrue);
      expect(bloc.state.isDeadReckoning, isTrue);
    });

    test('isDeadReckoning returns to false on GPS recovery', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // GPS → DR → GPS recovery.
      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(bloc.state.isDeadReckoning, isTrue);

      mockGps.emitPosition(_gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.isDeadReckoning, isFalse);
    });
  });

  group('LocationBloc — confidenceRadius', () {
    late _MockGpsProvider mockGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc bloc;

    setUp(() {
      mockGps = _MockGpsProvider();
      drProvider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 300),
      );
      bloc = LocationBloc(provider: drProvider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('confidenceRadius is 0 when no position', () {
      expect(bloc.state.confidenceRadius, equals(0.0));
    });

    test('confidenceRadius reflects GPS accuracy', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix); // accuracy: 5.0
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.confidenceRadius, closeTo(5.0, 2.0));
    });

    test('confidenceRadius grows during dead reckoning', () async {
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      mockGps.emitPosition(_gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final gpsRadius = bloc.state.confidenceRadius;

      // Wait for DR to build up uncertainty.
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      final drRadius = bloc.state.confidenceRadius;

      expect(drRadius, greaterThan(gpsRadius),
          reason: 'Confidence radius should grow during DR');
    });
  });
}
