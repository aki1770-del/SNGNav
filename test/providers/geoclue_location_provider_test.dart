library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/providers/geoclue_location_provider.dart';

class _FakeGeoClueSession implements GeoClueSession {
  _FakeGeoClueSession({
    this.availableAccuracyLevel,
  });

  final int? availableAccuracyLevel;
  GeoPosition? nextPosition;
  final _updates = StreamController<String>.broadcast();

  int? requestedAccuracyLevel;
  String? desktopId;
  bool started = false;
  bool stopped = false;
  bool closed = false;
  bool throwOnInitialize = false;
  bool throwOnStart = false;
  bool throwOnRead = false;

  @override
  Future<int?> getAvailableAccuracyLevel() async => availableAccuracyLevel;

  @override
  Future<void> initializeClient({
    required String desktopId,
    required int requestedAccuracyLevel,
  }) async {
    if (throwOnInitialize) {
      throw Exception('init failed');
    }
    this.desktopId = desktopId;
    this.requestedAccuracyLevel = requestedAccuracyLevel;
  }

  @override
  Stream<String> get locationUpdates => _updates.stream;

  @override
  Future<GeoPosition> readPosition(
    String locationPath, {
    required DateTime Function() now,
  }) async {
    if (throwOnRead) {
      throw Exception('read failed');
    }

    return nextPosition ??
        GeoPosition(
          latitude: 35.1709,
          longitude: 136.8815,
          accuracy: 12.0,
          timestamp: now(),
        );
  }

  @override
  Future<void> start() async {
    if (throwOnStart) {
      throw Exception('start failed');
    }
    started = true;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> close() async {
    closed = true;
    if (!_updates.isClosed) {
      await _updates.close();
    }
  }

  void emitLocation(String locationPath) {
    _updates.add(locationPath);
  }
}

void main() {
  group('GeoClueLocationProvider', () {
    late _FakeGeoClueSession session;
    late GeoClueLocationProvider provider;

    setUp(() {
      session = _FakeGeoClueSession();
      provider = GeoClueLocationProvider(
        sessionFactory: () => session,
        now: () => DateTime(2026, 3, 13, 12, 0),
      );
    });

    tearDown(() async {
      await provider.dispose();
    });

    test('clamps requested accuracy to available level', () async {
      session = _FakeGeoClueSession(availableAccuracyLevel: 6);
      provider = GeoClueLocationProvider(
        sessionFactory: () => session,
        now: () => DateTime(2026, 3, 13, 12, 0),
      );
      addTearDown(provider.dispose);

      await provider.start();

      expect(provider.availableAccuracyLevel, equals(6));
      expect(provider.requestedAccuracyLevel, equals(6));
      expect(session.desktopId, equals('sngnav-snow-scene'));
      expect(session.started, isTrue);
    });

    test('throws clearly when GeoClue services are disabled', () async {
      session = _FakeGeoClueSession(availableAccuracyLevel: 0);
      provider = GeoClueLocationProvider(
        sessionFactory: () => session,
      );
      addTearDown(provider.dispose);

      await expectLater(
        provider.start(),
        throwsA(
          isA<GeoClueException>().having(
            (error) => error.message,
            'message',
            contains('disabled'),
          ),
        ),
      );

      expect(provider.isRunning, isFalse);
      expect(session.closed, isTrue);
    });

    test('emits positions from GeoClue updates', () async {
      final received = <GeoPosition>[];
      provider.positions.listen(received.add);

      await provider.start();
      session.nextPosition = GeoPosition(
        latitude: 35.6895,
        longitude: 139.6917,
        accuracy: 25.0,
        speed: 8.0,
        heading: 90.0,
        timestamp: DateTime(2026, 3, 13, 12, 0),
      );

      session.emitLocation('/org/freedesktop/GeoClue2/Location/1');
      await Future<void>.delayed(Duration.zero);

      expect(received, hasLength(1));
      expect(received.single.latitude, equals(35.6895));
      expect(received.single.timestamp, equals(DateTime(2026, 3, 13, 12, 0)));
    });

    test('surfaces read failures on the positions stream', () async {
      Object? streamError;
      provider.positions.listen((_) {}, onError: (Object error) {
        streamError = error;
      });

      await provider.start();
      session.throwOnRead = true;

      session.emitLocation('/org/freedesktop/GeoClue2/Location/2');
      await Future<void>.delayed(Duration.zero);

      expect(streamError, isA<GeoClueException>());
    });

    test('stop tears down session lifecycle cleanly', () async {
      await provider.start();
      await provider.stop();

      expect(provider.isRunning, isFalse);
      expect(session.stopped, isTrue);
      expect(session.closed, isTrue);
    });
  });
}
