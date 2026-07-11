/// L2 source-guard tests — a non-finite GeoClue read is skipped at ingest so a
/// NaN/±inf coordinate never enters the location pipeline (and so never reaches
/// a flutter_map boundary, which on 8.2.2 SILENTLY projects a non-finite
/// coordinate to garbage, teleporting HER dot with no throw — the degraded-GPS
/// compound-failure scenario this whole defense-in-depth stack exists for).
///
/// The skip is SILENT (no stream error): surfacing an error on a single bad fix
/// would knock the LocationBloc into its error state, killing the map even when
/// a valid last-good fix is in hand.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/providers/geoclue_location_provider.dart';

/// Minimal fake GeoClue session — returns [nextPosition] for each update.
class _FakeGeoClueSession implements GeoClueSession {
  GeoPosition? nextPosition;
  final _updates = StreamController<String>.broadcast();

  @override
  Future<int?> getAvailableAccuracyLevel() async => null;

  @override
  Future<void> initializeClient({
    required String desktopId,
    required int requestedAccuracyLevel,
  }) async {}

  @override
  Stream<String> get locationUpdates => _updates.stream;

  @override
  Future<GeoPosition> readPosition(
    String locationPath, {
    required DateTime Function() now,
  }) async {
    return nextPosition ??
        GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: 12.0,
          timestamp: now(),
        );
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {
    if (!_updates.isClosed) {
      await _updates.close();
    }
  }

  void emitLocation(String path) => _updates.add(path);
}

void main() {
  group('GeoClueLocationProvider — non-finite read is skipped at ingest', () {
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

    test(
      'skips a NaN-latitude read — does not emit, does not error the stream',
      () async {
        final emitted = <GeoPosition>[];
        final errors = <Object>[];
        provider.positions.listen(emitted.add, onError: errors.add);

        await provider.start();
        session.nextPosition = GeoPosition(
          latitude: double.nan,
          longitude: 136.88,
          accuracy: 12.0,
          timestamp: DateTime(2026, 3, 13, 12, 0),
        );
        session.emitLocation('/org/freedesktop/GeoClue2/Location/1');
        await Future<void>.delayed(Duration.zero);

        expect(
          emitted,
          isEmpty,
          reason:
              'a non-finite coordinate must be skipped — it must never reach '
              'a map boundary',
        );
        expect(
          errors,
          isEmpty,
          reason:
              'skipped SILENTLY — surfacing an error here would flip the '
              'LocationBloc into its error state on one bad fix',
        );
      },
    );

    test('skips a +infinity-longitude read', () async {
      final emitted = <GeoPosition>[];
      final errors = <Object>[];
      provider.positions.listen(emitted.add, onError: errors.add);

      await provider.start();
      session.nextPosition = GeoPosition(
        latitude: 35.17,
        longitude: double.infinity,
        accuracy: 12.0,
        timestamp: DateTime(2026, 3, 13, 12, 0),
      );
      session.emitLocation('/org/freedesktop/GeoClue2/Location/2');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, isEmpty);
      expect(errors, isEmpty);
    });

    test('emits a finite read normally (guard is non-destructive)', () async {
      final emitted = <GeoPosition>[];
      provider.positions.listen(emitted.add);

      await provider.start();
      session.nextPosition = GeoPosition(
        latitude: 35.6895,
        longitude: 139.6917,
        accuracy: 25.0,
        timestamp: DateTime(2026, 3, 13, 12, 0),
      );
      session.emitLocation('/org/freedesktop/GeoClue2/Location/3');
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(1));
      expect(emitted.single.latitude, 35.6895);
      expect(emitted.single.longitude, 139.6917);
    });

    test(
      'a finite coordinate with UNKNOWN (NaN) accuracy is NOT skipped',
      () async {
        final emitted = <GeoPosition>[];
        provider.positions.listen(emitted.add);

        await provider.start();
        session.nextPosition = GeoPosition(
          latitude: 35.17,
          longitude: 136.88,
          accuracy: double.nan,
          timestamp: DateTime(2026, 3, 13, 12, 0),
        );
        session.emitLocation('/org/freedesktop/GeoClue2/Location/4');
        await Future<void>.delayed(Duration.zero);

        expect(
          emitted,
          hasLength(1),
          reason:
              'an unknown accuracy must not drop a valid coordinate — it '
              'degrades downstream (isNavigationGrade is false) instead',
        );
        expect(emitted.single.latitude.isFinite, isTrue);
        expect(emitted.single.longitude.isFinite, isTrue);
        expect(emitted.single.accuracy.isNaN, isTrue);
      },
    );
  });
}
