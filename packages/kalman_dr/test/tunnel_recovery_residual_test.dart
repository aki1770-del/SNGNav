/// Tunnel-recovery residual — what does the FIRST position after a GPS outage
/// actually tell a consumer holding only the object?
///
/// `position_provenance_test.dart` established that an *extrapolated* position
/// says so. This suite covers the emit immediately after that: the one where
/// GPS has just come back, dead reckoning has just stopped, and the filter
/// produces its first re-anchored estimate.
///
/// That estimate is not the measurement. It is the measurement blended with a
/// prediction that has been running blind for the whole outage, and on a short
/// tunnel the prediction still dominates it. Every discriminator the library
/// offers reads clean on it — `isDrActive` is false, `source` is `fused`,
/// `containsMeasurement` is true, `isNavigationGrade` and `isHighAccuracy` both
/// pass — and `extrapolatedFor`, the one field whose entire job is to say how
/// far the estimate has run from evidence, is stamped `Duration.zero` in the
/// same breath.
///
/// She is at a tunnel portal in snow, choosing a lane. The dot is confident and
/// it is in the wrong place.
///
/// Safety: ASIL-QM — display only.
library;

import 'dart:async';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

class _MockGps implements LocationProvider {
  final _c = StreamController<GeoPosition>.broadcast();

  @override
  Stream<GeoPosition> get positions => _c.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _c.close();

  void emit(GeoPosition p) => _c.add(p);
}

const _mPerDegLat = 111320.0;

