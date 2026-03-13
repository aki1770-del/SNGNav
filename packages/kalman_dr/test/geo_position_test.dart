import 'package:kalman_dr/kalman_dr.dart';
import 'package:test/test.dart';

void main() {
  group('GeoPosition', () {
    final timestamp = DateTime(2026, 3, 13, 12, 0, 0);

    GeoPosition position({
      double latitude = 35.17,
      double longitude = 136.88,
      double accuracy = 5.0,
      double altitude = 42.0,
      double speed = 10.0,
      double heading = 90.0,
    }) => GeoPosition(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      altitude: altitude,
      speed: speed,
      heading: heading,
      timestamp: timestamp,
    );

    test('isNavigationGrade is true at exactly 50.0m', () {
      expect(position(accuracy: 50.0).isNavigationGrade, isTrue);
    });

    test('isNavigationGrade is false above 50.0m', () {
      expect(position(accuracy: 50.1).isNavigationGrade, isFalse);
    });

    test('isHighAccuracy is true at exactly 10.0m', () {
      expect(position(accuracy: 10.0).isHighAccuracy, isTrue);
    });

    test('isHighAccuracy is false above 10.0m', () {
      expect(position(accuracy: 10.1).isHighAccuracy, isFalse);
    });

    test('speedKmh converts metres per second to km/h', () {
      expect(position(speed: 10.0).speedKmh, 36.0);
    });

    test('speedKmh preserves NaN when speed is unknown', () {
      expect(position(speed: double.nan).speedKmh, isNaN);
    });

    test('equatable compares all fields', () {
      expect(position(), equals(position()));
      expect(position(heading: 91.0), isNot(equals(position())));
    });

    test('toString includes coordinates and rounded accuracy', () {
      expect(
        position(accuracy: 12.34).toString(),
        'GeoPosition(35.17, 136.88 ±12.3m)',
      );
    });
  });
}