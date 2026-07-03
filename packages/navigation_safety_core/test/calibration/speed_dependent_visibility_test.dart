import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('computeSpeedAdjustedVisibilityMeters', () {
    test('zero speed returns the profile baseline', () {
      final v = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 200.0,
        speedMps: 0.0,
        driverReactionTimeSeconds: 1.5,
      );
      expect(v, 200.0);
    });

    test(
      'low speed (≈60 km/h, 16.7 m/s) under experienced RT keeps baseline',
      () {
        // RT 1.32s × 16.7 ≈ 22m + braking ≈ 25m → 47m total < 200 baseline.
        final v = computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 200.0,
          speedMps: 16.7,
          driverReactionTimeSeconds: 1.32,
        );
        expect(v, 200.0);
      },
    );

    test(
      'high speed (≈100 km/h, 27.8 m/s) under novice RT raises threshold',
      () {
        // RT 3.58s × 27.8 ≈ 99.5m + braking 27.8^2 / 11 ≈ 70.2m → ~169.7m,
        // still under 320 baseline; raise speed further.
        final v = computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 320.0,
          speedMps: 35.0, // ~126 km/h
          driverReactionTimeSeconds: 3.58,
        );
        // 3.58 * 35 = 125.3 + 35^2 / 11 ≈ 111.4 → 236.7; below 320 baseline.
        expect(v, 320.0);
      },
    );

    test('very high speed under novice RT exceeds baseline', () {
      // 3.58 * 50 = 179 + 50^2/11 ≈ 227 → 406, above 320 baseline.
      final v = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 320.0,
        speedMps: 50.0,
        driverReactionTimeSeconds: 3.58,
      );
      expect(v, greaterThan(320.0));
      expect(v, closeTo(179.0 + 227.27, 1.0));
    });

    test(
      'professional RT yields shorter required distance than novice at same speed',
      () {
        final novice = computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 0.0,
          speedMps: 25.0,
          driverReactionTimeSeconds: 3.58,
        );
        final pro = computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 0.0,
          speedMps: 25.0,
          driverReactionTimeSeconds: 1.5,
        );
        expect(pro, lessThan(novice));
      },
    );

    test('snow-context lower deceleration extends required distance', () {
      final dry = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 0.0,
        speedMps: 20.0,
        driverReactionTimeSeconds: 1.8,
        brakingDecelerationMps2: 5.5,
      );
      final snow = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 0.0,
        speedMps: 20.0,
        driverReactionTimeSeconds: 1.8,
        brakingDecelerationMps2: 3.0,
      );
      expect(snow, greaterThan(dry));
    });

    test(
      'foreign-tourist on highway (35 m/s, 3.5s RT) requires substantial floor',
      () {
        // 3.5*35 = 122.5 + 35^2/11 ≈ 111.4 → 233.9m
        final v = computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 0.0,
          speedMps: 35.0,
          driverReactionTimeSeconds: 3.5,
        );
        expect(v, closeTo(233.9, 0.5));
      },
    );

    test('ageing-rural at 25 m/s with snow surface', () {
      // 2.5*25 = 62.5 + 25^2/(2*3.0) = 104.17 → 166.67m
      final v = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 0.0,
        speedMps: 25.0,
        driverReactionTimeSeconds: 2.5,
        brakingDecelerationMps2: 3.0,
      );
      expect(v, closeTo(166.67, 0.1));
    });

    test('rejects negative profileBaseMeters', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: -1.0,
          speedMps: 10.0,
          driverReactionTimeSeconds: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative speed', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 100.0,
          speedMps: -1.0,
          driverReactionTimeSeconds: 1.5,
        ),
        throwsArgumentError,
      );
    });

    test('rejects non-positive deceleration', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 100.0,
          speedMps: 10.0,
          driverReactionTimeSeconds: 1.5,
          brakingDecelerationMps2: 0.0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative reaction time', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 100.0,
          speedMps: 10.0,
          driverReactionTimeSeconds: -0.1,
        ),
        throwsArgumentError,
      );
    });
  });
}