void main() {
  // -------------------------------------------------------------------------
  // The outage must survive the re-anchoring emit.
  // -------------------------------------------------------------------------

  group('the first fix after a GPS outage', () {
    late _MockGps gps;
    late DeadReckoningProvider provider;
    late List<GeoPosition> received;
    late StreamSubscription<GeoPosition> sub;

    setUp(() async {
      gps = _MockGps();
      provider = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      await provider.start();
      received = <GeoPosition>[];
      sub = provider.positions.listen(received.add, onError: (Object _) {});
    });

    tearDown(() async {
      await sub.cancel();
      await provider.dispose();
    });

    /// Four clean approach fixes, driving north at ~50 km/h.
    Future<DateTime> approach() async {
      final t0 = DateTime.now().toUtc();
      for (var i = 0; i < 4; i++) {
        gps.emit(
          GeoPosition(
            latitude: 35.1709 + i * 13.89 / _mPerDegLat,
            longitude: 136.8815,
            accuracy: 8.0,
            speed: 13.89,
            heading: 0.0,
            timestamp: t0.add(Duration(milliseconds: i * 100)),
            source: PositionSource.measured,
            extrapolatedFor: Duration.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      return t0;
    }

    test('discloses how long the estimate ran without a sensor', () async {
      final t0 = await approach();

      // Tunnel. Dead reckoning takes over and runs blind.
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(
        received.where((p) => p.isDeadReckoned),
        isNotEmpty,
        reason: 'the outage must actually have started dead reckoning',
      );
      final lastInvented = received.lastWhere((p) => p.isDeadReckoned);
      expect(
        lastInvented.extrapolatedFor!,
        greaterThan(const Duration(milliseconds: 400)),
        reason: 'the invented positions do disclose their age — that part works',
      );

      // Far portal: GPS re-acquires. Inside the tunnel the road curved east and
      // she slowed to 5 m/s, which a constant-velocity model cannot know.
      gps.emit(
        GeoPosition(
          latitude: 35.1709 + (3 * 13.89 + 0.8 * 5.0 * 0.342) / _mPerDegLat,
          longitude: 136.8815 + (0.8 * 5.0 * 0.940) / (_mPerDegLat * 0.8187),
          accuracy: 12.0,
          speed: 5.0,
          heading: 70.0,
          timestamp: t0.add(const Duration(milliseconds: 1100)),
          source: PositionSource.measured,
          extrapolatedFor: Duration.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final reanchored = received.last;

      // These are correct today and must stay correct: a real reading did
      // contribute, so the position is `fused` and not `deadReckoned`.
      expect(reanchored.source, PositionSource.fused);
      expect(reanchored.containsMeasurement, isTrue);
      expect(reanchored.isDeadReckoned, isFalse);
      expect(provider.isDrActive, isFalse);

      // This is the defect. The estimate has just spent the whole outage
      // running on prediction alone, and a single 12 m reading does not undo
      // that in one update — yet the field that exists to carry exactly this
      // fact is reset to zero, so nothing on the object distinguishes this
      // emit from a steady-state one.
      expect(
        reanchored.extrapolatedFor,
        isNotNull,
        reason: 'the re-anchoring emit must state its own residual',
      );
      expect(
        reanchored.extrapolatedFor!,
        greaterThanOrEqualTo(const Duration(milliseconds: 700)),
        reason:
            'the estimate ran ~800 ms without a sensor; the first fix back '
            'blends that prediction in, and a consumer holding only the '
            'object has no other way to learn it',
      );
    });

    test('survives a recovery that arrives without speed or heading first',
        () async {
      // The far portal often gives back a coarse fix before a full one. That
      // first fix has no speed/heading, so it is forwarded raw and never
      // reaches the filter — `_stopDr()` has already run by then. Keying the
      // disclosure off `isDrActive` would lose the outage here; keying it off
      // the last accepted reading does not.
      final t0 = await approach();
      await Future<void>.delayed(const Duration(milliseconds: 800));
      expect(received.where((p) => p.isDeadReckoned), isNotEmpty);

      gps.emit(
        GeoPosition(
          latitude: 35.1720,
          longitude: 136.8820,
          accuracy: 15.0,
          timestamp: t0.add(const Duration(milliseconds: 1100)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        received.last.source,
        PositionSource.unknown,
        reason: 'the raw fix is forwarded exactly as the inner declared it',
      );

      gps.emit(
        GeoPosition(
          latitude: 35.1721,
          longitude: 136.8821,
          accuracy: 12.0,
          speed: 5.0,
          heading: 70.0,
          timestamp: t0.add(const Duration(milliseconds: 1200)),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(received.last.source, PositionSource.fused);
      expect(
        received.last.extrapolatedFor!,
        greaterThanOrEqualTo(const Duration(milliseconds: 700)),
        reason: 'the outage is still unresolved and must still be stated',
      );
    });

    test('steady-state fused output states the ordinary inter-fix gap',
        () async {
      // 0.5.1 stamped Duration.zero here and a gated 0.5.2 candidate would
      // have kept doing so. Both are a claim the object cannot support: the
      // estimate really has run ~100 ms without evidence, and saying "zero"
      // is the same class of overstatement this package exists to refute.
      // The bound that matters is that it stays SMALL and ordered, not that
      // it is zero.
      await approach();

      final fused =
          received.where((p) => p.source == PositionSource.fused).toList();
      expect(fused, isNotEmpty);
      for (final p in fused) {
        expect(p.extrapolatedFor, isNotNull);
        expect(
          p.extrapolatedFor!,
          lessThan(const Duration(milliseconds: 400)),
          reason: 'no outage happened; the gap is ordinary inter-fix spacing',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // Linear mode is not touched by any of this.
  // -------------------------------------------------------------------------

  test('linear-mode recovery forwards the inner object byte for byte',
      () async {
    // There is no fusion in linear mode, so a recovered fix carries no residual
    // prediction and there is nothing to disclose. The provider must keep
    // forwarding the inner provider's own object untouched — rewriting it here
    // would be this library asserting something about a coordinate it did not
    // produce.
    final gps = _MockGps();
    final provider = DeadReckoningProvider(
      inner: gps,
      gpsTimeout: const Duration(milliseconds: 200),
      extrapolationInterval: const Duration(milliseconds: 100),
    );
    await provider.start();
    final received = <GeoPosition>[];
    final sub = provider.positions.listen(received.add, onError: (Object _) {});

    final t0 = DateTime.now().toUtc();
    gps.emit(
      GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 8.0,
        speed: 13.89,
        heading: 0.0,
        timestamp: t0,
        source: PositionSource.measured,
        extrapolatedFor: Duration.zero,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(received.where((p) => p.isDeadReckoned), isNotEmpty);

    final back = GeoPosition(
      latitude: 35.1730,
      longitude: 136.8815,
      accuracy: 6.0,
      speed: 13.89,
      heading: 0.0,
      timestamp: t0.add(const Duration(seconds: 1)),
      source: PositionSource.measured,
      extrapolatedFor: Duration.zero,
    );
    gps.emit(back);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(received.last, equals(back));
    expect(received.last.extrapolatedFor, Duration.zero);

    await sub.cancel();
    await provider.dispose();
  });

  // -------------------------------------------------------------------------
  // The band the 200 ms measurement never reached.
  // -------------------------------------------------------------------------

  group('at the SHIPPED DEFAULT gpsTimeout of 3 s', () {
    // The disclosure was first measured at `gpsTimeout: 200ms` — 15x tighter
    // than the default `dead_reckoning_provider_test.dart` locks — where every
    // outage band exceeds the timeout and every band therefore looked
    // disclosed. At the shipped default, gaps shorter than 3 s never start
    // dead reckoning at all, and a threshold keyed to `gpsTimeout` reported
    // zero across the whole band: measured, a 2 s gap put the emitted
    // coordinate 18.1 m from truth against a stated 5.60 m radius.
    //
    // These run with NO gpsTimeout argument on purpose. If the default moves,
    // this suite must move with it.

    /// Drives four approach fixes, waits [gap], then delivers one recovery
    /// fix, and returns the re-anchored `fused` emit.
    Future<GeoPosition> recoverAfter(Duration gap) async {
      final gps = _MockGps();
      final provider = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.kalman,
      );
      await provider.start();
      final received = <GeoPosition>[];
      final sub =
          provider.positions.listen(received.add, onError: (Object _) {});

      final t0 = DateTime.now().toUtc();
      for (var i = 0; i < 4; i++) {
        gps.emit(
          GeoPosition(
            latitude: 35.1709 + i * 13.89 * 0.5 / _mPerDegLat,
            longitude: 136.8815,
            accuracy: 8.0,
            speed: 13.89,
            heading: 0.0,
            timestamp: t0.add(Duration(milliseconds: i * 500)),
            source: PositionSource.measured,
            extrapolatedFor: Duration.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }

      await Future<void>.delayed(gap);

      gps.emit(
        GeoPosition(
          latitude: 35.1709 + (3 * 13.89 * 0.5 + 5.0 * 0.342) / _mPerDegLat,
          longitude: 136.8815 + (5.0 * 0.940) / (_mPerDegLat * 0.8187),
          accuracy: 12.0,
          speed: 5.0,
          heading: 70.0,
          timestamp: t0.add(Duration(milliseconds: 1500 + gap.inMilliseconds)),
          source: PositionSource.measured,
          extrapolatedFor: Duration.zero,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));

      final re = received.lastWhere((p) => p.source == PositionSource.fused);
      await sub.cancel();
      await provider.dispose();
      return re;
    }

    test('a 2 s gap — below the timeout, so no DR ever ran — is still stated',
        () async {
      final re = await recoverAfter(const Duration(seconds: 2));
      expect(
        re.extrapolatedFor,
        isNotNull,
        reason: 'the estimate ran 2 s without evidence and must say so',
      );
      expect(
        re.extrapolatedFor!,
        greaterThanOrEqualTo(const Duration(milliseconds: 1800)),
        reason:
            'this is the band a gpsTimeout-keyed threshold silenced: dead '
            'reckoning never started, so `isDeadReckoned` is false and '
            '`isDrActive` is false, and this field was the only thing left '
            'that could disclose the gap',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('a 1 s gap is stated too', () async {
      final re = await recoverAfter(const Duration(seconds: 1));
      expect(
        re.extrapolatedFor!,
        greaterThanOrEqualTo(const Duration(milliseconds: 800)),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('the disclosure grows with the gap and does not depend on gpsTimeout',
        () async {
      // Monotonicity is the property that makes the number usable. Under the
      // threshold it was not monotonic — it was 0, 0, 0, then jumped.
      final short = await recoverAfter(const Duration(milliseconds: 500));
      final mid = await recoverAfter(const Duration(seconds: 2));
      final long = await recoverAfter(const Duration(seconds: 4));
      expect(short.extrapolatedFor!, lessThan(mid.extrapolatedFor!));
      expect(mid.extrapolatedFor!, lessThan(long.extrapolatedFor!));
      // And the sub-timeout bands are not zero.
      expect(short.extrapolatedFor!, greaterThan(Duration.zero));
      expect(mid.extrapolatedFor!, greaterThan(Duration.zero));
    }, timeout: const Timeout(Duration(seconds: 60)));
  });

  // -------------------------------------------------------------------------
  // A confidence the sensor never supported.
  // -------------------------------------------------------------------------

  group('an accuracy the sensor never stated', () {
    // `geolocator` returns 0.0 when `Location.hasAccuracy()` is false,
    // GeoClue2 can report 0, some providers use -1, and a sensor fault can
    // deliver NaN or infinity. None of those is a precision claim, and 0.5.1
    // read them as one.

    /// Runs four Kalman-mode fixes at [accuracy] and returns the radius the
    /// last `fused` emit reported.
    Future<double> lastFusedAccuracyFor(double accuracy) async {
      final gps = _MockGps();
      final provider = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 500),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      await provider.start();
      final received = <GeoPosition>[];
      final sub =
          provider.positions.listen(received.add, onError: (Object _) {});

      final t0 = DateTime.now().toUtc();
      for (var i = 0; i < 4; i++) {
        gps.emit(
          GeoPosition(
            latitude: 35.1709 + i * 13.89 / _mPerDegLat,
            longitude: 136.8815,
            accuracy: accuracy,
            speed: 13.89,
            heading: 0.0,
            timestamp: t0.add(Duration(milliseconds: i * 100)),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }

      final fused =
          received.where((p) => p.source == PositionSource.fused).toList();
      expect(fused, isNotEmpty);
      final result = fused.last.accuracy;
      await sub.cancel();
      await provider.dispose();
      return result;
    }

    // Which sentinels actually reach the filter THROUGH the provider is not
    // all of them, and that is measured, not assumed:
    // `dead_reckoning_provider.dart` gates the filter feed on
    // `pos.accuracy.isFinite`, so a NaN or infinity fix is forwarded raw as
    // `unknown` and never becomes `fused`. `0.0` and `-1.0` are finite, pass
    // that gate, and land in the filter — which is exactly why they were the
    // dangerous pair. The filter-level tests below cover NaN and infinity for
    // consumers who drive `KalmanFilter` directly.
    test('a sentinel does not come back as a fix no GPS can deliver', () async {
      // Measured on the 0.5.1 tree: four fixes at `accuracy: 0` reported
      // 3.8 nanometres, and `isHighAccuracy` passed on it. The failure is not
      // that the number is small; it is that a sensor which said nothing was
      // read as having said something excellent.
      for (final sentinel in <double>[0.0, -1.0]) {
        final reported = await lastFusedAccuracyFor(sentinel);
        expect(
          reported,
          greaterThan(1.0),
          reason: 'accuracy \$sentinel means "not stated"; a radius of '
              '\$reported m is a confidence the sensor never gave us',
        );
        expect(reported.isFinite, isTrue);
      }
    });

    test('every sentinel convention that reaches the filter agrees', () async {
      // 0 and -1 are two spellings of "unavailable". They must not produce two
      // different confidences — on 0.5.1 they produced 3.8e-9 m and 0.76 m.
      expect(
        await lastFusedAccuracyFor(-1.0),
        closeTo(await lastFusedAccuracyFor(0.0), 1e-9),
        reason: 'accuracy -1 is the same statement as accuracy 0',
      );
    });

    test('NaN and infinity are the same statement at the filter boundary', () {
      // These never arrive through `DeadReckoningProvider` (see the note
      // above), but `KalmanFilter` is public API and a direct consumer can
      // hand them straight in.
      final t = DateTime.utc(2026, 3, 1, 12, 0, 0);
      double settle(double accuracy) {
        final kf = KalmanFilter();
        for (var i = 0; i < 8; i++) {
          kf.update(
            lat: 35.1709,
            lon: 136.8815,
            speed: 13.89,
            heading: 0.0,
            accuracy: accuracy,
            timestamp: t.add(Duration(seconds: i)),
          );
        }
        return kf.accuracyMetres;
      }

      final zero = settle(0.0);
      expect(zero, greaterThan(1.0));
      for (final other in <double>[-1.0, double.nan, double.infinity]) {
        expect(
          settle(other),
          closeTo(zero, 1e-9),
          reason: 'accuracy \$other is the same statement as accuracy 0',
        );
      }
    });

    test('a stated sub-metre accuracy is honoured, not censored', () async {
      // The regression this locks: fixing the sentinel by flooring the whole
      // band at 1 m would degrade a genuine RTK source 16.7x. 0.5.1 reported
      // 0.063 m for an inbound 0.05 m, and that number was truthful.
      final rtk = await lastFusedAccuracyFor(0.05);
      expect(
        rtk,
        lessThan(0.5),
        reason: 'an RTK receiver that stated 0.05 m must not be told it is '
            'a 1 m fix; got $rtk m',
      );
      expect(
        rtk,
        greaterThan(0.0),
        reason: 'and it must still be strictly positive',
      );

      // Ordering must survive too: better stated accuracy, smaller radius.
      final metre = await lastFusedAccuracyFor(1.0);
      final ten = await lastFusedAccuracyFor(10.0);
      expect(rtk, lessThan(metre));
      expect(metre, lessThan(ten));
    });

    test('does not let the filter discard a later measurement in silence',
        () {
      // Two zero-accuracy fixes drove P to exactly zero on 0.5.1. A third then
      // made S = P + R singular, `_invertMat` returned null, `update()`
      // returned early, and `DeadReckoningProvider` emitted the untouched
      // state as `fused` — a coordinate no sensor contributed to, wearing the
      // label that says one did.
      final t = DateTime.utc(2026, 3, 1, 12, 0, 0);
      final kf = KalmanFilter();
      kf.update(
        lat: 35.1709,
        lon: 136.8815,
        speed: 13.89,
        heading: 0.0,
        accuracy: 0.0,
        timestamp: t,
      );
      kf.update(
        lat: 35.1710,
        lon: 136.8815,
        speed: 13.89,
        heading: 0.0,
        accuracy: 0.0,
        timestamp: t.add(const Duration(seconds: 1)),
      );
      final before = kf.state;

      // A third fix, same timestamp as the second, 92 km away.
      kf.update(
        lat: 35.9999,
        lon: 136.9999,
        speed: 13.89,
        heading: 0.0,
        accuracy: 0.0,
        timestamp: t.add(const Duration(seconds: 1)),
      );
      final after = kf.state;

      expect(
        after.lat == before.lat && after.lon == before.lon,
        isFalse,
        reason:
            'the measurement was discarded without a trace; the state is '
            'unchanged and the provider will still label it `fused`',
      );
      expect(
        kf.accuracyMetres,
        greaterThan(0.0),
        reason: 'a filter reporting 0 m has stopped modelling uncertainty '
            'and can no longer accept a correction',
      );
    });

    test('a NaN accuracy does not silently drop the reading', () {
      // Measured on 0.5.1: R went NaN, S went NaN, `_invertMat` returned null,
      // and the fix 111 km away was dropped with the state left untouched.
      final t = DateTime.utc(2026, 3, 1, 12, 0, 0);
      final kf = KalmanFilter();
      kf.update(
        lat: 35.1709,
        lon: 136.8815,
        speed: 13.89,
        heading: 0.0,
        accuracy: 5.0,
        timestamp: t,
      );
      kf.update(
        lat: 36.1709,
        lon: 136.8815,
        speed: 13.89,
        heading: 0.0,
        accuracy: double.nan,
        timestamp: t.add(const Duration(seconds: 1)),
      );
      expect(
        kf.state.lat,
        greaterThan(35.1709),
        reason: 'the reading moved a full degree north and must have moved '
            'the estimate at all',
      );
      expect(kf.accuracyMetres.isFinite, isTrue);
    });

    test('the first fix and every later fix agree about a sentinel', () {
      // The disagreement 0.5.1 shipped: `_diagFromAccuracy` floored the init
      // at 1 m, `update()` floored nothing, and the gap compounded. Same
      // sentinel through either path must produce the same uncertainty.
      final t = DateTime.utc(2026, 3, 1, 12, 0, 0);

      final viaInit = KalmanFilter()
        ..update(
          lat: 35.1709,
          lon: 136.8815,
          speed: 13.89,
          heading: 0.0,
          accuracy: 0.0,
          timestamp: t,
        );

      final viaUpdate = KalmanFilter()
        ..update(
          lat: 35.1709,
          lon: 136.8815,
          speed: 13.89,
          heading: 0.0,
          accuracy: 5.0,
          timestamp: t,
        );
      // Drive it with sentinels until it settles on its own answer.
      for (var i = 1; i <= 40; i++) {
        viaUpdate.update(
          lat: 35.1709,
          lon: 136.8815,
          speed: 13.89,
          heading: 0.0,
          accuracy: 0.0,
          timestamp: t.add(Duration(seconds: i)),
        );
      }
      expect(
        viaUpdate.accuracyMetres,
        greaterThan(1.0),
        reason: 'the update path must not converge below what the init path '
            'is willing to claim for the same sentinel',
      );
      expect(viaInit.accuracyMetres, greaterThan(1.0));
    });
  });
}
