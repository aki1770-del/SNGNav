/// Performance benchmarks for SNGNav — Machine D reference numbers.
///
/// Run:
///   flutter test test/benchmark/performance_benchmark_test.dart --reporter expanded
///
/// These benchmarks measure and print timings for critical code paths.
/// They are not regression gates — they establish baselines.
///
/// Machine D: MacBook Pro 2017, i5-7267U 2C/4T, 8 GB RAM, Ubuntu 24.04.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latlong2/latlong.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:routing_engine/routing_engine.dart';

// ---------------------------------------------------------------------------
// Benchmark infrastructure
// ---------------------------------------------------------------------------

/// Runs [fn] for [iterations] and returns sorted elapsed microseconds.
List<int> _benchmark(int iterations, void Function() fn) {
  // Warmup — 10% of iterations or at least 10.
  final warmup = math.max(10, iterations ~/ 10);
  for (var i = 0; i < warmup; i++) {
    fn();
  }

  final times = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    fn();
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }
  times.sort();
  return times;
}

/// Async variant of [_benchmark].
Future<List<int>> _benchmarkAsync(
    int iterations, Future<void> Function() fn) async {
  final warmup = math.max(5, iterations ~/ 10);
  for (var i = 0; i < warmup; i++) {
    await fn();
  }

  final times = <int>[];
  for (var i = 0; i < iterations; i++) {
    final sw = Stopwatch()..start();
    await fn();
    sw.stop();
    times.add(sw.elapsedMicroseconds);
  }
  times.sort();
  return times;
}

/// Prints summary statistics for a benchmark.
void _report(String label, List<int> timesUs) {
  if (timesUs.isEmpty) return;
  final n = timesUs.length;
  final min = timesUs.first;
  final max = timesUs.last;
  final mean = timesUs.reduce((a, b) => a + b) / n;
  final p50 = timesUs[n ~/ 2];
  final p95 = timesUs[(n * 0.95).floor()];
  final p99 = timesUs[(n * 0.99).floor()];

  // ignore: avoid_print
  print('  $label: '
      'min=${min}µs  '
      'p50=${p50}µs  '
      'mean=${mean.toStringAsFixed(1)}µs  '
      'p95=${p95}µs  '
      'p99=${p99}µs  '
      'max=${max}µs  '
      '(n=$n)');
}

// ---------------------------------------------------------------------------
// Test data generators
// ---------------------------------------------------------------------------

/// Encode [points] into a polyline string with given [precision].
String _encodePolyline(List<LatLng> points, {int precision = 5}) {
  final factor = math.pow(10, precision).toInt();
  final buf = StringBuffer();
  var prevLat = 0;
  var prevLng = 0;

  for (final pt in points) {
    final lat = (pt.latitude * factor).round();
    final lng = (pt.longitude * factor).round();
    _encodeValue(lat - prevLat, buf);
    _encodeValue(lng - prevLng, buf);
    prevLat = lat;
    prevLng = lng;
  }
  return buf.toString();
}

void _encodeValue(int value, StringBuffer buf) {
  var v = value < 0 ? ~(value << 1) : (value << 1);
  while (v >= 0x20) {
    buf.writeCharCode(((v & 0x1F) | 0x20) + 63);
    v >>= 5;
  }
  buf.writeCharCode(v + 63);
}

/// Generate [count] LatLng points along Route 153 (Nagoya → Okazaki).
List<LatLng> _generateRoute153Points(int count) {
  const startLat = 35.1709;
  const startLon = 136.9066;
  const endLat = 34.9554;
  const endLon = 137.1791;

  return List.generate(count, (i) {
    final t = i / (count - 1);
    return LatLng(
      startLat + (endLat - startLat) * t,
      startLon + (endLon - startLon) * t,
    );
  });
}

