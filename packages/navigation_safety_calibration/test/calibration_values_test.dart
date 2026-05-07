import 'dart:math' as math;

import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';
import 'package:test/test.dart';

void main() {
  group('computeSurfaceMoistureFraction (precipitation_history_decay)', () {
    test('returns 1.0 immediately after precipitation (t = 0)', () {
      final fraction = computeSurfaceMoistureFraction(
        timeSincePrecipitation: Duration.zero,
        ambientCelsius: 5.0,
      );
      expect(fraction, 1.0);
    });

    test('returns 0.5 at one default half-life (90 minutes)', () {
      final fraction = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 90),
        ambientCelsius: 5.0,
      );
      // exp(-ln2) == 0.5 by definition.
      expect(fraction, closeTo(0.5, 1e-9));
    });

    test('returns 0.25 at two default half-lives (180 minutes)', () {
      final fraction = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 180),
        ambientCelsius: 5.0,
      );
      expect(fraction, closeTo(0.25, 1e-9));
    });

    test('half-life parameter overrides default', () {
      final fraction = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 30),
        ambientCelsius: 5.0,
        evaporationHalfLifeMinutes: 30.0,
      );
      expect(fraction, closeTo(0.5, 1e-9));
    });

    test('rejects non-positive half-life', () {
      expect(
        () => computeSurfaceMoistureFraction(
          timeSincePrecipitation: const Duration(minutes: 1),
          ambientCelsius: 5.0,
          evaporationHalfLifeMinutes: 0.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative time-since-precipitation', () {
      expect(
        () => computeSurfaceMoistureFraction(
          timeSincePrecipitation: const Duration(minutes: -1),
          ambientCelsius: 5.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('determinism — same inputs produce identical outputs', () {
      final a = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 47),
        ambientCelsius: 3.2,
      );
      final b = computeSurfaceMoistureFraction(
        timeSincePrecipitation: const Duration(minutes: 47),
        ambientCelsius: 3.2,
      );
      expect(a, b);
    });
  });

  group('computeEffectiveTemperatureCelsius (Magnus formula)', () {
    test('saturated air (RH = 1.0) returns ambient (zero depression)', () {
      // At RH = 1.0, ln(RH) = 0, so dew point equals ambient and
      // depression is zero; effective temperature equals ambient.
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: 10.0,
        humidityRH: 1.0,
      );
      expect(t, closeTo(10.0, 1e-9));
    });

    test('dry air (RH ≈ 0.5) at 20 °C — Magnus dew point ≈ 9.27 °C', () {
      // Well-known Magnus result: at 20 °C, RH 50%, dew point ≈ 9.27 °C.
      // depression ≈ 10.73; effective ≈ ambient - depression ≈ 9.27 °C.
      // (effective = ambient - depression = ambient - (ambient - dewPoint)
      //  = dewPoint by construction.)
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: 20.0,
        humidityRH: 0.5,
      );
      expect(t, closeTo(9.27, 0.05));
    });

    test('rejects RH = 0.0 (ln(0) undefined)', () {
      expect(
        () => computeEffectiveTemperatureCelsius(
          ambientCelsius: 10.0,
          humidityRH: 0.0,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects RH > 1.0', () {
      expect(
        () => computeEffectiveTemperatureCelsius(
          ambientCelsius: 10.0,
          humidityRH: 1.01,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('determinism — same inputs produce identical outputs', () {
      final a = computeEffectiveTemperatureCelsius(
        ambientCelsius: 5.5,
        humidityRH: 0.7,
      );
      final b = computeEffectiveTemperatureCelsius(
        ambientCelsius: 5.5,
        humidityRH: 0.7,
      );
      expect(a, b);
    });
  });

  group('computeSpeedAdjustedVisibilityMeters', () {
    test('zero speed returns the per-profile baseline (lower bound)', () {
      final v = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 100.0,
        speedMps: 0.0,
        driverReactionTimeSeconds: 1.5,
      );
      expect(v, 100.0);
    });

    test('high speed lifts above the baseline (caution-add-only)', () {
      // 30 m/s × 1.5 s = 45 m reaction; 30² / (2 × 5.5) ≈ 81.82 m braking.
      // Total ≈ 126.82 m, larger than 100 m baseline.
      final v = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 100.0,
        speedMps: 30.0,
        driverReactionTimeSeconds: 1.5,
      );
      final expected = 30.0 * 1.5 + math.pow(30.0, 2) / (2.0 * 5.5);
      expect(v, closeTo(expected, 1e-9));
      expect(v, greaterThan(100.0));
    });

    test('lower deceleration (e.g. snow ≈ 3.0) raises required distance', () {
      final dryV = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 0.0,
        speedMps: 20.0,
        driverReactionTimeSeconds: 1.5,
        brakingDecelerationMps2: 5.5,
      );
      final snowV = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 0.0,
        speedMps: 20.0,
        driverReactionTimeSeconds: 1.5,
        brakingDecelerationMps2: 3.0,
      );
      expect(snowV, greaterThan(dryV));
    });

    test('rejects negative profile-base', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: -1.0,
          speedMps: 10.0,
          driverReactionTimeSeconds: 1.5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative speed', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 100.0,
          speedMps: -1.0,
          driverReactionTimeSeconds: 1.5,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('rejects negative reaction time', () {
      expect(
        () => computeSpeedAdjustedVisibilityMeters(
          profileBaseMeters: 100.0,
          speedMps: 10.0,
          driverReactionTimeSeconds: -0.1,
        ),
        throwsA(isA<ArgumentError>()),
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
        throwsA(isA<ArgumentError>()),
      );
    });

    test('determinism — same inputs produce identical outputs', () {
      final a = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 50.0,
        speedMps: 12.5,
        driverReactionTimeSeconds: 2.0,
      );
      final b = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: 50.0,
        speedMps: 12.5,
        driverReactionTimeSeconds: 2.0,
      );
      expect(a, b);
    });
  });
}
