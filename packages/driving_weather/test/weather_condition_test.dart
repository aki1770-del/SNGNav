library;

import 'package:driving_weather/driving_weather.dart';
import 'package:test/test.dart';

void main() {
  group('WeatherCondition model', () {
    final timestamp = DateTime(2026, 3, 12, 6);

    test('clear constructor provides non-hazard baseline values', () {
      final clear = WeatherCondition.clear(timestamp: timestamp);

      expect(clear.precipType, PrecipitationType.none);
      expect(clear.intensity, PrecipitationIntensity.none);
      expect(clear.isSnowing, isFalse);
      expect(clear.isHazardous, isFalse);
      expect(clear.props, [
        PrecipitationType.none,
        PrecipitationIntensity.none,
        5.0,
        10000.0,
        0.0,
        false,
        timestamp,
      ]);
      expect(clear.toString(), 'WeatherCondition(none none, 5.0°C, vis=10000m, wind=0km/h)');
    });

    test('snow with none intensity is not snowing', () {
      final condition = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.none,
        temperatureCelsius: -1,
        visibilityMeters: 5000,
        windSpeedKmh: 10,
        timestamp: timestamp,
      );

      expect(condition.isSnowing, isFalse);
    });

    test('very low visibility alone is hazardous and freezing is thresholded', () {
      final condition = WeatherCondition(
        precipType: PrecipitationType.rain,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 0,
        visibilityMeters: 150,
        windSpeedKmh: 22,
        timestamp: timestamp,
      );

      expect(condition.hasReducedVisibility, isTrue);
      expect(condition.isHazardous, isTrue);
      expect(condition.isFreezing, isTrue);
      expect(condition.toString(), contains('vis=150m'));
    });

    test('ice risk is reflected in props and toString', () {
      final condition = WeatherCondition(
        precipType: PrecipitationType.sleet,
        intensity: PrecipitationIntensity.moderate,
        temperatureCelsius: -3,
        visibilityMeters: 800,
        windSpeedKmh: 15,
        iceRisk: true,
        timestamp: timestamp,
      );

      expect(condition.props.last, timestamp);
      expect(condition.toString(), contains(', ICE'));
    });
  });
}