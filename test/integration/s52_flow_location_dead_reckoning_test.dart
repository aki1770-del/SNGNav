library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/bloc/bloc.dart';

import 's52_test_fixtures.dart';

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
}

void main() {
  group('S52 Flow 3: GPS -> dead reckoning -> location', () {
    test('normal GPS passes through as navigation-grade fix', () async {
      final gps = _MockGpsProvider();
      final provider = DeadReckoningProvider(
        inner: gps,
        gpsTimeout: const Duration(milliseconds: 400),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
      final bloc = LocationBloc(provider: provider);

      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 30));

      gps.emitPosition(S52TestFixtures.gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(gps.started, isTrue);
      expect(bloc.state.quality, LocationQuality.fix);
      expect(bloc.state.isDeadReckoning, isFalse);
      expect(bloc.state.position!.latitude, S52TestFixtures.gpsFix.latitude);

      await bloc.close();
    });

    test('GPS timeout activates DR and moves position forward', () async {
      final gps = _MockGpsProvider();
      final provider = DeadReckoningProvider(
        inner: gps,
        gpsTimeout: const Duration(milliseconds: 400),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
      final bloc = LocationBloc(provider: provider);

      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gps.emitPosition(S52TestFixtures.gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final initialLatitude = bloc.state.position!.latitude;

      await Future<void>.delayed(const Duration(milliseconds: 900));

      expect(provider.isDrActive, isTrue);
      expect(bloc.state.hasPosition, isTrue);
      expect(bloc.state.isDeadReckoning, isTrue);
      expect(bloc.state.position!.latitude, greaterThan(initialLatitude));
      expect(bloc.state.position!.accuracy, greaterThan(5.0));

      await bloc.close();
    });

    test('Kalman GPS recovery improves confidence and clears DR flag', () async {
      final gps = _MockGpsProvider();
      final provider = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 400),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
      final bloc = LocationBloc(provider: provider);

      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gps.emitPosition(S52TestFixtures.gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final gpsConfidence = bloc.state.confidenceRadius;

      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(provider.isDrActive, isTrue);
      expect(bloc.state.isDeadReckoning, isTrue);
      final drConfidence = bloc.state.confidenceRadius;

      gps.emitPosition(S52TestFixtures.gpsFixUpdated);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(provider.isDrActive, isFalse);
      expect(bloc.state.isDeadReckoning, isFalse);
      expect(bloc.state.quality, LocationQuality.fix);
      expect(bloc.state.confidenceRadius, lessThan(drConfidence));
      expect(bloc.state.confidenceRadius, lessThanOrEqualTo(gpsConfidence + 5));
      expect(
        bloc.state.position!.latitude,
        closeTo(S52TestFixtures.gpsFixUpdated.latitude, 0.005),
      );

      await bloc.close();
    });

    test('extended Kalman-only loss exceeds safety cap and stops DR emissions', () async {
      final gps = _MockGpsProvider();
      final provider = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 100),
        extrapolationInterval: const Duration(hours: 6),
      );
      final bloc = LocationBloc(
        provider: provider,
        staleThreshold: const Duration(milliseconds: 250),
      );

      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 30));
      gps.emitPosition(S52TestFixtures.gpsFix);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.quality, LocationQuality.fix);

      await Future<void>.delayed(const Duration(milliseconds: 180));

      expect(provider.isDrActive, isFalse,
          reason: 'Kalman DR should stop immediately when uncertainty '
              'exceeds the 500m safety cap');

      // DR cap trip now emits a DeadReckoningAccuracyExceededException on
      // the positions stream error channel (explicit terminal signal).
      // The LocationBloc's onError handler transitions to
      // LocationQuality.error on that event — this is the intended,
      // explicit "position unavailable" signal per the library docstring,
      // observed immediately instead of via stale-timer silence inference.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.quality, LocationQuality.error,
          reason: 'DR cap trip must emit an explicit error on the stream; '
              'LocationBloc routes it to LocationQuality.error');
      expect(bloc.state.errorMessage ?? '',
          contains('DeadReckoningAccuracyExceededException'),
          reason: 'error message should identify the cap-trip cause');

      await bloc.close();
    });
  });
}