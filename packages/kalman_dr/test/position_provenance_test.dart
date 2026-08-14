/// Position-provenance tests — can a consumer tell a measured fix from an
/// invented one, holding only the object?
///
/// The failure this suite exists to catch: `DeadReckoningProvider` emits
/// extrapolated positions onto the same stream as real ones, with a fresh
/// timestamp and an accuracy that can read *better* than a genuine fix taken in
/// poor conditions. Before `GeoPosition.source`, the only discriminator was the
/// out-of-band `isDrActive` getter — unavailable to anyone holding just a
/// position, and read at handler time rather than emit time even by those who
/// had it.
///
/// The consumer under test here is deliberately blind: it is handed positions
/// and never sees the provider. That is the real shape — a fusion library, a
/// BLoC state, a stored trajectory, a log line.
///
/// Safety: ASIL-QM — display only.
library;

import 'dart:async';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Mock inner provider
// ---------------------------------------------------------------------------

class MockLocationProvider implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _controller.close();

  void emitPosition(GeoPosition pos) => _controller.add(pos);
}

final _baseTime = DateTime.utc(2026, 3, 1, 12, 0, 0);

/// A real fix off the sensor — driving north at ~50 km/h, clean urban accuracy.
/// Declares its own provenance, as a sensor-backed provider should.
final _measuredFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 8.0,
  speed: 13.89,
  heading: 0.0,
  timestamp: _baseTime,
  source: PositionSource.measured,
  extrapolatedFor: Duration.zero,
);

