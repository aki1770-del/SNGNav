/// LocationBloc unit tests — 6-state quality machine.
///
/// Tests the complete state machine with a mock LocationProvider.
/// No D-Bus required — pure logic testing.
///
/// Sprint 7 Day 2 — LocationBloc extraction.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:sngnav_snow_scene/models/models.dart';

// ---------------------------------------------------------------------------
// Mock provider — controllable stream for testing
// ---------------------------------------------------------------------------
class MockLocationProvider implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();
  bool started = false;
  bool stopped = false;
  bool disposed = false;
  bool shouldThrowOnStart = false;

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {
    if (shouldThrowOnStart) {
      throw Exception('GeoClue2 not available');
    }
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

  /// Emit a position into the stream (test helper).
  void emitPosition(GeoPosition pos) {
    _controller.add(pos);
  }

  /// Emit an error into the stream (test helper).
  void emitError(Object error) {
    _controller.addError(error);
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
final _nagoyaFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0, // navigation-grade (≤ 50m)
  speed: 13.89, // ~50 km/h
  heading: 90.0,
  timestamp: DateTime(2026, 2, 27, 10, 0),
);

final _degradedFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 200.0, // NOT navigation-grade (> 50m)
  timestamp: DateTime(2026, 2, 27, 10, 1),
);

final _updatedFix = GeoPosition(
  latitude: 35.1720,
  longitude: 136.8830,
  accuracy: 3.0,
  speed: 16.67, // ~60 km/h
  heading: 45.0,
  timestamp: DateTime(2026, 2, 27, 10, 2),
);

final _borderlineFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 50.0, // exactly 50m — navigation-grade boundary
  timestamp: DateTime(2026, 2, 27, 10, 3),
);

