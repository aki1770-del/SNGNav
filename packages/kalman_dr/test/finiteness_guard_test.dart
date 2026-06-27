/// Finiteness-guard tests (L3 defense-in-depth) — a degraded-GPS NaN/±inf must
/// neither poison the Kalman fused state nor reach the output stream.
///
/// Two seams are exercised:
///   1. KalmanFilter internals — a non-finite accuracy must not turn the
///      covariance / fused position NaN (_diagFromAccuracy floor + _invertMat
///      non-finite-determinant rejection).
///   2. DeadReckoningProvider ingest guard — a non-finite latitude/longitude is
///      dropped before it is forwarded or fused (both linear AND kalman modes),
///      while a valid coordinate with an unknown accuracy is preserved.
///
/// These are the source/amplification layers beneath the LocationBloc chokepoint
/// guard: on the live GeoClue path a non-finite coordinate would otherwise reach
/// flutter_map, which on 8.2.2 SILENTLY projects it to garbage (teleporting the
/// dot, with no throw) — the exact compound-failure (Maps+GPS) scenario.
library;

import 'dart:async';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

/// Controllable inner GPS source.
class _MockInner implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }

  void emit(GeoPosition p) => _controller.add(p);
}

final _t0 = DateTime(2026, 3, 1, 12, 0, 0);

GeoPosition _fix({
  double latitude = 35.17,
  double longitude = 136.88,
  double accuracy = 5.0,
  double speed = 11.0,
  double heading = 90.0,
  DateTime? timestamp,
}) =>
    GeoPosition(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      speed: speed,
      heading: heading,
      timestamp: timestamp ?? _t0,
    );

DeadReckoningProvider _provider(_MockInner inner, DeadReckoningMode mode) =>
    DeadReckoningProvider(
      inner: inner,
      mode: mode,
      // Long timeouts so dead reckoning never kicks in during these short
      // synchronous-ish tests (we are testing ingest, not extrapolation).
      gpsTimeout: const Duration(seconds: 30),
      extrapolationInterval: const Duration(seconds: 30),
    );

