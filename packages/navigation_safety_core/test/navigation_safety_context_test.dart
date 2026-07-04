import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('DrivingContext', () {
    test('default constructor leaves all fields null', () {
      const ctx = DrivingContext();
      expect(ctx.speedMps, isNull);
      expect(ctx.humidityRH, isNull);
      expect(ctx.timeSincePrecipitation, isNull);
      expect(ctx.ambientTempCelsius, isNull);
    });

    test('all fields can be set explicitly', () {
      const ctx = DrivingContext(
        speedMps: 20.0,
        humidityRH: 0.85,
        timeSincePrecipitation: Duration(minutes: 15),
        ambientTempCelsius: -1.0,
      );
      expect(ctx.speedMps, 20.0);
      expect(ctx.humidityRH, 0.85);
      expect(ctx.timeSincePrecipitation, const Duration(minutes: 15));
      expect(ctx.ambientTempCelsius, -1.0);
    });

    test('value equality holds for identical fields', () {
      const a = DrivingContext(speedMps: 10.0, humidityRH: 0.5);
      const b = DrivingContext(speedMps: 10.0, humidityRH: 0.5);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('value equality differentiates by field', () {
      const a = DrivingContext(speedMps: 10.0);
      const b = DrivingContext(speedMps: 11.0);
      expect(a, isNot(equals(b)));
    });

    test('toString surfaces field values for debugging', () {
      const ctx = DrivingContext(speedMps: 16.7);
      final s = ctx.toString();
      expect(s, contains('16.7'));
    });

    test('default constructor is const-constructible', () {
      const a = DrivingContext();
      const b = DrivingContext();
      expect(identical(a, b), isTrue);
    });
  });

  group('DrivingContext.withPercentHumidity — the percent door', () {
    // Weather APIs (MET Norway relative_humidity) and the pretrip_*
    // packages carry RH in PERCENT; core's humidityRH is a FRACTION.
    // This factory is the seam that cannot be wired wrong.
    test('converts percent to the fraction contract', () {
      final ctx = DrivingContext.withPercentHumidity(humidityPercent: 95.0);
      expect(ctx.humidityRH, closeTo(0.95, 1e-12));
    });

    test('null percent stays null (unknown humidity)', () {
      final ctx = DrivingContext.withPercentHumidity(ambientTempCelsius: 1.0);
      expect(ctx.humidityRH, isNull);
      expect(ctx.ambientTempCelsius, 1.0);
    });

    test('carries the other fields through unchanged', () {
      final ctx = DrivingContext.withPercentHumidity(
        speedMps: 8.0,
        humidityPercent: 80.0,
        timeSincePrecipitation: const Duration(minutes: 30),
        ambientTempCelsius: -1.0,
        vehicleClassToken: 'kei-car',
      );
      expect(ctx.speedMps, 8.0);
      expect(ctx.humidityRH, closeTo(0.80, 1e-12));
      expect(ctx.timeSincePrecipitation, const Duration(minutes: 30));
      expect(ctx.ambientTempCelsius, -1.0);
      expect(ctx.vehicleClassToken, 'kei-car');
    });

    test('rejects out-of-range and non-finite percent', () {
      for (final bad in [0.0, -5.0, 100.1, 250.0, double.nan, double.infinity]) {
        expect(
          () => DrivingContext.withPercentHumidity(humidityPercent: bad),
          throwsArgumentError,
          reason: 'percent $bad must be rejected',
        );
      }
      // 100% RH (saturated air) is a legal reading.
      final saturated =
          DrivingContext.withPercentHumidity(humidityPercent: 100.0);
      expect(saturated.humidityRH, closeTo(1.0, 1e-12));
    });

    test('END-TO-END: a MET-Norway-style percent reading reaches the '
        'black-ice calibration instead of throwing', () {
      // This is the loaded-gun scenario the factory exists to close: the
      // exact wiring that previously threw ArgumentError in bad weather.
      final cfg = NavigationSafetyConfig.forProfileWithContext(
        DriverProfile.snowZoneExperienced,
        context: DrivingContext.withPercentHumidity(
          humidityPercent: 95.0, // as MET Norway relative_humidity delivers
          ambientTempCelsius: 1.0,
          speedMps: 8.0,
        ),
      );
      // The humidity-lifted warning temperature holds the caution-add-only
      // invariant relative to the baseline.
      final base = NavigationSafetyConfig.forProfile(
        DriverProfile.snowZoneExperienced,
      );
      expect(cfg.warningTemperatureCelsius,
          greaterThanOrEqualTo(base.warningTemperatureCelsius));
    });
  });
}
