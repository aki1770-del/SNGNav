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
}
