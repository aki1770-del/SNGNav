import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:sngnav_snow_scene/models/kalman_filter.dart';

void main() {
  group('KalmanFilter', () {
    group('initialisation', () {
      test('starts uninitialised', () {
        final kf = KalmanFilter();
        expect(kf.isInitialized, isFalse);
      });

      test('predict before initialisation returns infinity accuracy', () {
        final kf = KalmanFilter();
        final result = kf.predict(const Duration(seconds: 1));
        expect(result.accuracy, double.infinity);
      });

      test('first update initialises state', () {
        final kf = KalmanFilter();
        final t = DateTime(2026, 2, 28, 12, 0, 0);
        kf.update(
          lat: 35.17, lon: 136.88, speed: 11.0, heading: 90.0,
          accuracy: 5.0, timestamp: t,
        );
        expect(kf.isInitialized, isTrue);
        expect(kf.state.lat, 35.17);
        expect(kf.state.lon, 136.88);
        expect(kf.state.speed, 11.0);
        expect(kf.state.heading, 90.0);
      });

      test('withState constructor initialises directly', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
        );
        expect(kf.isInitialized, isTrue);
        expect(kf.state.lat, 35.17);
      });

      test('reset clears state', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
        );
        kf.reset();
        expect(kf.isInitialized, isFalse);
      });
    });

    group('prediction (GPS lost)', () {
      test('predicts position forward at constant velocity', () {
        final t = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0, // due east
          timestamp: t,
        );

        final result = kf.predict(const Duration(seconds: 1));

        // Heading 90° = due east → longitude increases, latitude stays.
        expect(result.lat, closeTo(35.17, 0.001));
        expect(result.lon, greaterThan(136.88));
        expect(result.speed, closeTo(11.0, 0.1));
        expect(result.heading, closeTo(90.0, 0.1));
      });

      test('heading 0° moves north (latitude increases)', () {
        final kf = KalmanFilter.withState(
          latitude: 35.0, longitude: 137.0,
          speed: 10.0, heading: 0.0, // due north
          timestamp: DateTime(2026, 2, 28),
        );

        final result = kf.predict(const Duration(seconds: 10));
        expect(result.lat, greaterThan(35.0));
        expect(result.lon, closeTo(137.0, 0.0001));
      });

      test('heading 180° moves south (latitude decreases)', () {
        final kf = KalmanFilter.withState(
          latitude: 35.0, longitude: 137.0,
          speed: 10.0, heading: 180.0, // due south
          timestamp: DateTime(2026, 2, 28),
        );

        final result = kf.predict(const Duration(seconds: 10));
        expect(result.lat, lessThan(35.0));
      });

      test('accuracy grows during prediction-only', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
          initialAccuracy: 5.0,
        );

        final a0 = kf.accuracyMetres;

        // Predict 10 seconds without GPS.
        for (var i = 0; i < 10; i++) {
          kf.predict(const Duration(seconds: 1));
        }

        final a10 = kf.accuracyMetres;
        expect(a10, greaterThan(a0),
            reason: 'Accuracy should degrade during prediction-only');
      });

      test('zero-duration prediction does not change state', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
        );

        final before = kf.state;
        kf.predict(Duration.zero);
        final after = kf.state;

        expect(after.lat, before.lat);
        expect(after.lon, before.lon);
      });

      test('stationary vehicle stays in place', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 0.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
        );

        final result = kf.predict(const Duration(seconds: 60));
        expect(result.lat, closeTo(35.17, 0.0001));
        expect(result.lon, closeTo(136.88, 0.0001));
      });
    });

    group('measurement update (GPS available)', () {
      test('update corrects predicted position toward measurement', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: t0,
        );

        // Predict forward 5 seconds (GPS lost).
        for (var i = 0; i < 5; i++) {
          kf.predict(const Duration(seconds: 1));
        }
        final predicted = kf.state;

        // GPS fix arrives — slightly different from prediction.
        final t5 = t0.add(const Duration(seconds: 5));
        kf.update(
          lat: predicted.lat + 0.0001,
          lon: predicted.lon - 0.0001,
          speed: 12.0,
          heading: 85.0,
          accuracy: 5.0,
          timestamp: t5,
        );

        // State should move toward the GPS measurement.
        final updated = kf.state;
        expect(updated.lat, greaterThan(predicted.lat));
        expect(updated.lon, lessThan(predicted.lon));
      });

      test('update reduces accuracy (covariance shrinks)', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: t0,
          initialAccuracy: 5.0,
        );

        // Predict forward — accuracy degrades.
        for (var i = 0; i < 10; i++) {
          kf.predict(const Duration(seconds: 1));
        }
        final degradedAccuracy = kf.accuracyMetres;

        // GPS fix — accuracy recovers.
        kf.update(
          lat: kf.state.lat, lon: kf.state.lon,
          speed: 11.0, heading: 90.0,
          accuracy: 5.0,
          timestamp: t0.add(const Duration(seconds: 10)),
        );
        final recoveredAccuracy = kf.accuracyMetres;

        expect(recoveredAccuracy, lessThan(degradedAccuracy),
            reason: 'GPS fix should reduce uncertainty');
      });

      test('low-accuracy GPS has less influence', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);

        // Two identical filters.
        final kfGood = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: t0,
        );
        final kfBad = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: t0,
        );

        final t1 = t0.add(const Duration(seconds: 1));
        const offsetLat = 35.171;

        // Good GPS (5m accuracy).
        kfGood.update(
          lat: offsetLat, lon: 136.88,
          speed: 11.0, heading: 90.0,
          accuracy: 5.0, timestamp: t1,
        );

        // Bad GPS (100m accuracy).
        kfBad.update(
          lat: offsetLat, lon: 136.88,
          speed: 11.0, heading: 90.0,
          accuracy: 100.0, timestamp: t1,
        );

        // Good GPS should pull the state closer to the measurement.
        final goodDist = (kfGood.state.lat - offsetLat).abs();
        final badDist = (kfBad.state.lat - offsetLat).abs();
        expect(goodDist, lessThan(badDist),
            reason: 'Higher-accuracy GPS should have more influence');
      });
    });

    group('heading wraparound', () {
      test('handles 350° → 10° transition', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 350.0,
          timestamp: t0,
        );

        kf.update(
          lat: 35.17, lon: 136.88,
          speed: 11.0, heading: 10.0,
          accuracy: 5.0,
          timestamp: t0.add(const Duration(seconds: 1)),
        );

        // Heading should be near 0/360, not near 180.
        final h = kf.state.heading;
        expect(h < 30 || h > 330, isTrue,
            reason: 'Heading should wrap correctly through 0°');
      });

      test('heading stays in [0, 360)', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 5.0,
          timestamp: t0,
        );

        // Update with heading near 355° — wraps through 0.
        kf.update(
          lat: 35.17, lon: 136.88,
          speed: 11.0, heading: 355.0,
          accuracy: 5.0,
          timestamp: t0.add(const Duration(seconds: 1)),
        );

        expect(kf.state.heading, greaterThanOrEqualTo(0.0));
        expect(kf.state.heading, lessThan(360.0));
      });
    });

    group('convergence', () {
      test('filter converges on steady-state GPS stream', () {
        final kf = KalmanFilter();
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);

        // Simulate 20 GPS fixes at ~35.17°N, 136.88°E, 11 m/s, heading 90°.
        // Add small random noise to simulate real GPS.
        final rng = math.Random(42);
        for (var i = 0; i < 20; i++) {
          kf.update(
            lat: 35.17 + (rng.nextDouble() - 0.5) * 0.0001,
            lon: 136.88 + (rng.nextDouble() - 0.5) * 0.0001,
            speed: 11.0 + (rng.nextDouble() - 0.5) * 2.0,
            heading: 90.0 + (rng.nextDouble() - 0.5) * 5.0,
            accuracy: 5.0,
            timestamp: t0.add(Duration(seconds: i)),
          );
        }

        // After 20 fixes, state should be near the mean.
        expect(kf.state.lat, closeTo(35.17, 0.001));
        expect(kf.state.lon, closeTo(136.88, 0.001));
        expect(kf.state.speed, closeTo(11.0, 2.0));
        expect(kf.state.heading, closeTo(90.0, 5.0));
        expect(kf.accuracyMetres, lessThan(20.0));
      });

      test('tunnel scenario: GPS → predict → GPS recovery', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter();

        // 10 GPS fixes before tunnel.
        for (var i = 0; i < 10; i++) {
          kf.update(
            lat: 35.17, lon: 136.88 + i * 0.0001,
            speed: 25.0, heading: 90.0,
            accuracy: 5.0,
            timestamp: t0.add(Duration(seconds: i)),
          );
        }
        final preAccuracy = kf.accuracyMetres;

        // 30 seconds in tunnel (prediction only).
        for (var i = 0; i < 30; i++) {
          kf.predict(const Duration(seconds: 1));
        }
        final tunnelAccuracy = kf.accuracyMetres;
        expect(tunnelAccuracy, greaterThan(preAccuracy),
            reason: 'Accuracy degrades in tunnel');

        // GPS recovery.
        kf.update(
          lat: kf.state.lat, lon: kf.state.lon,
          speed: 25.0, heading: 90.0,
          accuracy: 8.0,
          timestamp: t0.add(const Duration(seconds: 40)),
        );
        final recoveredAccuracy = kf.accuracyMetres;
        expect(recoveredAccuracy, lessThan(tunnelAccuracy),
            reason: 'Accuracy recovers after GPS fix');
      });

      test('extended dead reckoning exceeds safety cap', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 25.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
          initialAccuracy: 5.0,
        );

        // Predict for 5 minutes without GPS.
        for (var i = 0; i < 300; i++) {
          kf.predict(const Duration(seconds: 1));
        }

        expect(kf.isAccuracyExceeded, isTrue,
            reason: '5 minutes without GPS should exceed safety cap');
      });
    });

    group('speed clamping', () {
      test('speed never goes negative', () {
        final t0 = DateTime(2026, 2, 28, 12, 0, 0);
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 1.0, heading: 90.0,
          timestamp: t0,
        );

        // GPS reports speed 0 — filter should clamp, not go negative.
        kf.update(
          lat: 35.17, lon: 136.88,
          speed: 0.0, heading: 90.0,
          accuracy: 5.0,
          timestamp: t0.add(const Duration(seconds: 1)),
        );

        expect(kf.state.speed, greaterThanOrEqualTo(0.0));
      });
    });

    group('accuracy calculation', () {
      test('accuracy reflects covariance in metres', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 11.0, heading: 90.0,
          timestamp: DateTime(2026, 2, 28),
          initialAccuracy: 10.0,
        );

        // Initial accuracy should be near the specified value.
        expect(kf.accuracyMetres, closeTo(10.0, 5.0));
      });

      test('accuracy is positive', () {
        final kf = KalmanFilter.withState(
          latitude: 35.17, longitude: 136.88,
          speed: 0.0, heading: 0.0,
          timestamp: DateTime(2026, 2, 28),
        );

        expect(kf.accuracyMetres, greaterThan(0));
      });
    });
  });
}
