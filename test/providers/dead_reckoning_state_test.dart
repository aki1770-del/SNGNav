/// DeadReckoningState unit tests — state vector math.
///
/// Tests the linear extrapolation model that predicts driver position
/// when GPS is lost in a tunnel.
///
/// Sprint 9 Day 2 — E9-1 baseline tests.
/// Safety: all positions are ASIL-QM (display only).
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:kalman_dr/kalman_dr.dart';

// ---------------------------------------------------------------------------
// Test data — Nagoya area coordinates
// ---------------------------------------------------------------------------

final _baseTime = DateTime(2026, 2, 28, 10, 0, 0);

/// Driving north at 50 km/h (13.89 m/s) with good GPS fix.
final _northboundFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 13.89,
  heading: 0.0, // due north
  timestamp: _baseTime,
);

/// Driving east at 60 km/h (16.67 m/s).
final _eastboundFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 8.0,
  speed: 16.67,
  heading: 90.0, // due east
  timestamp: _baseTime,
);

/// Driving NW (315°) at 50 km/h — mountain approach.
final _nwFix = GeoPosition(
  latitude: 35.2000,
  longitude: 136.8620,
  accuracy: 15.0,
  speed: 13.89,
  heading: 315.0,
  timestamp: _baseTime,
);

/// Stationary vehicle (speed = 0).
final _stationaryFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 0.0,
  heading: 0.0,
  timestamp: _baseTime,
);

