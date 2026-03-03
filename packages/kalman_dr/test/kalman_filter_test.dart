/// Kalman filter unit tests — verifies predict/update cycle, accuracy,
/// heading wraparound, convergence, and safety cap.
///
/// Tests:
///   - initialisation from constructor and withState
///   - predict forward (position moves, covariance grows)
///   - update with GPS fix (covariance shrinks)
///   - heading wraparound (350° → 10° = +20° innovation)
///   - speed clamping (never negative)
///   - accuracy exceeded threshold
///   - reset returns to uninitialised
///   - predict before initialisation returns infinity
library;
import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

void main() {
  group('KalmanFilter', () {
    late KalmanFilter kf;

    setUp(() {
      kf = KalmanFilter();
    });

    test('starts uninitialised', () {
      expect(kf.isInitialized, isFalse);
    });

    test('predict before initialisation returns infinity accuracy', () {
      final result = kf.predict(const Duration(seconds: 1));
      expect(result.accuracy, double.infinity);
    });

    test('first update initialises the filter', () {
      final now = DateTime.now();
      kf.update(
        lat: 35.17,
        lon: 136.88,
        speed: 11.0,
        heading: 90.0,
        accuracy: 5.0,
        timestamp: now,
      );
      expect(kf.isInitialized, isTrue);
      expect(kf.state.lat, closeTo(35.17, 0.001));
      expect(kf.state.lon, closeTo(136.88, 0.001));
    });

    test('predict moves position forward', () {
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 0.0, // north
        timestamp: DateTime.now(),
      );

      final before = kf.state.lat;
      kf.predict(const Duration(seconds: 5));
      expect(kf.state.lat, greaterThan(before));
    });

    test('predict grows accuracy (covariance increases)', () {
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        timestamp: DateTime.now(),
        initialAccuracy: 5.0,
      );

      final acc1 = kf.accuracyMetres;
      kf.predict(const Duration(seconds: 10));
      final acc2 = kf.accuracyMetres;
      expect(acc2, greaterThan(acc1));
    });

    test('update shrinks accuracy (GPS fusion)', () {
      final now = DateTime.now();
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        timestamp: now,
        initialAccuracy: 50.0, // poor initial
      );

      // Predict to grow uncertainty.
      kf.predict(const Duration(seconds: 5));
      final accBefore = kf.accuracyMetres;

      // GPS update with good accuracy.
      kf.update(
        lat: 35.17,
        lon: 136.885,
        speed: 10.0,
        heading: 90.0,
        accuracy: 3.0,
        timestamp: now.add(const Duration(seconds: 6)),
      );
      expect(kf.accuracyMetres, lessThan(accBefore));
    });

    test('heading wraparound handles 350 to 10 correctly', () {
      final now = DateTime.now();
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 350.0,
        timestamp: now,
      );

      kf.update(
        lat: 35.17,
        lon: 136.88,
        speed: 10.0,
        heading: 10.0,
        accuracy: 5.0,
        timestamp: now.add(const Duration(seconds: 1)),
      );

      // Heading should be near 0/360, not 180.
      final h = kf.state.heading;
      expect(h < 30 || h > 330, isTrue,
          reason: 'heading=$h should be near 0/360');
    });

    test('speed never goes negative', () {
      final now = DateTime.now();
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 1.0,
        heading: 90.0,
        timestamp: now,
      );

      // Feed zero-speed measurements to drive speed down.
      for (var i = 1; i <= 10; i++) {
        kf.update(
          lat: 35.17,
          lon: 136.88,
          speed: 0.0,
          heading: 90.0,
          accuracy: 5.0,
          timestamp: now.add(Duration(seconds: i)),
        );
      }
      expect(kf.state.speed, greaterThanOrEqualTo(0));
    });

    test('accuracy exceeded after many predictions', () {
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      // Predict for a long time without GPS.
      for (var i = 0; i < 300; i++) {
        kf.predict(const Duration(seconds: 1));
      }
      expect(kf.isAccuracyExceeded, isTrue);
    });

    test('reset returns to uninitialised', () {
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        timestamp: DateTime.now(),
      );
      expect(kf.isInitialized, isTrue);

      kf.reset();
      expect(kf.isInitialized, isFalse);
    });

    test('withState constructor initialises correctly', () {
      final now = DateTime.now();
      kf = KalmanFilter.withState(
        latitude: 35.0,
        longitude: 137.0,
        speed: 15.0,
        heading: 45.0,
        timestamp: now,
        initialAccuracy: 3.0,
      );

      expect(kf.isInitialized, isTrue);
      expect(kf.state.lat, closeTo(35.0, 0.001));
      expect(kf.state.lon, closeTo(137.0, 0.001));
      expect(kf.state.speed, closeTo(15.0, 0.1));
      expect(kf.state.heading, closeTo(45.0, 0.1));
      expect(kf.accuracyMetres, closeTo(3.0, 1.0));
    });

    test('predict with zero duration returns current state', () {
      kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      final result = kf.predict(Duration.zero);
      expect(result.lat, closeTo(35.17, 0.001));
      expect(result.lon, closeTo(136.88, 0.001));
    });
  });
}
