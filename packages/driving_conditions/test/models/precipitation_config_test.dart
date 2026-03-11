import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';

WeatherCondition _condition({
  PrecipitationType precipType = PrecipitationType.none,
  PrecipitationIntensity intensity = PrecipitationIntensity.none,
}) =>
    WeatherCondition(
      precipType: precipType,
      intensity: intensity,
      temperatureCelsius: 5.0,
      visibilityMeters: 10000,
      windSpeedKmh: 0,
      timestamp: DateTime(2026),
    );

void main() {
  group('PrecipitationConfig.fromCondition', () {
    test('no precip → none', () {
      final config = PrecipitationConfig.fromCondition(_condition());
      expect(config, PrecipitationConfig.none);
      expect(config.particleCount, 0);
    });

    test('light snow → 150 particles, slow velocity', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
      ));
      expect(config.particleCount, 150);
      expect(config.minVelocity, 2.0);
      expect(config.maxVelocity, 4.0);
      expect(config.minSize, 2.0);
      expect(config.maxSize, 6.0);
      expect(config.lifetime, 4.0);
    });

    test('heavy rain → 500 particles, fast velocity', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.heavy,
      ));
      expect(config.particleCount, 500);
      expect(config.minVelocity, 7.0);
      expect(config.maxVelocity, 12.0);
      expect(config.minSize, 1.0);
      expect(config.maxSize, 3.0);
      expect(config.lifetime, 1.5);
    });

    test('moderate sleet → 300 particles', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.sleet,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.particleCount, 300);
      expect(config.minVelocity, 4.0);
      expect(config.maxVelocity, 8.0);
      expect(config.minSize, 1.5);
      expect(config.maxSize, 4.0);
      expect(config.lifetime, 2.5);
    });

    test('hail light → 150 particles, high velocity', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.hail,
        intensity: PrecipitationIntensity.light,
      ));
      expect(config.particleCount, 150);
      expect(config.minVelocity, 8.0);
      expect(config.maxVelocity, 15.0);
      expect(config.minSize, 3.0);
      expect(config.maxSize, 8.0);
      expect(config.lifetime, 1.0);
    });

    test('precip type none suppresses particles', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.none,
        intensity: PrecipitationIntensity.heavy,
      ));
      expect(config, PrecipitationConfig.none);
    });

    test('intensity none suppresses particles', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.none,
      ));
      expect(config, PrecipitationConfig.none);
    });

    test('equatable works', () {
      final a = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
      ));
      final b = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
      ));
      expect(a, equals(b));
    });
  });
}
