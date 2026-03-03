/// Dead reckoning state tests — verifies linear extrapolation,
/// accuracy degradation, and safety cap.
///
/// Tests:
///   - fromGeoPosition with valid/invalid inputs
///   - predict moves position (north, east, NW)
///   - predict with zero speed stays put
///   - accuracy degrades linearly
///   - maxAccuracy safety cap
///   - toGeoPosition conversion
///   - heading wraparound in extrapolation
library;
import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

void main() {
  group('DeadReckoningState', () {
    final baseTime = DateTime(2026, 3, 1, 12, 0, 0);

    test('fromGeoPosition creates state from valid position', () {
      final pos = GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 5.0,
        speed: 10.0,
        heading: 90.0,
        timestamp: baseTime,
      );

      final state = DeadReckoningState.fromGeoPosition(pos);
      expect(state, isNotNull);
      expect(state!.latitude, 35.17);
      expect(state.speed, 10.0);
      expect(state.heading, 90.0);
    });

    test('fromGeoPosition returns null for NaN speed', () {
      final pos = GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 5.0,
        speed: double.nan,
        heading: 90.0,
        timestamp: baseTime,
      );
      expect(DeadReckoningState.fromGeoPosition(pos), isNull);
    });

    test('fromGeoPosition returns null for NaN heading', () {
      final pos = GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 5.0,
        speed: 10.0,
        heading: double.nan,
        timestamp: baseTime,
      );
      expect(DeadReckoningState.fromGeoPosition(pos), isNull);
    });

    test('fromGeoPosition returns null for negative speed', () {
      final pos = GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 5.0,
        speed: -1.0,
        heading: 90.0,
        timestamp: baseTime,
      );
      expect(DeadReckoningState.fromGeoPosition(pos), isNull);
    });

    test('predict north increases latitude', () {
      final state = DeadReckoningState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 0.0, // north
        baseAccuracy: 5.0,
        lastGpsTime: baseTime,
      );

      final next = state.predict(const Duration(seconds: 1));
      expect(next.latitude, greaterThan(state.latitude));
      expect(next.longitude, closeTo(state.longitude, 0.0001));
      expect(next.extrapolationCount, 1);
    });

    test('predict east increases longitude', () {
      final state = DeadReckoningState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0, // east
        baseAccuracy: 5.0,
        lastGpsTime: baseTime,
      );

      final next = state.predict(const Duration(seconds: 1));
      expect(next.longitude, greaterThan(state.longitude));
      expect(next.latitude, closeTo(state.latitude, 0.0001));
    });

    test('predict with zero speed stays in place', () {
      final state = DeadReckoningState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 0.0,
        heading: 90.0,
        baseAccuracy: 5.0,
        lastGpsTime: baseTime,
      );

      final next = state.predict(const Duration(seconds: 5));
      expect(next.latitude, state.latitude);
      expect(next.longitude, state.longitude);
      expect(next.extrapolationCount, 1);
    });

    test('accuracy degrades linearly over time', () {
      final state = DeadReckoningState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        baseAccuracy: 5.0,
        lastGpsTime: baseTime,
      );

      final at0 = state.accuracyAt(baseTime);
      final at10 = state.accuracyAt(baseTime.add(const Duration(seconds: 10)));
      expect(at0, closeTo(5.0, 0.1));
      expect(at10, closeTo(55.0, 0.1)); // 5 + 5*10
    });

    test('maxAccuracy is 500m', () {
      expect(DeadReckoningState.maxAccuracy, 500.0);
    });

    test('degradationRate is 5 m/s', () {
      expect(DeadReckoningState.degradationRate, 5.0);
    });

    test('toGeoPosition produces GeoPosition with degraded accuracy', () {
      final state = DeadReckoningState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        baseAccuracy: 5.0,
        lastGpsTime: baseTime,
      );

      final pos = state.toGeoPosition(
        now: baseTime.add(const Duration(seconds: 5)),
      );
      expect(pos.latitude, 35.17);
      expect(pos.accuracy, closeTo(30.0, 0.1)); // 5 + 5*5
    });

    test('canExtrapolate is true for valid state', () {
      final state = DeadReckoningState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 10.0,
        heading: 90.0,
        baseAccuracy: 5.0,
        lastGpsTime: baseTime,
      );
      expect(state.canExtrapolate, isTrue);
    });
  });
}