void main() {
  // -------------------------------------------------------------------------
  // The consumer's question, asked of a live dead-reckoning cycle.
  // -------------------------------------------------------------------------

  group('a consumer holding only a GeoPosition', () {
    late MockLocationProvider mockGps;
    late DeadReckoningProvider provider;

    setUp(() {
      mockGps = MockLocationProvider();
      provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 300),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
    });

    tearDown(() async => provider.dispose());

    test('can tell the extrapolated positions from the measured one', () async {
      await provider.start();

      // The consumer sees positions and nothing else — no provider handle.
      final received = <GeoPosition>[];
      final sub = provider.positions.listen(received.add);

      mockGps.emitPosition(_measuredFix); // one real fix
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 800)); // silence

      await sub.cancel();

      expect(
        received.length,
        greaterThanOrEqualTo(2),
        reason: 'expected the real fix plus at least one extrapolation',
      );

      // Partition using ONLY what is on each object.
      final invented = received.where((p) => p.isDeadReckoned).toList();
      final real = received.where((p) => p.isMeasured).toList();

      expect(real, hasLength(1), reason: 'exactly one fix came off the sensor');
      expect(real.single.latitude, _measuredFix.latitude);

      expect(invented, isNotEmpty, reason: 'dead reckoning did emit');
      for (final p in invented) {
        expect(p.source, PositionSource.deadReckoned);
        expect(p.isMeasured, isFalse);
        expect(
          p.containsMeasurement,
          isFalse,
          reason: 'no sensor reading contributed to this coordinate',
        );
      }

      // The partition is total: every position was classifiable.
      expect(invented.length + real.length, received.length);
    });

    test('can tell HOW LONG the estimate has run without a sensor', () async {
      await provider.start();

      final received = <GeoPosition>[];
      final sub = provider.positions.listen(received.add);

      mockGps.emitPosition(_measuredFix);
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await sub.cancel();

      final invented = received.where((p) => p.isDeadReckoned).toList();
      expect(invented.length, greaterThanOrEqualTo(2));

      for (final p in invented) {
        expect(
          p.extrapolatedFor,
          isNotNull,
          reason: 'an invented position must say how far it has run',
        );
        expect(p.extrapolatedFor!, greaterThan(Duration.zero));
      }

      // It grows: the later estimate is further from evidence than the earlier.
      expect(
        invented.last.extrapolatedFor!,
        greaterThan(invented.first.extrapolatedFor!),
      );

      // And it is NOT recoverable from accuracy alone — accuracy conflates the
      // base fix quality with elapsed drift, so this is genuinely new
      // information rather than a restatement of the radius.
      expect(invented.first.accuracy, greaterThan(_measuredFix.accuracy));
    });

    test(
      'recovery: after GPS returns, positions stop claiming to be invented',
      () async {
        await provider.start();

        final received = <GeoPosition>[];
        final sub = provider.positions.listen(received.add);

        mockGps.emitPosition(_measuredFix);
        await Future<void>.delayed(
          const Duration(milliseconds: 700),
        ); // into DR
        expect(received.any((p) => p.isDeadReckoned), isTrue);

        // GPS comes back.
        mockGps.emitPosition(
          GeoPosition(
            latitude: 35.1730,
            longitude: 136.8815,
            accuracy: 6.0,
            speed: 13.89,
            heading: 0.0,
            timestamp: _baseTime.add(const Duration(seconds: 10)),
            source: PositionSource.measured,
            extrapolatedFor: Duration.zero,
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await sub.cancel();

        expect(received.last.isDeadReckoned, isFalse);
        expect(received.last.containsMeasurement, isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Kalman mode emits a THIRD kind, and it was previously indistinguishable
  // from a raw measurement too.
  // -------------------------------------------------------------------------

  group('Kalman mode', () {
    test('marks filter output as fused, not measured', () async {
      final mockGps = MockLocationProvider();
      final provider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 300),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
      await provider.start();

      final received = <GeoPosition>[];
      final sub = provider.positions.listen(received.add);

      mockGps.emitPosition(_measuredFix);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();

      expect(received, isNotEmpty);
      final out = received.first;

      // The consumer handed this position did NOT receive the sensor's value —
      // it received the filter's estimate. It has a right to know that.
      expect(out.source, PositionSource.fused);
      expect(out.isMeasured, isFalse, reason: 'not the raw sensor value');
      expect(out.containsMeasurement, isTrue, reason: 'a real reading fed it');
      expect(out.isDeadReckoned, isFalse);

      await provider.dispose();
    });

    test('marks pure prediction as deadReckoned with elapsed time', () async {
      final mockGps = MockLocationProvider();
      final provider = DeadReckoningProvider(
        inner: mockGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 300),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
      await provider.start();

      final received = <GeoPosition>[];
      final sub = provider.positions.listen(received.add);

      mockGps.emitPosition(_measuredFix);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await sub.cancel();

      final invented = received.where((p) => p.isDeadReckoned).toList();
      expect(invented, isNotEmpty);
      expect(invented.first.extrapolatedFor, isNotNull);
      expect(invented.first.extrapolatedFor!, greaterThan(Duration.zero));

      await provider.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Why the other candidate discriminators do not work.
  // -------------------------------------------------------------------------

  group('the discriminators a consumer would otherwise reach for', () {
    test('accuracy ranks a short extrapolation ABOVE a real poor fix', () {
      // One second of dead reckoning off a clean 8 m fix: 8 + 5*1 = 13 m.
      final oneSecondOfGuessing = GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 13.0,
        timestamp: _baseTime,
        source: PositionSource.deadReckoned,
        extrapolatedFor: const Duration(seconds: 1),
      );
      // A genuine reading under snow-loaded tree cover.
      final realFixInSnow = GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 40.0,
        timestamp: _baseTime,
        source: PositionSource.measured,
        extrapolatedFor: Duration.zero,
      );

      // Both clear the documented gate, and the invention looks better.
      expect(oneSecondOfGuessing.isNavigationGrade, isTrue);
      expect(realFixInSnow.isNavigationGrade, isTrue);
      expect(oneSecondOfGuessing.accuracy, lessThan(realFixInSnow.accuracy));

      // So accuracy must never be used as the provenance signal. `source` is.
      expect(oneSecondOfGuessing.isDeadReckoned, isTrue);
      expect(realFixInSnow.isDeadReckoned, isFalse);
    });

    test('timestamp freshness does not discriminate either', () async {
      final mockGps = MockLocationProvider();
      final provider = DeadReckoningProvider(
        inner: mockGps,
        gpsTimeout: const Duration(milliseconds: 300),
        extrapolationInterval: const Duration(milliseconds: 200),
      );
      await provider.start();

      final received = <GeoPosition>[];
      final sub = provider.positions.listen(received.add);

      mockGps.emitPosition(_measuredFix);
      await Future<void>.delayed(const Duration(milliseconds: 900));
      await sub.cancel();

      final invented = received.firstWhere((p) => p.isDeadReckoned);

      // The invented position's timestamp is NEWER than the real fix's. A
      // staleness watchdog — the standard fallback — sees it as the freshest
      // thing on the stream. `source` is what tells the truth.
      expect(invented.timestamp.isAfter(_measuredFix.timestamp), isTrue);
      expect(invented.isDeadReckoned, isTrue);

      await provider.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Equality, logging, and the honest default.
  // -------------------------------------------------------------------------

  group('GeoPosition.source semantics', () {
    GeoPosition at(PositionSource source) => GeoPosition(
      latitude: 35.1709,
      longitude: 136.8815,
      accuracy: 13.0,
      timestamp: _baseTime,
      source: source,
    );

    test('a measured and an invented fix at the same spot are NOT equal', () {
      // Load-bearing for `Stream.distinct()`: without provenance in `props`,
      // the measured -> dead-reckoned transition is silently swallowed
      // whenever it happens at a stationary coordinate — losing exactly the
      // event that matters.
      expect(
        at(PositionSource.measured),
        isNot(equals(at(PositionSource.deadReckoned))),
      );
      expect(
        at(PositionSource.fused),
        isNot(equals(at(PositionSource.measured))),
      );
      expect(at(PositionSource.measured), equals(at(PositionSource.measured)));
    });

    test('the transition survives Stream.distinct()', () async {
      final stationary = Stream<GeoPosition>.fromIterable([
        at(PositionSource.measured),
        at(PositionSource.measured),
        at(PositionSource.deadReckoned), // GPS just died. Same coordinate.
      ]);

      final seen = await stationary.distinct().toList();

      expect(seen, hasLength(2), reason: 'the duplicate collapses');
      expect(
        seen.last.isDeadReckoned,
        isTrue,
        reason: 'the transition into invention must NOT be collapsed away',
      );
    });

    test(
      'toString names the provenance — the line a remote debugger reads',
      () {
        expect(
          at(PositionSource.deadReckoned).toString(),
          'GeoPosition(35.1709, 136.8815 ±13.0m deadReckoned)',
        );
        expect(at(PositionSource.fused).toString(), contains('fused'));
      },
    );

    test('an unstated provenance renders exactly as it did before', () {
      // A producer that has not adopted `source` sees a byte-identical log
      // line. We do not churn output for people who have changed nothing.
      expect(
        at(PositionSource.unknown).toString(),
        'GeoPosition(35.1709, 136.8815 ±13.0m)',
      );
    });

    test('the default is unknown — absence is never rendered as measured', () {
      final undeclared = GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 8.0,
        timestamp: _baseTime,
      );

      expect(undeclared.source, PositionSource.unknown);
      // The critical asymmetry: an unstated provenance must not read as a
      // clean bill of health. A library cannot know a caller's coordinate came
      // off a sensor, and asserting it would manufacture the very claim this
      // field exists to make checkable.
      expect(undeclared.isMeasured, isFalse);
      expect(undeclared.containsMeasurement, isFalse);
      // Nor may it read as invented — we genuinely do not know.
      expect(undeclared.isDeadReckoned, isFalse);
    });

    test(
      'a consumer can filter the stream on the tag it now carries',
      () async {
        final mixed = Stream<GeoPosition>.fromIterable([
          at(PositionSource.measured),
          at(PositionSource.deadReckoned),
          at(PositionSource.fused),
          at(PositionSource.unknown),
        ]);

        // No separate stream is needed, and none is offered: the tag lets each
        // consumer choose its own predicate rather than inherit ours.
        final trustworthy = await mixed
            .where((p) => p.containsMeasurement)
            .toList();

        expect(trustworthy, hasLength(2));
        expect(trustworthy.every((p) => !p.isDeadReckoned), isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Pass-through honesty.
  // -------------------------------------------------------------------------

  test('the provider does not invent provenance it cannot vouch for', () async {
    final mockGps = MockLocationProvider();
    final provider = DeadReckoningProvider(inner: mockGps);
    await provider.start();

    final received = <GeoPosition>[];
    final sub = provider.positions.listen(received.add);

    // An inner provider that declares nothing.
    final undeclared = GeoPosition(
      latitude: 35.1709,
      longitude: 136.8815,
      accuracy: 8.0,
      speed: 13.89,
      heading: 0.0,
      timestamp: _baseTime,
    );
    mockGps.emitPosition(undeclared);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();

    // Forwarded untouched. This provider did not measure the coordinate and so
    // does not upgrade `unknown` to `measured` on the inner's behalf.
    expect(received.single.source, PositionSource.unknown);
    expect(received.single, equals(undeclared));

    await provider.dispose();
  });
}