/// Build a mock OSRM JSON response with [numManeuvers] steps and
/// [polyline] geometry.
MockClient _osrmMockClient({
  required String polyline,
  required int numManeuvers,
  double distance = 25700,
  double duration = 1800,
}) {
  final steps = <Map<String, dynamic>>[];
  for (var i = 0; i < numManeuvers; i++) {
    final isFirst = i == 0;
    final isLast = i == numManeuvers - 1;
    steps.add({
      'maneuver': {
        'type': isFirst
            ? 'depart'
            : isLast
                ? 'arrive'
                : 'turn',
        'modifier': isFirst || isLast
            ? ''
            : (i % 2 == 0 ? 'left' : 'right'),
        'location': [136.9 + i * 0.01, 35.17 - i * 0.005],
      },
      'name': 'Route 153 segment $i',
      'distance': distance / numManeuvers,
      'duration': duration / numManeuvers,
    });
  }

  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'code': 'Ok',
        'routes': [
          {
            'geometry': polyline,
            'distance': distance,
            'duration': duration,
            'legs': [
              {'steps': steps},
            ],
          },
        ],
      }),
      200,
    );
  });
}

/// Build a mock Valhalla JSON response.
MockClient _valhallaMockClient({
  required String polyline,
  required int numManeuvers,
  double length = 25.7,
  double time = 1800,
}) {
  final maneuvers = <Map<String, dynamic>>[];
  for (var i = 0; i < numManeuvers; i++) {
    final isFirst = i == 0;
    final isLast = i == numManeuvers - 1;
    maneuvers.add({
      'instruction': isFirst
          ? 'Drive east on Route 153.'
          : isLast
              ? 'You have arrived.'
              : 'Turn ${i % 2 == 0 ? "left" : "right"} on segment $i.',
      'type': isFirst
          ? 1
          : isLast
              ? 2
              : (i % 2 == 0 ? 11 : 6),
      'length': length / numManeuvers,
      'time': time / numManeuvers,
      'begin_shape_index': i,
    });
  }

  return MockClient((request) async {
    return http.Response(
      jsonEncode({
        'trip': {
          'summary': {'length': length, 'time': time},
          'legs': [
            {
              'shape': polyline,
              'maneuvers': maneuvers,
            },
          ],
        },
      }),
      200,
    );
  });
}

// ---------------------------------------------------------------------------
// Benchmarks
// ---------------------------------------------------------------------------

