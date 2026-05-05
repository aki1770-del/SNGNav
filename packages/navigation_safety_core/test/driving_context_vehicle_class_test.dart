import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:test/test.dart';

void main() {
  group('DrivingContext.vehicleClassToken', () {
    test('default constructor leaves vehicleClassToken null', () {
      const ctx = DrivingContext();
      expect(ctx.vehicleClassToken, isNull);
    });

    test('vehicleClassToken can be set explicitly', () {
      const ctx = DrivingContext(vehicleClassToken: 'kei-car');
      expect(ctx.vehicleClassToken, 'kei-car');
    });

    test('value-equality differentiates by vehicleClassToken', () {
      const a = DrivingContext(speedMps: 10.0, vehicleClassToken: 'kei-car');
      const b = DrivingContext(speedMps: 10.0, vehicleClassToken: 'compact-sedan');
      expect(a, isNot(equals(b)));
    });

    test('value-equality holds when only vehicleClassToken matches', () {
      const a = DrivingContext(vehicleClassToken: 'kei-car');
      const b = DrivingContext(vehicleClassToken: 'kei-car');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('vehicleClassToken composes with all other fields independently', () {
      const ctx = DrivingContext(
        speedMps: 22.2,
        humidityRH: 0.85,
        timeSincePrecipitation: Duration(minutes: 15),
        ambientTempCelsius: -1.0,
        vehicleClassToken: '4wd',
      );
      expect(ctx.speedMps, 22.2);
      expect(ctx.humidityRH, 0.85);
      expect(ctx.timeSincePrecipitation, const Duration(minutes: 15));
      expect(ctx.ambientTempCelsius, -1.0);
      expect(ctx.vehicleClassToken, '4wd');
    });

    test('toString surfaces vehicleClassToken for debugging', () {
      const ctx = DrivingContext(vehicleClassToken: 'kei-car');
      final s = ctx.toString();
      expect(s, contains('kei-car'));
    });

    test('null-as-absent convention preserved across all five fields', () {
      const ctx = DrivingContext(speedMps: 18.0);
      // Only speedMps set; everything else null per absent convention.
      expect(ctx.speedMps, 18.0);
      expect(ctx.humidityRH, isNull);
      expect(ctx.timeSincePrecipitation, isNull);
      expect(ctx.ambientTempCelsius, isNull);
      expect(ctx.vehicleClassToken, isNull);
    });
  });
}