/// Fix with NaN speed — cannot extrapolate.
final _noSpeedFix = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  timestamp: _baseTime,
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('DeadReckoningState.fromGeoPosition', () {
    test('creates state from valid fix with speed and heading', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix);
      expect(state, isNotNull);
      expect(state!.latitude, equals(35.1709));
      expect(state.longitude, equals(136.8815));
      expect(state.speed, equals(13.89));
      expect(state.heading, equals(0.0));
      expect(state.baseAccuracy, equals(5.0));
      expect(state.lastGpsTime, equals(_baseTime));
      expect(state.extrapolationCount, equals(0));
    });

    test('returns null when speed is NaN', () {
      final state = DeadReckoningState.fromGeoPosition(_noSpeedFix);
      expect(state, isNull);
    });

    test('returns null when heading is NaN', () {
      final fix = GeoPosition(
        latitude: 35.0,
        longitude: 137.0,
        accuracy: 5.0,
        speed: 10.0, // has speed
        // heading defaults to NaN
        timestamp: _baseTime,
      );
      final state = DeadReckoningState.fromGeoPosition(fix);
      expect(state, isNull);
    });

    test('returns null for negative speed', () {
      final fix = GeoPosition(
        latitude: 35.0,
        longitude: 137.0,
        accuracy: 5.0,
        speed: -1.0,
        heading: 0.0,
        timestamp: _baseTime,
      );
      final state = DeadReckoningState.fromGeoPosition(fix);
      expect(state, isNull);
    });

    test('creates state from stationary fix (speed = 0)', () {
      final state = DeadReckoningState.fromGeoPosition(_stationaryFix);
      expect(state, isNotNull);
      expect(state!.speed, equals(0.0));
    });
  });

  group('DeadReckoningState.predict — northbound', () {
    test('latitude increases when heading north', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final predicted = state.predict(const Duration(seconds: 1));

      expect(predicted.latitude, greaterThan(state.latitude));
      expect(predicted.extrapolationCount, equals(1));
    });

    test('longitude unchanged when heading due north', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final predicted = state.predict(const Duration(seconds: 1));

      // Longitude should be essentially unchanged for due north heading.
      expect(predicted.longitude, closeTo(state.longitude, 1e-10));
    });

    test('distance matches speed * time', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final dt = const Duration(seconds: 10);
      final predicted = state.predict(dt);

      // Expected distance: 13.89 m/s * 10s = 138.9m
      // In degrees latitude: 138.9 / 111320 ≈ 0.001248
      final dLat = predicted.latitude - state.latitude;
      expect(dLat, closeTo(138.9 / 111320.0, 1e-6));
    });
  });

  group('DeadReckoningState.predict — eastbound', () {
    test('longitude increases when heading east', () {
      final state = DeadReckoningState.fromGeoPosition(_eastboundFix)!;
      final predicted = state.predict(const Duration(seconds: 1));

      expect(predicted.longitude, greaterThan(state.longitude));
    });

    test('latitude unchanged when heading due east', () {
      final state = DeadReckoningState.fromGeoPosition(_eastboundFix)!;
      final predicted = state.predict(const Duration(seconds: 1));

      expect(predicted.latitude, closeTo(state.latitude, 1e-10));
    });
  });

  group('DeadReckoningState.predict — NW heading (315°)', () {
    test('latitude increases and longitude decreases for NW heading', () {
      final state = DeadReckoningState.fromGeoPosition(_nwFix)!;
      final predicted = state.predict(const Duration(seconds: 1));

      expect(predicted.latitude, greaterThan(state.latitude));
      expect(predicted.longitude, lessThan(state.longitude));
    });
  });

  group('DeadReckoningState.predict — edge cases', () {
    test('stationary vehicle does not move', () {
      final state = DeadReckoningState.fromGeoPosition(_stationaryFix)!;
      final predicted = state.predict(const Duration(seconds: 10));

      expect(predicted.latitude, equals(state.latitude));
      expect(predicted.longitude, equals(state.longitude));
      expect(predicted.extrapolationCount, equals(1));
    });

    test('extrapolation count increments with each predict', () {
      var state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      expect(state.extrapolationCount, equals(0));

      state = state.predict(const Duration(seconds: 1));
      expect(state.extrapolationCount, equals(1));

      state = state.predict(const Duration(seconds: 1));
      expect(state.extrapolationCount, equals(2));

      state = state.predict(const Duration(seconds: 1));
      expect(state.extrapolationCount, equals(3));
    });

    test('large dt (60s) produces reasonable Nagoya-area coordinates', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final predicted = state.predict(const Duration(seconds: 60));

      // 13.89 m/s * 60s = 833.4m north ≈ 0.00749°
      // Should still be in Nagoya area (35.x, 136.x)
      expect(predicted.latitude, greaterThan(35.0));
      expect(predicted.latitude, lessThan(36.0));
      expect(predicted.longitude, closeTo(136.8815, 0.01));
    });

    test('heading near 360° wraps correctly', () {
      final fix = GeoPosition(
        latitude: 35.1709,
        longitude: 136.8815,
        accuracy: 5.0,
        speed: 13.89,
        heading: 350.0, // almost due north, slightly west
        timestamp: _baseTime,
      );
      final state = DeadReckoningState.fromGeoPosition(fix)!;
      final predicted = state.predict(const Duration(seconds: 1));

      // Should move mostly north, very slightly west
      expect(predicted.latitude, greaterThan(state.latitude));
      expect(predicted.longitude, lessThan(state.longitude));
    });
  });

  group('DeadReckoningState.accuracyAt — degradation', () {
    test('accuracy degrades at 5m/sec from GPS loss', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;

      final at0 = state.accuracyAt(_baseTime);
      expect(at0, equals(5.0)); // base accuracy

      final at10 = state.accuracyAt(
        _baseTime.add(const Duration(seconds: 10)),
      );
      expect(at10, equals(55.0)); // 5 + 5*10

      final at30 = state.accuracyAt(
        _baseTime.add(const Duration(seconds: 30)),
      );
      expect(at30, equals(155.0)); // 5 + 5*30
    });

    test('accuracy at GPS time equals base accuracy', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      expect(state.accuracyAt(_baseTime), equals(state.baseAccuracy));
    });
  });

  group('DeadReckoningState.toGeoPosition', () {
    test('produces GeoPosition with correct fields', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final now = _baseTime.add(const Duration(seconds: 5));
      final pos = state.toGeoPosition(now: now);

      expect(pos.latitude, equals(state.latitude));
      expect(pos.longitude, equals(state.longitude));
      expect(pos.speed, equals(state.speed));
      expect(pos.heading, equals(state.heading));
      expect(pos.timestamp, equals(now));
      expect(pos.accuracy, equals(30.0)); // 5 + 5*5
    });

    test('accuracy reflects time since GPS loss', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;

      final early = state.toGeoPosition(
        now: _baseTime.add(const Duration(seconds: 2)),
      );
      expect(early.accuracy, equals(15.0)); // 5 + 5*2

      final late = state.toGeoPosition(
        now: _baseTime.add(const Duration(seconds: 20)),
      );
      expect(late.accuracy, equals(105.0)); // 5 + 5*20

      // Early position is navigation-grade, late is not.
      expect(early.isNavigationGrade, isTrue);
      expect(late.isNavigationGrade, isFalse);
    });
  });

  group('DeadReckoningState — safety boundary', () {
    test('maxAccuracy is 500m', () {
      expect(DeadReckoningState.maxAccuracy, equals(500.0));
    });

    test('degradationRate is 5m/sec', () {
      expect(DeadReckoningState.degradationRate, equals(5.0));
    });

    test('isAccuracyExceeded after ~99 seconds with 5m base', () {
      // 5 + 5*99 = 500 (exactly at cap)
      // 5 + 5*100 = 505 (over cap)
      // The method uses DateTime.now() so we test the concept via accuracyAt
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final at99 = state.accuracyAt(
        _baseTime.add(const Duration(seconds: 99)),
      );
      expect(at99, equals(500.0)); // exactly at cap

      final at100 = state.accuracyAt(
        _baseTime.add(const Duration(seconds: 100)),
      );
      expect(at100, greaterThan(500.0)); // over cap
    });
  });

  group('DeadReckoningState — canExtrapolate', () {
    test('true when speed and heading are valid', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      expect(state.canExtrapolate, isTrue);
    });

    test('true for stationary (speed = 0)', () {
      final state = DeadReckoningState.fromGeoPosition(_stationaryFix)!;
      expect(state.canExtrapolate, isTrue);
    });
  });

  group('DeadReckoningState — Equatable', () {
    test('equal states are equal', () {
      final a = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final b = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      expect(a, equals(b));
    });

    test('different states are not equal', () {
      final a = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final b = DeadReckoningState.fromGeoPosition(_eastboundFix)!;
      expect(a, isNot(equals(b)));
    });
  });

  group('DeadReckoningState.toString', () {
    test('includes coordinates and speed', () {
      final state = DeadReckoningState.fromGeoPosition(_northboundFix)!;
      final s = state.toString();
      expect(s, contains('35.1709'));
      expect(s, contains('136.8815'));
      expect(s, contains('13.9'));
      expect(s, contains('steps=0'));
    });
  });
}
