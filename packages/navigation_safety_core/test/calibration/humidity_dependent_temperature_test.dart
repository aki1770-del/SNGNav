import 'package:navigation_safety_core/src/calibration/humidity_dependent_temperature.dart';
import 'package:test/test.dart';

void main() {
  group('computeEffectiveTemperatureCelsius', () {
    test('saturated air (RH=1.0) yields zero dew-point depression', () {
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: 5.0,
        humidityRH: 1.0,
      );
      // ambient - depression with depression = 0 → effective = ambient.
      expect(t, closeTo(5.0, 0.01));
    });

    test('dry air gives larger depression and lower effective temp', () {
      final dry = computeEffectiveTemperatureCelsius(
        ambientCelsius: 5.0,
        humidityRH: 0.2,
      );
      final humid = computeEffectiveTemperatureCelsius(
        ambientCelsius: 5.0,
        humidityRH: 0.95,
      );
      expect(dry, lessThan(humid));
    });

    test('typical winter morning (-5C, 80% RH) yields effective below ambient', () {
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: -5.0,
        humidityRH: 0.8,
      );
      expect(t, lessThan(-5.0));
    });

    test('black-ice scenario (2C, 95% RH) drops effective near 0C', () {
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: 2.0,
        humidityRH: 0.95,
      );
      // Dew-point depression at 95% RH is small (~1C); effective ~1C.
      expect(t, lessThan(2.0));
      expect(t, greaterThan(0.0));
    });

    test('black-ice scenario (3C, 60% RH) effective drops below 0C', () {
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: 3.0,
        humidityRH: 0.60,
      );
      // 60% RH at 3C dew-point ≈ -4.1C; depression ≈ 7.1C → effective ≈ -4.1C.
      expect(t, lessThan(0.0));
    });

    test('very low humidity at very low temp gives very low effective', () {
      final t = computeEffectiveTemperatureCelsius(
        ambientCelsius: -10.0,
        humidityRH: 0.1,
      );
      expect(t, lessThan(-30.0));
    });

    test('rejects RH = 0.0', () {
      expect(
        () => computeEffectiveTemperatureCelsius(
          ambientCelsius: 0.0,
          humidityRH: 0.0,
        ),
        throwsArgumentError,
      );
    });

    test('rejects RH > 1.0', () {
      expect(
        () => computeEffectiveTemperatureCelsius(
          ambientCelsius: 0.0,
          humidityRH: 1.1,
        ),
        throwsArgumentError,
      );
    });

    test('rejects negative RH', () {
      expect(
        () => computeEffectiveTemperatureCelsius(
          ambientCelsius: 0.0,
          humidityRH: -0.1,
        ),
        throwsArgumentError,
      );
    });
  });
}
