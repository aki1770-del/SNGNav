/// LocationBloc finiteness guard tests — the primary non-finite-coordinate guard.
///
/// Scenario: a driver in a degraded-GPS situation (e.g. Google Maps unavailable
/// and the GPS fix going bad). On the live GeoClue / Kalman dead-reckoning path
/// a non-finite latitude or longitude (NaN / +/-Infinity) can be emitted.
/// flutter_map 8.2.2 SILENTLY projects a non-finite coordinate to garbage (no
/// throw — verified at map_controller_impl.dart moveRaw: the
/// `newCamera.center == camera.center` early-out is false for NaN, so the NaN
/// center is committed), teleporting the position dot and wrecking the follow
/// camera; flutter_map 8.3.0 throws outright. The guard at the chokepoint
/// LocationBloc._onPositionReceived fixes BOTH, version-independently, by
/// dropping a poisoned fix and retaining the last good one.
///
/// These tests are render-grade: on flutter_map 8.2.2 a NaN does NOT throw, so
/// we assert the EMITTED position / map camera center stays FINITE after a NaN
/// fix (the guard dropped it) — not merely "no exception".
///
/// Every test here fails without the guard.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/bloc/bloc.dart';

// ---------------------------------------------------------------------------
// Mock provider — controllable stream (mirrors location_bloc_test.dart)
// ---------------------------------------------------------------------------
class MockLocationProvider implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();
  bool started = false;
  bool stopped = false;
  bool disposed = false;

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> stop() async => stopped = true;

  @override
  Future<void> dispose() async {
    disposed = true;
    await _controller.close();
  }

  void emitPosition(GeoPosition pos) => _controller.add(pos);
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
final _goodFix = GeoPosition(
  latitude: 35.1709, // Nagoya
  longitude: 136.8815,
  accuracy: 5.0, // navigation-grade
  timestamp: DateTime(2026, 2, 27, 10, 0),
);

final _goodFix2 = GeoPosition(
  latitude: 35.1720,
  longitude: 136.8830,
  accuracy: 4.0,
  timestamp: DateTime(2026, 2, 27, 10, 2),
);

// NaN-latitude poison. accuracy is finite + navigation-grade so that WITHOUT
// the guard the bloc would emit a `fix` state carrying a non-finite position
// (the bug) — making these tests fail without the guard.
final _nanLat = GeoPosition(
  latitude: double.nan,
  longitude: 136.8815,
  accuracy: 5.0,
  timestamp: DateTime(2026, 2, 27, 10, 1),
);

final _infLng = GeoPosition(
  latitude: 35.1709,
  longitude: double.infinity,
  accuracy: 5.0,
  timestamp: DateTime(2026, 2, 27, 10, 1),
);

final _negInfLat = GeoPosition(
  latitude: double.negativeInfinity,
  longitude: 136.8815,
  accuracy: 5.0,
  timestamp: DateTime(2026, 2, 27, 10, 1),
);

final _nanBoth = GeoPosition(
  latitude: double.nan,
  longitude: double.nan,
  accuracy: 5.0,
  timestamp: DateTime(2026, 2, 27, 10, 1),
);

// Helper: a GeoPosition has a finite, map-placeable coordinate.
bool _isFinitePos(GeoPosition? p) =>
    p != null && p.latitude.isFinite && p.longitude.isFinite;