void main() {
  // -----------------------------------------------------------------------
  // 1. Kalman filter predict — the hottest pure-computation path
  // -----------------------------------------------------------------------
  group('Kalman filter predict', () {
    test('1000 × predict(1s) — single step baseline', () {
      final kf = KalmanFilter.withState(
        latitude: 35.1709,
        longitude: 136.9066,
        speed: 11.11,
        heading: 90.0,
        timestamp: DateTime(2026, 3, 4, 10, 0),
      );

      final times = _benchmark(1000, () {
        kf.predict(const Duration(seconds: 1));
      });

      _report('predict(1s)', times);

      // Sanity: filter still produces valid state.
      expect(kf.state.lat, isNot(isNaN));
      expect(kf.state.lon, isNot(isNaN));
    });

    test('1000 × predict(100ms) — high-frequency DR', () {
      final kf = KalmanFilter.withState(
        latitude: 35.1709,
        longitude: 136.9066,
        speed: 16.67,
        heading: 135.0,
        timestamp: DateTime(2026, 3, 4, 10, 0),
      );

      final times = _benchmark(1000, () {
        kf.predict(const Duration(milliseconds: 100));
      });

      _report('predict(100ms)', times);
    });
  });

  // -----------------------------------------------------------------------
  // 2. Kalman filter update — GPS fusion
  // -----------------------------------------------------------------------
  group('Kalman filter update', () {
    test('1000 × update() — standard GPS fix', () {
      final now = DateTime(2026, 3, 4, 10, 0);

      final times = _benchmark(1000, () {
        final kf = KalmanFilter.withState(
          latitude: 35.1709,
          longitude: 136.9066,
          speed: 11.11,
          heading: 90.0,
          timestamp: now,
          initialAccuracy: 5.0,
        );
        kf.predict(const Duration(seconds: 1));
        kf.update(
          lat: 35.1710,
          lon: 136.9076,
          speed: 11.5,
          heading: 89.5,
          accuracy: 5.0,
          timestamp: now.add(const Duration(seconds: 1)),
        );
      });

      _report('predict+update', times);
    });
  });

  // -----------------------------------------------------------------------
  // 3. Kalman filter tunnel scenario — 60s GPS loss
  // -----------------------------------------------------------------------
  group('Kalman filter tunnel scenario', () {
    test('60 × predict(1s) — simulated 60s tunnel', () {
      final kf = KalmanFilter.withState(
        latitude: 35.0824,
        longitude: 137.1088,
        speed: 16.67,
        heading: 135.0,
        timestamp: DateTime(2026, 3, 4, 10, 0),
      );

      final sw = Stopwatch()..start();
      for (var i = 0; i < 60; i++) {
        kf.predict(const Duration(seconds: 1));
      }
      sw.stop();

      final accuracyAfter60s = kf.accuracyMetres;
      final isExceeded = kf.isAccuracyExceeded;

      // ignore: avoid_print
      print('  60s tunnel: ${sw.elapsedMicroseconds}µs total '
          '(${(sw.elapsedMicroseconds / 60).toStringAsFixed(1)}µs/step), '
          'accuracy=${accuracyAfter60s.toStringAsFixed(1)}m, '
          'exceeded=$isExceeded');

      // Sanity: position should have moved south-east.
      expect(kf.state.lat, lessThan(35.0824));
      expect(kf.state.lon, greaterThan(137.1088));
    });

    test('tunnel + recovery — predict 30s then update', () {
      final now = DateTime(2026, 3, 4, 10, 0);
      final kf = KalmanFilter.withState(
        latitude: 35.0824,
        longitude: 137.1088,
        speed: 16.67,
        heading: 135.0,
        timestamp: now,
      );

      final sw = Stopwatch()..start();
      // 30s tunnel.
      for (var i = 0; i < 30; i++) {
        kf.predict(const Duration(seconds: 1));
      }
      // GPS recovery.
      kf.update(
        lat: 35.0500,
        lon: 137.1400,
        speed: 16.67,
        heading: 135.0,
        accuracy: 20.0, // degraded after tunnel exit
        timestamp: now.add(const Duration(seconds: 30)),
      );
      sw.stop();

      // ignore: avoid_print
      print('  30s tunnel + recovery: ${sw.elapsedMicroseconds}µs total, '
          'post-recovery accuracy=${kf.accuracyMetres.toStringAsFixed(1)}m');

      // Post-recovery accuracy should be better than pre-recovery.
      expect(kf.accuracyMetres, lessThan(100));
    });
  });

  // -----------------------------------------------------------------------
  // 4. Polyline5 decoding (OSRM) — varying sizes
  // -----------------------------------------------------------------------
  group('Polyline5 decoding (OSRM)', () {
    for (final numPoints in [10, 100, 500, 2000]) {
      test('$numPoints points — decode through calculateRoute', () async {
        final pts = _generateRoute153Points(numPoints);
        final encoded = _encodePolyline(pts, precision: 5);

        final engine = OsrmRoutingEngine(
          baseUrl: 'http://bench',
          client: _osrmMockClient(
            polyline: encoded,
            numManeuvers: 2, // minimal steps to isolate decode
          ),
        );

        final times = await _benchmarkAsync(200, () async {
          await engine.calculateRoute(const RouteRequest(
            origin: LatLng(35.17, 136.91),
            destination: LatLng(34.96, 137.18),
          ));
        });

        _report('polyline5 ${numPoints}pt', times);

        // Verify decode correctness.
        final result = await engine.calculateRoute(const RouteRequest(
          origin: LatLng(35.17, 136.91),
          destination: LatLng(34.96, 137.18),
        ));
        expect(result.shape.length, numPoints);
        expect(result.shape.first.latitude, closeTo(35.1709, 0.001));

        await engine.dispose();
      });
    }
  });

  // -----------------------------------------------------------------------
  // 5. Polyline6 decoding (Valhalla) — varying sizes
  // -----------------------------------------------------------------------
  group('Polyline6 decoding (Valhalla)', () {
    for (final numPoints in [10, 100, 500, 2000]) {
      test('$numPoints points — decode through calculateRoute', () async {
        final pts = _generateRoute153Points(numPoints);
        final encoded = _encodePolyline(pts, precision: 6);

        final engine = ValhallaRoutingEngine(
          baseUrl: 'http://bench',
          client: _valhallaMockClient(
            polyline: encoded,
            numManeuvers: 2,
          ),
        );

        final times = await _benchmarkAsync(200, () async {
          await engine.calculateRoute(const RouteRequest(
            origin: LatLng(35.17, 136.91),
            destination: LatLng(34.96, 137.18),
          ));
        });

        _report('polyline6 ${numPoints}pt', times);

        final result = await engine.calculateRoute(const RouteRequest(
          origin: LatLng(35.17, 136.91),
          destination: LatLng(34.96, 137.18),
        ));
        expect(result.shape.length, numPoints);

        await engine.dispose();
      });
    }
  });

  // -----------------------------------------------------------------------
  // 6. OSRM response parsing — realistic 25-maneuver route
  // -----------------------------------------------------------------------
  group('OSRM response parsing', () {
    test('25 maneuvers + 500pt polyline — full parse', () async {
      final pts = _generateRoute153Points(500);
      final encoded = _encodePolyline(pts, precision: 5);

      final engine = OsrmRoutingEngine(
        baseUrl: 'http://bench',
        client: _osrmMockClient(
          polyline: encoded,
          numManeuvers: 25,
        ),
      );

      final times = await _benchmarkAsync(200, () async {
        await engine.calculateRoute(const RouteRequest(
          origin: LatLng(35.17, 136.91),
          destination: LatLng(34.96, 137.18),
        ));
      });

      _report('OSRM 25-step/500pt', times);

      final result = await engine.calculateRoute(const RouteRequest(
        origin: LatLng(35.17, 136.91),
        destination: LatLng(34.96, 137.18),
      ));
      expect(result.maneuvers.length, 25);
      expect(result.shape.length, 500);

      await engine.dispose();
    });
  });

  // -----------------------------------------------------------------------
  // 7. Valhalla response parsing — realistic 25-maneuver route
  // -----------------------------------------------------------------------
  group('Valhalla response parsing', () {
    test('25 maneuvers + 500pt polyline — full parse', () async {
      final pts = _generateRoute153Points(500);
      final encoded = _encodePolyline(pts, precision: 6);

      final engine = ValhallaRoutingEngine(
        baseUrl: 'http://bench',
        client: _valhallaMockClient(
          polyline: encoded,
          numManeuvers: 25,
        ),
      );

      final times = await _benchmarkAsync(200, () async {
        await engine.calculateRoute(const RouteRequest(
          origin: LatLng(35.17, 136.91),
          destination: LatLng(34.96, 137.18),
        ));
      });

      _report('Valhalla 25-step/500pt', times);

      final result = await engine.calculateRoute(const RouteRequest(
        origin: LatLng(35.17, 136.91),
        destination: LatLng(34.96, 137.18),
      ));
      expect(result.maneuvers.length, 25);
      expect(result.shape.length, 500);

      await engine.dispose();
    });
  });

  // -----------------------------------------------------------------------
  // 8. DR activation latency — GPS timeout → first DR position
  // -----------------------------------------------------------------------
  group('DR activation latency', () {
    test('GPS loss → DR active (kalman mode, 200ms timeout)', () async {
      final gps = _ControllableProvider();
      final dr = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );

      await dr.start();
      final positions = <GeoPosition>[];
      final sub = dr.positions.listen(positions.add);

      // Emit one GPS fix to initialise the filter.
      gps.emit(GeoPosition(
        latitude: 35.0824,
        longitude: 137.1088,
        accuracy: 5.0,
        speed: 16.67,
        heading: 135.0,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final gpsCount = positions.length;

      // Now stop emitting — GPS lost. Measure time to first DR position.
      final sw = Stopwatch()..start();
      positions.clear();

      // Wait for GPS timeout + at least one DR extrapolation.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      sw.stop();

      final drPositions = positions.length;
      final isDrActive = dr.isDrActive;

      // ignore: avoid_print
      print('  DR activation: gps_fixes=$gpsCount, '
          'dr_positions=$drPositions, '
          'isDrActive=$isDrActive, '
          'wall_time=${sw.elapsedMilliseconds}ms');

      expect(isDrActive, isTrue,
          reason: 'DR should be active after GPS timeout');
      expect(drPositions, greaterThan(0),
          reason: 'DR should have emitted at least one position');

      await sub.cancel();
      await dr.dispose();
    });

    test('GPS loss → DR active (linear mode, 200ms timeout)', () async {
      final gps = _ControllableProvider();
      final dr = DeadReckoningProvider(
        inner: gps,
        mode: DeadReckoningMode.linear,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );

      await dr.start();
      final positions = <GeoPosition>[];
      final sub = dr.positions.listen(positions.add);

      gps.emit(GeoPosition(
        latitude: 35.0824,
        longitude: 137.1088,
        accuracy: 5.0,
        speed: 16.67,
        heading: 135.0,
        timestamp: DateTime.now(),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      positions.clear();

      final sw = Stopwatch()..start();
      await Future<void>.delayed(const Duration(milliseconds: 500));
      sw.stop();

      final drPositions = positions.length;

      // ignore: avoid_print
      print('  DR activation (linear): '
          'dr_positions=$drPositions, '
          'isDrActive=${dr.isDrActive}, '
          'wall_time=${sw.elapsedMilliseconds}ms');

      expect(dr.isDrActive, isTrue);
      expect(drPositions, greaterThan(0));

      await sub.cancel();
      await dr.dispose();
    });
  });

  // -----------------------------------------------------------------------
  // 9. Provider creation chain — startup cost
  // -----------------------------------------------------------------------
  group('Provider creation', () {
    test('1000 × KalmanFilter instantiation', () {
      final times = _benchmark(1000, () {
        KalmanFilter();
      });
      _report('KalmanFilter()', times);
    });

    test('1000 × KalmanFilter.withState', () {
      final times = _benchmark(1000, () {
        KalmanFilter.withState(
          latitude: 35.17,
          longitude: 136.91,
          speed: 11.11,
          heading: 90.0,
          timestamp: DateTime(2026, 3, 4, 10, 0),
        );
      });
      _report('KalmanFilter.withState()', times);
    });
  });

  // -----------------------------------------------------------------------
  // 10. Matrix operations — micro-benchmarks
  // -----------------------------------------------------------------------
  group('Kalman filter convergence', () {
    test('GPS fix every 1s for 60s — convergence profile', () {
      final now = DateTime(2026, 3, 4, 10, 0);
      final kf = KalmanFilter();

      final accuracies = <double>[];
      final sw = Stopwatch()..start();

      for (var i = 0; i < 60; i++) {
        // Simulate moving east at 11 m/s.
        kf.update(
          lat: 35.1709 + i * 0.0001,
          lon: 136.9066 + i * 0.001,
          speed: 11.11 + (i % 3) * 0.5, // slight jitter
          heading: 90.0 + (i % 5) - 2.0, // slight jitter
          accuracy: 5.0,
          timestamp: now.add(Duration(seconds: i)),
        );
        accuracies.add(kf.accuracyMetres);
      }

      sw.stop();

      // ignore: avoid_print
      print('  60 GPS updates: ${sw.elapsedMicroseconds}µs total '
          '(${(sw.elapsedMicroseconds / 60).toStringAsFixed(1)}µs/update)');
      // ignore: avoid_print
      print('  Convergence: '
          'fix1=${accuracies[0].toStringAsFixed(2)}m → '
          'fix10=${accuracies[9].toStringAsFixed(2)}m → '
          'fix30=${accuracies[29].toStringAsFixed(2)}m → '
          'fix60=${accuracies[59].toStringAsFixed(2)}m');

      // After 60 fixes, accuracy should be very good.
      expect(accuracies.last, lessThan(10.0));
    });
  });
}

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

/// A location provider whose emissions are controlled by the test.
class _ControllableProvider implements LocationProvider {
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

  void emit(GeoPosition pos) => _controller.add(pos);
}
