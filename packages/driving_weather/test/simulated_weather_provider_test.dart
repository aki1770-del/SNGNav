/// SimulatedWeatherProvider unit tests.
///
/// Tests:
///   1. conditions stream emits after startMonitoring
///   2. First emission is clear (Phase 0)
///   3. Second emission is light snow (Phase 1)
///   4. Emits all 6 phases in sequence
///   5. Scenario cycles back to Phase 0 after Phase 5
///   6. stopMonitoring stops emissions
///   7. dispose closes the stream
///   8. Phase 3 (heavy snow) is hazardous
///   9. Phase 4 (ice risk) has iceRisk = true
///  10. Custom interval is respected
library;

import 'package:test/test.dart';

import 'package:driving_weather/driving_weather.dart';

void main() {
  group('SimulatedWeatherProvider', () {
    late SimulatedWeatherProvider provider;

    setUp(() {
      provider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 50),
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('conditions stream emits after startMonitoring', () async {
      final firstCondition = provider.conditions.first;
      await provider.startMonitoring();

      final condition = await firstCondition.timeout(
        const Duration(seconds: 2),
      );
      expect(condition, isA<WeatherCondition>());
    });

    test('first emission is clear (Phase 0)', () async {
      final firstCondition = provider.conditions.first;
      await provider.startMonitoring();

      final condition = await firstCondition;
      expect(condition.precipType, PrecipitationType.none);
      expect(condition.isSnowing, false);
    });

    test('second emission is light snow (Phase 1)', () async {
      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      // Wait for two emissions (initial + first timer tick)
      await Future.delayed(const Duration(milliseconds: 100));

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions[1].precipType, PrecipitationType.snow);
      expect(emissions[1].intensity, PrecipitationIntensity.light);
      expect(emissions[1].temperatureCelsius, 1.0);

      await sub.cancel();
    });

    test('emits all 6 phases in sequence', () async {
      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      // Wait for all 6 phases (initial + 5 ticks at 50ms each)
      await Future.delayed(const Duration(milliseconds: 350));

      expect(emissions.length, greaterThanOrEqualTo(6));

      // Phase 0: clear
      expect(emissions[0].precipType, PrecipitationType.none);
      // Phase 1: light snow
      expect(emissions[1].intensity, PrecipitationIntensity.light);
      // Phase 2: moderate snow
      expect(emissions[2].intensity, PrecipitationIntensity.moderate);
      // Phase 3: heavy snow
      expect(emissions[3].intensity, PrecipitationIntensity.heavy);
      // Phase 4: moderate + ice
      expect(emissions[4].iceRisk, true);
      // Phase 5: light snow (clearing)
      expect(emissions[5].intensity, PrecipitationIntensity.light);
      expect(emissions[5].temperatureCelsius, 0.0);

      await sub.cancel();
    });

    test('scenario cycles back to Phase 0 after Phase 5', () async {
      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      // Wait for 7 emissions (full cycle + one more)
      await Future.delayed(const Duration(milliseconds: 400));

      expect(emissions.length, greaterThanOrEqualTo(7));
      // Phase 6 = Phase 0 (cycle)
      expect(emissions[6].precipType, PrecipitationType.none);

      await sub.cancel();
    });

    test('stopMonitoring stops emissions', () async {
      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      await Future.delayed(const Duration(milliseconds: 100));
      final countBeforeStop = emissions.length;

      await provider.stopMonitoring();
      await Future.delayed(const Duration(milliseconds: 150));

      // No new emissions after stop
      expect(emissions.length, countBeforeStop);

      await sub.cancel();
    });

    test('dispose stops timer and allows cleanup', () async {
      final emissions = <WeatherCondition>[];
      await provider.startMonitoring();
      final sub = provider.conditions.listen(emissions.add);

      await Future.delayed(const Duration(milliseconds: 100));
      final countBeforeDispose = emissions.length;

      provider.dispose();
      await Future.delayed(const Duration(milliseconds: 150));

      // No new emissions after dispose
      expect(emissions.length, countBeforeDispose);

      await sub.cancel();
    });

    test('Phase 3 (heavy snow) is hazardous', () async {
      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      await Future.delayed(const Duration(milliseconds: 250));

      expect(emissions.length, greaterThanOrEqualTo(4));
      expect(emissions[3].isHazardous, true);
      expect(emissions[3].intensity, PrecipitationIntensity.heavy);
      expect(emissions[3].visibilityMeters, 150);

      await sub.cancel();
    });

    test('Phase 4 (ice risk) has iceRisk = true', () async {
      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      await Future.delayed(const Duration(milliseconds: 300));

      expect(emissions.length, greaterThanOrEqualTo(5));
      expect(emissions[4].iceRisk, true);
      expect(emissions[4].isHazardous, true);

      await sub.cancel();
    });

    test('custom interval is respected', () async {
      provider.dispose();
      provider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 200),
      );

      final emissions = <WeatherCondition>[];
      final sub = provider.conditions.listen(emissions.add);
      await provider.startMonitoring();

      // After 150ms, only the initial emission should have fired
      await Future.delayed(const Duration(milliseconds: 150));
      expect(emissions.length, 1);

      // After 350ms total, 2 emissions (initial + 1 tick)
      await Future.delayed(const Duration(milliseconds: 200));
      expect(emissions.length, 2);

      await sub.cancel();
    });
  });
}