void main() {
  group('KalmanFilter — a non-finite accuracy must not poison the fused state',
      () {
    test(
        'NaN accuracy on the FIRST fix keeps the state + covariance finite '
        '(_diagFromAccuracy floor)', () {
      final kf = KalmanFilter();
      kf.update(
        lat: 35.17,
        lon: 136.88,
        speed: 11.0,
        heading: 90.0,
        accuracy: double.nan,
        timestamp: _t0,
      );

      expect(kf.isInitialized, isTrue);
      expect(kf.state.lat, closeTo(35.17, 1e-9));
      expect(kf.state.lon, closeTo(136.88, 1e-9));
      expect(kf.state.lat.isFinite, isTrue);
      expect(kf.state.lon.isFinite, isTrue);
      // accuracyMetres derives from the covariance P; if _diagFromAccuracy let
      // a NaN through, P — and therefore this — would be NaN.
      expect(
        kf.accuracyMetres.isFinite,
        isTrue,
        reason: 'a NaN accuracy must floor to a finite covariance, not poison P',
      );
    });

    test(
        '+infinity accuracy on the FIRST fix keeps the state + covariance finite',
        () {
      final kf = KalmanFilter();
      kf.update(
        lat: 35.17,
        lon: 136.88,
        speed: 11.0,
        heading: 90.0,
        accuracy: double.infinity,
        timestamp: _t0,
      );

      expect(kf.state.lat.isFinite, isTrue);
      expect(kf.state.lon.isFinite, isTrue);
      expect(kf.accuracyMetres.isFinite, isTrue);
    });

    test(
        'NaN accuracy on an UPDATE does not produce a NaN fused position '
        '(_invertMat rejects a non-finite determinant)', () {
      final kf = KalmanFilter();
      // Initialise with a GOOD finite accuracy so _diagFromAccuracy is NOT the
      // thing under test here — this isolates the _invertMat singular guard.
      kf.update(
        lat: 35.17,
        lon: 136.88,
        speed: 11.0,
        heading: 90.0,
        accuracy: 5.0,
        timestamp: _t0,
      );
      expect(kf.state.lat, closeTo(35.17, 1e-9));

      // A poisoned measurement: valid coordinate, NaN accuracy -> NaN measurement
      // noise R -> NaN innovation covariance S -> NaN determinant.
      kf.update(
        lat: 35.18,
        lon: 136.89,
        speed: 11.0,
        heading: 90.0,
        accuracy: double.nan,
        timestamp: _t0.add(const Duration(seconds: 1)),
      );

      expect(
        kf.state.lat.isFinite,
        isTrue,
        reason: 'a NaN-accuracy update must not poison the fused latitude',
      );
      expect(
        kf.state.lon.isFinite,
        isTrue,
        reason: 'a NaN-accuracy update must not poison the fused longitude',
      );
      expect(kf.accuracyMetres.isFinite, isTrue);
      // The poisoned update is rejected (non-finite S) -> the prior (finite)
      // state is retained, near the first fix (heading east, so lat barely moves).
      expect(kf.state.lat, closeTo(35.17, 0.05));
    });

    test('valid finite updates still fuse normally (hardening is non-destructive)',
        () {
      final kf = KalmanFilter();
      kf.update(
        lat: 35.17,
        lon: 136.88,
        speed: 11.0,
        heading: 90.0,
        accuracy: 5.0,
        timestamp: _t0,
      );
      kf.update(
        lat: 35.17,
        lon: 136.90,
        speed: 11.0,
        heading: 90.0,
        accuracy: 3.0,
        timestamp: _t0.add(const Duration(seconds: 1)),
      );

      expect(kf.isInitialized, isTrue);
      expect(kf.state.lat.isFinite, isTrue);
      expect(kf.state.lon.isFinite, isTrue);
      // Heading east (90°) + the eastward second fix -> longitude advances.
      expect(kf.state.lon, greaterThan(136.88));
    });
  });

  group('DeadReckoningProvider — ingest guard drops a non-finite coordinate',
      () {
    test('kalman mode: a NaN-latitude fix is dropped, not emitted or fused',
        () async {
      final inner = _MockInner();
      final provider = _provider(inner, DeadReckoningMode.kalman);
      addTearDown(provider.dispose);
      await provider.start();

      final emitted = <GeoPosition>[];
      final sub = provider.positions.listen(emitted.add);
      addTearDown(sub.cancel);

      inner.emit(_fix()); // good fix
      await Future<void>.delayed(const Duration(milliseconds: 50));
      inner.emit(_fix(latitude: double.nan)); // poison
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        emitted.length,
        1,
        reason: 'only the good fix is emitted; the NaN fix is dropped at ingest',
      );
      expect(
        emitted.single.latitude.isFinite && emitted.single.longitude.isFinite,
        isTrue,
      );
    });

    test('linear mode: a +infinity-longitude fix is dropped, not forwarded',
        () async {
      final inner = _MockInner();
      final provider = _provider(inner, DeadReckoningMode.linear);
      addTearDown(provider.dispose);
      await provider.start();

      final emitted = <GeoPosition>[];
      final sub = provider.positions.listen(emitted.add);
      addTearDown(sub.cancel);

      final good = _fix();
      inner.emit(good);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      inner.emit(_fix(longitude: double.infinity)); // poison
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        emitted.length,
        1,
        reason: 'linear mode forwards raw; the guard must STILL drop the poison '
            '(a kalman-only guard at the filter-feed would not cover linear mode)',
      );
      expect(emitted.single, good);
    });

    test(
        'a valid coordinate with UNKNOWN (NaN) accuracy is NOT dropped — '
        'forwarded raw, no valid data lost', () async {
      final inner = _MockInner();
      final provider = _provider(inner, DeadReckoningMode.kalman);
      addTearDown(provider.dispose);
      await provider.start();

      final emitted = <GeoPosition>[];
      final sub = provider.positions.listen(emitted.add);
      addTearDown(sub.cancel);

      inner.emit(_fix(accuracy: double.nan)); // valid coordinate, unknown accuracy
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        emitted.length,
        1,
        reason: 'an unknown accuracy must not drop a valid coordinate',
      );
      expect(
        emitted.single.latitude.isFinite && emitted.single.longitude.isFinite,
        isTrue,
      );
      expect(
        emitted.single.accuracy.isNaN,
        isTrue,
        reason: 'forwarded raw (not filter-fused) so accuracy stays the '
            'unknown sentinel; it never scales the Kalman noise',
      );
    });
  });

  // -------------------------------------------------------------------------
  // DOES-NOT-MASK (the load-bearing property). A SUSTAINED non-finite stream
  // must NOT reset the GPS watchdog and masquerade as a live GPS fix. The L3
  // ingest guard drops the garbage BEFORE `_resetGpsWatchdog`, so the watchdog
  // is invisible to the stream and AGES to GPS-loss: DEAD RECKONING TAKES OVER,
  // and DR then honestly ages to the 500m safety cap → the
  // DeadReckoningAccuracyExceededException terminal "position unavailable"
  // signal HER sees, rather than a dead GPS held forever as a confident dot.
  //
  // OBSERVATION-grade (OPS-066): asserts the observable downstream STATES
  // (DR active; the terminal error on the stream) after the sustained garbage,
  // not merely "the guard returned early".
  //
  // Both FAIL if the ingest guard's drop were moved AFTER `_resetGpsWatchdog`
  // (the garbage would keep rearming the watchdog at 50ms, the 200ms watchdog
  // would never fire, DR would never take over) — verified by mutation.
  // -------------------------------------------------------------------------
  group('DeadReckoningProvider — sustained garbage does NOT mask as live GPS',
      () {
    test(
        'sustained NaN/Inf stream → GPS watchdog ages to DR takeover '
        '(watchdog not reset by garbage)', () async {
      final inner = _MockInner();
      final provider = DeadReckoningProvider(
        inner: inner,
        mode: DeadReckoningMode.linear,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 80),
      );
      addTearDown(provider.dispose);
      await provider.start();

      final emitted = <GeoPosition>[];
      final sub = provider.positions.listen(emitted.add);
      addTearDown(sub.cancel);

      inner.emit(_fix()); // last good LIVE fix (speed/heading → can extrapolate)
      // SUSTAINED garbage every 50ms — faster than the 200ms watchdog. With the
      // guard correctly BEFORE the reset these are invisible to the watchdog.
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        inner.emit(
            i.isEven ? _fix(latitude: double.nan) : _fix(longitude: double.infinity));
      }

      expect(
        provider.isDrActive,
        isTrue,
        reason: 'DR must take over — the sustained garbage must NOT keep the '
            'GPS watchdog alive (that would mask dead GPS as a live fix)',
      );
      // No garbage ever reached the output stream, and at least one
      // DR-extrapolated fix was emitted after the last good one.
      expect(emitted.length, greaterThanOrEqualTo(2));
      for (final p in emitted) {
        expect(p.latitude.isFinite && p.longitude.isFinite, isTrue,
            reason: 'a non-finite coordinate must never reach the stream');
      }
    });

    test(
        'DR ages to the 500m safety cap → "position unavailable", '
        'even under a sustained NaN stream', () async {
      final inner = _MockInner();
      final provider = DeadReckoningProvider(
        inner: inner,
        mode: DeadReckoningMode.linear,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 80),
      );
      addTearDown(provider.dispose);
      await provider.start();

      final errors = <Object>[];
      final sub = provider.positions.listen((_) {}, onError: errors.add);
      addTearDown(sub.cancel);

      // A valid but already near-cap fix (accuracy 499.5m): once DR takes over,
      // the very first extrapolation tick crosses the 500m cap — the honest
      // terminal "POSITION UNAVAILABLE" signal, reached only because the
      // sustained garbage did NOT keep the GPS watchdog alive.
      inner.emit(_fix(accuracy: 499.5));
      for (var i = 0; i < 12; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        inner.emit(
            i.isEven ? _fix(latitude: double.nan) : _fix(longitude: double.infinity));
      }

      expect(
        errors,
        isNotEmpty,
        reason: 'the dead-reckoning 500m cap must surface position-unavailable; '
            'a sustained garbage stream must not suppress it',
      );
      expect(errors.first, isA<DeadReckoningAccuracyExceededException>());
    });
  });
}