void main() {
  group('LocationBloc — finiteness guard (degraded-GPS poison)', () {
    late MockLocationProvider provider;

    setUp(() => provider = MockLocationProvider());

    blocTest<LocationBloc, LocationState>(
      'drops a NaN-latitude fix — emits nothing, retains last good position',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _goodFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_nanLat)),
      expect: () => <LocationState>[], // poison dropped — no emit
      verify: (bloc) {
        expect(bloc.state.position, equals(_goodFix));
        expect(_isFinitePos(bloc.state.position), isTrue);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'drops a +Infinity-longitude fix — emits nothing, retains last good',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _goodFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_infLng)),
      expect: () => <LocationState>[],
      verify: (bloc) {
        expect(bloc.state.position, equals(_goodFix));
        expect(_isFinitePos(bloc.state.position), isTrue);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'drops a -Infinity-latitude fix — emits nothing, retains last good',
      build: () => LocationBloc(provider: provider),
      seed: () =>
          LocationState(quality: LocationQuality.fix, position: _goodFix),
      act: (bloc) => bloc.add(LocationPositionReceived(_negInfLat)),
      expect: () => <LocationState>[],
      verify: (bloc) {
        expect(bloc.state.position, equals(_goodFix));
        expect(_isFinitePos(bloc.state.position), isTrue);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'drops poison from acquiring — stays acquiring, no position acquired',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(LocationPositionReceived(_nanBoth)),
      expect: () => <LocationState>[],
      verify: (bloc) {
        expect(bloc.state.quality, equals(LocationQuality.acquiring));
        expect(bloc.state.hasPosition, isFalse);
      },
    );

    blocTest<LocationBloc, LocationState>(
      'NEVER emits a LocationState with a non-finite position '
      '(good -> poison-skipped -> good)',
      build: () => LocationBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        provider.emitPosition(_goodFix);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        provider.emitPosition(_nanLat); // dropped
        await Future<void>.delayed(const Duration(milliseconds: 20));
        provider.emitPosition(_goodFix2);
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      // The NaN fix is absent from the sequence — never emitted.
      expect: () => [
        const LocationState.acquiring(),
        LocationState(quality: LocationQuality.fix, position: _goodFix),
        LocationState(quality: LocationQuality.fix, position: _goodFix2),
      ],
      verify: (bloc) {
        // Render-grade invariant: every position the UI ever saw is finite.
        expect(_isFinitePos(bloc.state.position), isTrue);
      },
    );
  });

  group('LocationBloc — finiteness guard drops NO valid coordinate', () {
    late MockLocationProvider provider;
    setUp(() => provider = MockLocationProvider());

    final zeroZero = GeoPosition(
      latitude: 0.0, // equator / prime meridian — a VALID coordinate
      longitude: 0.0,
      accuracy: 5.0,
      timestamp: DateTime(2026, 2, 27, 10, 0),
    );
    final southWest = GeoPosition(
      latitude: -54.8019, // Ushuaia — negative lat & lng
      longitude: -68.3030,
      accuracy: 5.0,
      timestamp: DateTime(2026, 2, 27, 10, 0),
    );
    final highLat = GeoPosition(
      latitude: 78.2232, // Svalbard — high-latitude pass
      longitude: 15.6267,
      accuracy: 5.0,
      timestamp: DateTime(2026, 2, 27, 10, 0),
    );

    blocTest<LocationBloc, LocationState>(
      'passes a valid 0,0 coordinate (NOT dropped)',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(LocationPositionReceived(zeroZero)),
      expect: () => [
        LocationState(quality: LocationQuality.fix, position: zeroZero),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'passes valid negative coordinates (NOT dropped)',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(LocationPositionReceived(southWest)),
      expect: () => [
        LocationState(quality: LocationQuality.fix, position: southWest),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'passes valid high-latitude coordinates (NOT dropped)',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(LocationPositionReceived(highLat)),
      expect: () => [
        LocationState(quality: LocationQuality.fix, position: highLat),
      ],
    );

    blocTest<LocationBloc, LocationState>(
      'non-finite ACCURACY with finite lat/lon is NOT dropped — treated as '
      'unknown, flows to degraded with a finite, placeable position',
      build: () => LocationBloc(provider: provider),
      seed: () => const LocationState.acquiring(),
      act: (bloc) => bloc.add(
        LocationPositionReceived(
          GeoPosition(
            latitude: 35.1709,
            longitude: 136.8815,
            accuracy: double.nan, // unknown accuracy — NOT a poison
            timestamp: DateTime(2026, 2, 27, 10, 0),
          ),
        ),
      ),
      expect: () => [
        isA<LocationState>()
            .having((s) => s.quality, 'quality', LocationQuality.degraded)
            .having((s) => s.position!.latitude, 'lat', 35.1709)
            .having((s) => s.position!.longitude, 'lng', 136.8815),
      ],
      verify: (bloc) => expect(_isFinitePos(bloc.state.position), isTrue),
    );
  });

  // -------------------------------------------------------------------------
  // Render-grade widget test: the REAL flutter_map follow camera must stay
  // FINITE after a NaN fix routes through the real LocationBloc. The listener
  // below mirrors the production follow-camera path at
  // lib/widgets/snow_scene_scaffold.dart:213-220
  // (CenterChanged(LatLng(pos.latitude, pos.longitude)) -> mapController.move).
  // -------------------------------------------------------------------------
  group('snow_scene follow camera — stays finite after a NaN fix', () {
    testWidgets('a NaN fix does not teleport / corrupt the map camera center', (
      tester,
    ) async {
      final bloc = LocationBloc(provider: MockLocationProvider());
      final mapController = MapController();
      const tokyo = LatLng(35.6812, 139.7671); // initial — distinct from fix

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BlocProvider<LocationBloc>.value(
              value: bloc,
              child: BlocListener<LocationBloc, LocationState>(
                listenWhen: (prev, curr) => curr.hasPosition,
                listener: (context, state) {
                  // Mirrors snow_scene_scaffold.dart follow-camera path.
                  final pos = state.position!;
                  mapController.move(
                    LatLng(pos.latitude, pos.longitude),
                    mapController.camera.zoom,
                  );
                },
                child: FlutterMap(
                  mapController: mapController,
                  options: const MapOptions(
                    initialCenter: tokyo,
                    initialZoom: 13,
                  ),
                  children: const [],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // A GOOD fix moves the camera to Nagoya (the last good position).
      bloc.add(LocationPositionReceived(_goodFix));
      await tester.pump(const Duration(milliseconds: 20));
      expect(mapController.camera.center.latitude, closeTo(35.1709, 0.5));
      expect(mapController.camera.center.longitude, closeTo(136.8815, 0.5));

      // A NaN poison fix — on flutter_map 8.2.2 an unguarded NaN move()
      // silently sets camera.center to NaN (verified). The guard must prevent
      // the bloc from ever emitting it, so the camera never receives it.
      bloc.add(LocationPositionReceived(_nanLat));
      await tester.pump(const Duration(milliseconds: 20));

      // Render-grade assertion: camera center FINITE and held at last good.
      expect(
        mapController.camera.center.latitude.isFinite,
        isTrue,
        reason: 'NaN fix must not corrupt the map camera latitude',
      );
      expect(
        mapController.camera.center.longitude.isFinite,
        isTrue,
        reason: 'NaN fix must not corrupt the map camera longitude',
      );
      expect(
        mapController.camera.center.latitude,
        closeTo(35.1709, 0.5),
        reason: 'camera must hold the last good position',
      );

      // Cleanup: stop cancels the stale watchdog timer; close disposes the
      // provider. Both are driven via pump (not awaited) to avoid a fake-async
      // deadlock inside testWidgets.
      bloc.add(const LocationStopRequested());
      await tester.pump(const Duration(milliseconds: 20));
      unawaited(bloc.close());
      await tester.pump(const Duration(milliseconds: 20));
    });
  });

  // -------------------------------------------------------------------------
  // DOES-NOT-MASK (the load-bearing property). A SUSTAINED non-finite stream
  // must NOT reset the stale watchdog and masquerade as a live fix. The L1
  // drop is placed BEFORE `_resetStaleTimer`, so a garbage stream is invisible
  // to the watchdog and the state correctly AGES to `stale` — the honest "GPS
  // stale — last known position" signal HER already trusts — instead of a dead
  // GPS being held forever as a confident live fix.
  //
  // This is an OBSERVATION-grade test (OPS-066): it does not assert "the guard
  // dropped the fix"; it observes the END STATE the driver sees (`stale`,
  // holding the last good position) after a sustained garbage stream.
  //
  // It FAILS if the drop were moved AFTER `_resetStaleTimer` — the garbage
  // would keep rearming the timer and the fix would never go stale (verified by
  // mutation). The 50ms garbage cadence is 3x faster than the 150ms threshold,
  // so a misplaced guard would never let the watchdog reach its deadline.
  // -------------------------------------------------------------------------
  group('LocationBloc — sustained garbage does NOT mask as a live fix', () {
    late MockLocationProvider provider;
    setUp(() => provider = MockLocationProvider());

    blocTest<LocationBloc, LocationState>(
      'a sustained NaN/Inf stream ages to STALE (watchdog not reset by garbage)',
      build: () => LocationBloc(
        provider: provider,
        staleThreshold: const Duration(milliseconds: 150),
      ),
      act: (bloc) async {
        bloc.add(const LocationStartRequested());
        await Future<void>.delayed(const Duration(milliseconds: 20));
        provider.emitPosition(_goodFix); // the last good LIVE fix
        // A SUSTAINED garbage stream at 50ms cadence — comfortably faster than
        // the 150ms stale threshold. If the drop sat AFTER `_resetStaleTimer`,
        // each of these would rearm the watchdog and `stale` would NEVER fire.
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          provider.emitPosition(i.isEven ? _nanLat : _infLng);
        }
      },
      // Observation: the system aged to `stale` DESPITE the ongoing stream —
      // the garbage was invisible to the watchdog, and the position is held at
      // the last good (finite) fix. The garbage never produced a `fix` emit.
      expect: () => [
        const LocationState.acquiring(),
        LocationState(quality: LocationQuality.fix, position: _goodFix),
        LocationState(quality: LocationQuality.stale, position: _goodFix),
      ],
      verify: (bloc) {
        expect(
          bloc.state.quality,
          LocationQuality.stale,
          reason: 'dead GPS must age to stale, never masquerade as live',
        );
        expect(_isFinitePos(bloc.state.position), isTrue);
      },
    );
  });
}
