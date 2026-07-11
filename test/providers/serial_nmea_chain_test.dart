/// Serial-NMEA → kalman_dr → LocationBloc chain integration tests.
///
/// Drives the FULL real data path with an INJECTED byte source (no hardware,
/// no serial port): canned NMEA bytes → [SerialNmeaLocationProvider] →
/// [DeadReckoningProvider] → [LocationBloc] → [LocationState]. Asserts:
///   1. a fix arrives at the right position;
///   2. stopping the byte feed transitions the chain to dead-reckoning;
///   3. a high-HDOP fix degrades the quality (without DR);
///   4. dead reckoning past the 500 m safety cap reaches the "position
///      unavailable" floor (LocationQuality.error).
///
/// Honest bound: the byte source is injected (a real serial port is NOT opened
/// here — see SerialNmeaLocationProvider.byteSource). DR timings use short
/// (gpsTimeout / extrapolationInterval) durations so the real Timers fire fast.
///
/// Note on feeding: bytes are fed only AFTER a short settle delay following
/// LocationStartRequested. The chain start is asynchronous —
/// LocationBloc → DeadReckoningProvider.start() subscribes to the inner
/// provider's stream only after inner.start() returns — so a sentence delivered
/// before that subscription is live would be dropped (in production a GPS
/// streams continuously, so the very first sentence's drop is harmless; the
/// existing SimulatedLocationProvider relies on the same continuous-stream
/// behaviour). The settle delay models a real receiver that emits its first
/// fix a moment after the port opens.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/providers/serial_nmea_location_provider.dart';

/// Encode an NMEA sentence as CRLF-terminated serial bytes.
List<int> nmea(String sentence) => latin1.encode('$sentence\r\n');

// Munich-ish reference fix (matches the parser unit test) with speed+heading
// (RMC) so the Kalman filter can initialise and dead-reckon.
const _rmc =
    r'$GPRMC,123519,A,4807.038,N,01131.000,E,022.4,084.4,230394,003.1,W*6A';

void main() {
  /// Build the full chain over an injected byte controller. Returns the
  /// controller (to feed bytes) and the bloc (to observe states).
  ({StreamController<List<int>> bytes, LocationBloc bloc}) buildChain({
    required DeadReckoningMode mode,
    required Duration gpsTimeout,
    Duration extrapolationInterval = const Duration(milliseconds: 100),
  }) {
    final bytes = StreamController<List<int>>();
    final provider = SerialNmeaLocationProvider(
      portName: 'injected', // ignored when byteSource is supplied
      byteSource: bytes.stream,
    );
    final dr = DeadReckoningProvider(
      inner: provider,
      mode: mode,
      gpsTimeout: gpsTimeout,
      extrapolationInterval: extrapolationInterval,
    );
    final bloc = LocationBloc(provider: dr);
    addTearDown(() async {
      await bloc.close();
      if (!bytes.isClosed) await bytes.close();
    });
    return (bytes: bytes, bloc: bloc);
  }

  /// Let the asynchronous chain start (bloc → DR → provider subscriptions)
  /// fully settle before feeding bytes — see the library note on feeding.
  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 200));

  test(
    '1. canned NMEA bytes → fix LocationState at the right position',
    () async {
      // Long gpsTimeout so DR never kicks in for this fix-only test.
      final chain = buildChain(
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(seconds: 30),
      );

      chain.bloc.add(const LocationStartRequested());
      await settle();

      final fixFuture = chain.bloc.stream
          .firstWhere((s) => s.quality == LocationQuality.fix)
          .timeout(const Duration(seconds: 5));
      chain.bytes.add(nmea(_rmc));

      final fix = await fixFuture;
      expect(fix.quality, LocationQuality.fix);
      expect(fix.position, isNotNull);
      expect(fix.position!.latitude, closeTo(48.1173, 0.01));
      expect(fix.position!.longitude, closeTo(11.5167, 0.01));
      expect(fix.isDeadReckoning, isFalse);
    },
  );

  test('2. stopping the byte feed → dead-reckoning state', () async {
    final chain = buildChain(
      mode: DeadReckoningMode.kalman,
      gpsTimeout: const Duration(milliseconds: 150),
    );

    chain.bloc.add(const LocationStartRequested());
    await settle();
    chain.bytes.add(nmea(_rmc)); // one fix → Kalman initialises

    // Wait for the fix, THEN stop feeding bytes (no more sentences).
    await chain.bloc.stream
        .firstWhere((s) => s.quality == LocationQuality.fix)
        .timeout(const Duration(seconds: 5));

    // After gpsTimeout with no new bytes, the chain must dead-reckon.
    final dr = await chain.bloc.stream
        .firstWhere((s) => s.isDeadReckoning)
        .timeout(const Duration(seconds: 5));
    expect(dr.isDeadReckoning, isTrue);
  });

  test('3. high-HDOP fix degrades quality (no DR needed)', () async {
    final chain = buildChain(
      mode: DeadReckoningMode.kalman,
      gpsTimeout: const Duration(seconds: 30), // DR disabled for this test
    );

    chain.bloc.add(const LocationStartRequested());
    await settle();

    // A GGA with no preceding RMC has no speed/heading, so the Kalman wrapper
    // forwards the RAW fix unfiltered — exposing the parser's HDOP→accuracy.
    // HDOP 30.0 → ~150 m accuracy → above the 50 m navigation-grade bar.
    final degradedFuture = chain.bloc.stream
        .firstWhere((s) => s.quality == LocationQuality.degraded)
        .timeout(const Duration(seconds: 5));
    chain.bytes.add(
      nmea(r'$GPGGA,123521,4807.038,N,01131.000,E,1,06,30.0,545.4,M,46.9,M,,'),
    );

    final degraded = await degradedFuture;
    expect(degraded.quality, LocationQuality.degraded);
    expect(degraded.position, isNotNull);
    expect(degraded.confidenceRadius, closeTo(150.0, 0.5));
  });

  test('4. DR past the 500 m safety cap → position-unavailable floor', () async {
    // Linear DR grows accuracy at a fixed 5 m/s wall-clock, so a near-cap base
    // accuracy trips the 500 m floor within a second — deterministically fast.
    final chain = buildChain(
      mode: DeadReckoningMode.linear,
      gpsTimeout: const Duration(milliseconds: 100),
      extrapolationInterval: const Duration(milliseconds: 100),
    );

    chain.bloc.add(const LocationStartRequested());
    await settle();
    chain.bytes.add(nmea(_rmc)); // establishes speed+heading (DR-extrapolable)

    await chain.bloc.stream
        .firstWhere((s) => s.quality == LocationQuality.fix)
        .timeout(const Duration(seconds: 5));

    // HDOP 99.6 → ~498 m base accuracy. Linear DR (5 m/s) crosses 500 m in
    // well under a second once GPS stops.
    chain.bytes.add(
      nmea(r'$GPGGA,123522,4807.038,N,01131.000,E,1,04,99.6,545.4,M,46.9,M,,'),
    );

    // Stop feeding → DR starts → trips the 500 m safety cap → error floor.
    final floor = await chain.bloc.stream
        .firstWhere((s) => s.quality == LocationQuality.error)
        .timeout(const Duration(seconds: 8));
    expect(floor.quality, LocationQuality.error);
    expect(floor.errorMessage, contains('safety cap'));
  });
}
