import 'package:driving_weather/driving_weather.dart';
import 'package:snow_rendering/snow_rendering.dart';
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
      iceRisk: false,
      timestamp: DateTime(2026),
    );

void main() {
  group('PrecipitationConfig.fromCondition', () {
    test('no precipitation → none (zero particles)', () {
      final config = PrecipitationConfig.fromCondition(_condition());
      expect(config.particleCount, 0);
      expect(config, PrecipitationConfig.none);
    });

    test('precip type set but intensity none → none', () {
      final config = PrecipitationConfig.fromCondition(
        _condition(
          precipType: PrecipitationType.rain,
          intensity: PrecipitationIntensity.none,
        ),
      );
      expect(config, PrecipitationConfig.none);
    });

    test('snow light → 150 particles', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
      ));
      expect(config.particleCount, 150); // (0.3 * 500).round()
    });

    test('snow moderate → 300 particles', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.particleCount, 300); // (0.6 * 500).round()
    });

    test('snow heavy → 500 particles', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
      ));
      expect(config.particleCount, 500); // (1.0 * 500).round()
    });

    test('snow velocity range: minVelocity=2.0, maxVelocity=4.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minVelocity, 2.0);
      expect(config.maxVelocity, 4.0);
    });

    test('snow size range: minSize=2.0, maxSize=6.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minSize, 2.0);
      expect(config.maxSize, 6.0);
    });

    test('snow lifetime = 4.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.lifetime, 4.0);
    });

    test('rain velocity range: minVelocity=7.0, maxVelocity=12.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minVelocity, 7.0);
      expect(config.maxVelocity, 12.0);
    });

    test('rain size range: minSize=1.0, maxSize=3.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minSize, 1.0);
      expect(config.maxSize, 3.0);
    });

    test('rain lifetime = 1.5', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.lifetime, 1.5);
    });

    test('sleet velocity range: minVelocity=4.0, maxVelocity=8.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.sleet,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minVelocity, 4.0);
      expect(config.maxVelocity, 8.0);
    });

    test('hail velocity range: minVelocity=8.0, maxVelocity=15.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.hail,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minVelocity, 8.0);
      expect(config.maxVelocity, 15.0);
    });

    test('hail size range: minSize=3.0, maxSize=8.0', () {
      final config = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.hail,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(config.minSize, 3.0);
      expect(config.maxSize, 8.0);
    });

    test('rain is faster than snow (maxVelocity)', () {
      final rain = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.moderate,
      ));
      final snow = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(rain.maxVelocity, greaterThan(snow.maxVelocity));
    });

    test('snow has larger particles than rain (maxSize)', () {
      final rain = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.moderate,
      ));
      final snow = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
      ));
      expect(snow.maxSize, greaterThan(rain.maxSize));
    });

    test('heavy has more particles than light', () {
      final heavy = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.heavy,
      ));
      final light = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
      ));
      expect(heavy.particleCount, greaterThan(light.particleCount));
    });

    test('equality — same inputs produce equal configs', () {
      final a = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
      ));
      final b = PrecipitationConfig.fromCondition(_condition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
      ));
      expect(a, b);
    });
  });
}