final _justOverThreshold = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 50.1, // just over — degraded
  timestamp: DateTime(2026, 2, 27, 10, 4),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('GeoPosition model', () {
    test('creates with required fields, optionals default to NaN', () {
      final pos = GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 10.0,
        timestamp: DateTime(2026, 2, 27),
      );

      expect(pos.latitude, equals(35.1709));
      expect(pos.longitude, equals(136.8815));
      expect(pos.accuracy, equals(10.0));
      expect(pos.altitude, isNaN);
      expect(pos.speed, isNaN);
      expect(pos.heading, isNaN);
    });

    test('speedKmh converts m/s to km/h', () {
      expect(_nagoyaFix.speedKmh, closeTo(50.0, 0.1));
    });

    test('speedKmh returns NaN when speed is NaN', () {
      final pos = GeoPosition(
        latitude: 35.0,
        longitude: 137.0,
        accuracy: 5.0,
        timestamp: DateTime.now(),
      );
      expect(pos.speedKmh, isNaN);
    });

    test('isNavigationGrade true when accuracy ≤ 50m', () {
      expect(_nagoyaFix.isNavigationGrade, isTrue);
      expect(_borderlineFix.isNavigationGrade, isTrue);
    });

    test('isNavigationGrade false when accuracy > 50m', () {
      expect(_degradedFix.isNavigationGrade, isFalse);
      expect(_justOverThreshold.isNavigationGrade, isFalse);
    });

    test('isHighAccuracy true when accuracy ≤ 10m', () {
      expect(_nagoyaFix.isHighAccuracy, isTrue);
      expect(_updatedFix.isHighAccuracy, isTrue);
    });

    test('isHighAccuracy false when accuracy > 10m', () {
      expect(_borderlineFix.isHighAccuracy, isFalse);
      expect(_degradedFix.isHighAccuracy, isFalse);
    });

    test('equality works (Equatable)', () {
      final a = GeoPosition(
        latitude: 35.0,
        longitude: 137.0,
        accuracy: 5.0,
        timestamp: DateTime(2026, 2, 27),
      );
      final b = GeoPosition(
        latitude: 35.0,
        longitude: 137.0,
        accuracy: 5.0,
        timestamp: DateTime(2026, 2, 27),
      );
      expect(a, equals(b));
    });

    test('toString includes coordinates and accuracy', () {
      final s = _nagoyaFix.toString();
      expect(s, contains('35.1709'));
      expect(s, contains('136.8815'));
      expect(s, contains('5.0'));
    });
  });

  group('LocationState', () {
    test('uninitialized has no position and no error', () {
      const state = LocationState.uninitialized();
      expect(state.quality, equals(LocationQuality.uninitialized));
      expect(state.position, isNull);
      expect(state.errorMessage, isNull);
      expect(state.isTracking, isFalse);
      expect(state.hasPosition, isFalse);
      expect(state.isNavigationGrade, isFalse);
    });

    test('acquiring is tracking but has no position', () {
      const state = LocationState.acquiring();
      expect(state.quality, equals(LocationQuality.acquiring));
      expect(state.isTracking, isTrue);
      expect(state.hasPosition, isFalse);
    });

    test('fix state is navigation-grade', () {
      final state = LocationState(
        quality: LocationQuality.fix,
        position: _nagoyaFix,
      );
      expect(state.isNavigationGrade, isTrue);
      expect(state.hasPosition, isTrue);
    });

    test('degraded state has position but is not navigation-grade', () {
      final state = LocationState(
        quality: LocationQuality.degraded,
        position: _degradedFix,
      );
      expect(state.isNavigationGrade, isFalse);
      expect(state.hasPosition, isTrue);
    });

    test('stale state preserves last known position', () {
      final state = LocationState(
        quality: LocationQuality.stale,
        position: _nagoyaFix,
      );
      expect(state.hasPosition, isTrue);
      expect(state.isNavigationGrade, isFalse);
    });

    test('error state has message', () {
      const state = LocationState(
        quality: LocationQuality.error,
        errorMessage: 'D-Bus timeout',
      );
      expect(state.errorMessage, equals('D-Bus timeout'));
      expect(state.hasPosition, isFalse);
    });

    test('copyWith preserves position, clears error', () {
      final state = LocationState(
        quality: LocationQuality.fix,
        position: _nagoyaFix,
      );
      final stale = state.copyWith(quality: LocationQuality.stale);
      expect(stale.quality, equals(LocationQuality.stale));
      expect(stale.position, equals(_nagoyaFix));
      expect(stale.errorMessage, isNull);
    });
  });

  group('LocationEvent', () {
    test('events are equatable', () {
      expect(
        const LocationStartRequested(),
        equals(const LocationStartRequested()),
      );
      expect(
        LocationPositionReceived(_nagoyaFix),
        equals(LocationPositionReceived(_nagoyaFix)),
      );
      expect(
        const LocationErrorOccurred('test'),
        equals(const LocationErrorOccurred('test')),
      );
    });
  });

  group('LocationBloc — initial state', () {
    late MockLocationProvider provider;

    setUp(() {
      provider = MockLocationProvider();
    });

    test('initial state is uninitialized', () {
      final bloc = LocationBloc(provider: provider);
      expect(bloc.state, equals(const LocationState.uninitialized()));
      bloc.close();
    });
  });

  group('LocationBloc — start/stop lifecycle', () {
    late MockLocationProvider provider;

    setUp(() {
      provider = MockLocationProvider();
    });

    blocTest<LocationBloc, LocationState>(
      'emits [acquiring] when start is requested',
      build: () => LocationBloc(provider: provider),
      act: (bloc) => bloc.add(const LocationStartRequested()),
      expect: () => [const LocationState.acquiring()],
      verify: (_) {
        expect(provider.started, isTrue);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'emits [acquiring, error] when provider throws on start',
      build: () {
        provider.shouldThrowOnStart = true;
        return LocationBloc(provider: provider);
      },
      act: (bloc) => bloc.add(const LocationStartRequested()),
      expect: () => [
        const LocationState.acquiring(),
        isA<LocationState>()
            .having((s) => s.quality, 'quality', LocationQuality.error)
            .having(
                (s) => s.errorMessage, 'error', contains('not available')),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'emits [uninitialized] when stop is requested from uninitialized (idempotent)',
      build: () => LocationBloc(provider: provider),
      act: (bloc) => bloc.add(const LocationStopRequested()),
      expect: () => [const LocationState.uninitialized()],
    );

    blocTest<LocationBloc, LocationState>(
      'returns to uninitialized after start then stop',
      build: () => LocationBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const LocationStopRequested());
      },
      expect: () => [
        const LocationState.acquiring(),
        const LocationState.uninitialized(),
      ],
      verify: (_) {
        expect(provider.stopped, isTrue);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'ignores duplicate start when already tracking',
      build: () => LocationBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        bloc.add(const LocationStartRequested()); // duplicate — ignored
      },
      expect: () => [const LocationState.acquiring()],
    );
  });

  group('LocationBloc — position received transitions', () {
    late MockLocationProvider provider;

    setUp(() {
      provider = MockLocationProvider();
    });

    blocTest<LocationBloc, LocationState>(
      'acquiring → fix when navigation-grade position received',
      build: () => LocationBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.emitPosition(_nagoyaFix);
      },
      expect: () => [
        const LocationState.acquiring(),
        LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'acquiring → degraded when low-accuracy position received',
      build: () => LocationBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.emitPosition(_degradedFix);
      },
      expect: () => [
        const LocationState.acquiring(),
        LocationState(
            quality: LocationQuality.degraded, position: _degradedFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'fix → fix when new navigation-grade position received',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_updatedFix)),
      expect: () => [
        LocationState(quality: LocationQuality.fix, position: _updatedFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'fix → degraded when accuracy drops below 50m',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_degradedFix)),
      expect: () => [
        LocationState(
            quality: LocationQuality.degraded, position: _degradedFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'degraded → fix when accuracy improves',
      build: () => LocationBloc(provider: provider),
      seed: () => LocationState(
          quality: LocationQuality.degraded, position: _degradedFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_nagoyaFix)),
      expect: () => [
        LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'exactly 50m accuracy is navigation-grade (boundary)',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(LocationPositionReceived(_borderlineFix)),
      expect: () => [
        LocationState(
            quality: LocationQuality.fix, position: _borderlineFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      '50.1m accuracy is degraded (boundary)',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(LocationPositionReceived(_justOverThreshold)),
      expect: () => [
        LocationState(
            quality: LocationQuality.degraded,
            position: _justOverThreshold),
      ],
    );
  });

  group('LocationBloc — stale timeout', () {
    late MockLocationProvider provider;

    setUp(() {
      provider = MockLocationProvider();
    });

    blocTest<LocationBloc, LocationState>(
      'fix → stale when timeout fires',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
      act: (bloc) => bloc.add(const LocationStaleTimeout()),
      expect: () => [
        LocationState(quality: LocationQuality.stale, position: _nagoyaFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'degraded → stale when timeout fires',
      build: () => LocationBloc(provider: provider),
      seed: () => LocationState(
          quality: LocationQuality.degraded, position: _degradedFix),
      act: (bloc) => bloc.add(const LocationStaleTimeout()),
      expect: () => [
        LocationState(
            quality: LocationQuality.stale, position: _degradedFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'stale timeout ignored when acquiring (no position yet)',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(const LocationStaleTimeout()),
      expect: () => <LocationState>[],
    );

    blocTest<LocationBloc, LocationState>(
      'stale → fix when new good position arrives',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.stale, position: _nagoyaFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_updatedFix)),
      expect: () => [
        LocationState(quality: LocationQuality.fix, position: _updatedFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'stale timer fires after configured threshold',
      build: () => LocationBloc(
        provider: provider,
        staleThreshold: const Duration(milliseconds: 100),
      ),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.emitPosition(_nagoyaFix);
        // Wait for stale threshold to fire
        await Future<void>.delayed(const Duration(milliseconds: 200));
      },
      expect: () => [
        const LocationState.acquiring(),
        LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
        LocationState(quality: LocationQuality.stale, position: _nagoyaFix),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'stale timer resets on each new position',
      build: () => LocationBloc(
        provider: provider,
        staleThreshold: const Duration(milliseconds: 150),
      ),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 50));
        provider.emitPosition(_nagoyaFix);
        // Wait 100ms (before stale), send another position
        await Future<void>.delayed(const Duration(milliseconds: 100));
        provider.emitPosition(_updatedFix);
        // Wait another 100ms — still before stale (timer was reset)
        await Future<void>.delayed(const Duration(milliseconds: 100));
        // Now wait for stale to fire
        await Future<void>.delayed(const Duration(milliseconds: 100));
      },
      expect: () => [
        const LocationState.acquiring(),
        LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
        LocationState(quality: LocationQuality.fix, position: _updatedFix),
        LocationState(
            quality: LocationQuality.stale, position: _updatedFix),
      ],
    );
  });

  group('LocationBloc — error transitions', () {
    late MockLocationProvider provider;

    setUp(() {
      provider = MockLocationProvider();
    });

    blocTest<LocationBloc, LocationState>(
      'fix → error on error event',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _nagoyaFix),
      act: (bloc) =>
          bloc.add(const LocationErrorOccurred('D-Bus connection lost')),
      expect: () => [
        const LocationState(
          quality: LocationQuality.error,
          errorMessage: 'D-Bus connection lost',
        ),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'degraded → error on error event',
      build: () => LocationBloc(provider: provider),
      seed: () => LocationState(
          quality: LocationQuality.degraded, position: _degradedFix),
      act: (bloc) => bloc.add(const LocationErrorOccurred('timeout')),
      expect: () => [
        const LocationState(
          quality: LocationQuality.error,
          errorMessage: 'timeout',
        ),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'acquiring → error on error event',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) =>
          bloc.add(const LocationErrorOccurred('permission denied')),
      expect: () => [
        const LocationState(
          quality: LocationQuality.error,
          errorMessage: 'permission denied',
        ),
      ],
    );
  });

  group('LocationBloc — close', () {
    test('close disposes provider', () async {
      final provider = MockLocationProvider();
      final bloc = LocationBloc(provider: provider);
      await bloc.close();
      expect(provider.disposed, isTrue);
    });
  });
}
