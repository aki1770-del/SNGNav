/// SimulatedWeatherProvider unit tests.
///
/// The simulator is the ONE legitimate caller of a complete "clear" value: it
/// ASSERTS a scenario, which is not a claim about the world. Every condition it
/// emits therefore carries [ObservationSource.simulated].
library;

import 'package:test/test.dart';

import 'package:driving_weather/driving_weather.dart';

/// The simulator never fails, so every reading is an observation.
WeatherCondition _conditionOf(WeatherReading reading) {
  expect(reading, isA<WeatherObserved>());
  return (reading as WeatherObserved).condition;
}

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
      final first = provider.conditions.first;
      await provider.startMonitoring();

      final reading = await first.timeout(const Duration(seconds: 2));
      expect(reading, isA<WeatherObserved>());
    });

    test(
      'every emission is labelled as simulated, never as measured',
      () async {
        final readings = <WeatherReading>[];
        final sub = provider.conditions.listen(readings.add);
        await provider.startMonitoring();

        await Future<void>.delayed(const Duration(milliseconds: 350));

        expect(readings, isNotEmpty);
        for (final r in readings) {
          expect(_conditionOf(r).source, ObservationSource.simulated);
        }

        await sub.cancel();
      },
    );

    test(
      'first emission is clear (Phase 0) — and says it is simulated',
      () async {
        final first = provider.conditions.first;
        await provider.startMonitoring();

        final c = _conditionOf(await first);
        expect(c.precipType, PrecipitationType.none);
        expect(c.snowing, SafetyVerdict.notHazardous);
        expect(c.source, ObservationSource.simulated);
        // A complete scenario, so an honest negative verdict is possible.
        expect(c.hazard, SafetyVerdict.notHazardous);
      },
    );

    test('second emission is light snow (Phase 1)', () async {
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(readings.length, greaterThanOrEqualTo(2));
      final c = _conditionOf(readings[1]);
      expect(c.precipType, PrecipitationType.snow);
      expect(c.intensity, PrecipitationIntensity.light);
      expect(c.temperatureCelsius, 1.0);

      await sub.cancel();
    });

    test('emits all 6 phases in sequence', () async {
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(readings.length, greaterThanOrEqualTo(6));

      expect(_conditionOf(readings[0]).precipType, PrecipitationType.none);
      expect(_conditionOf(readings[1]).intensity, PrecipitationIntensity.light);
      expect(
        _conditionOf(readings[2]).intensity,
        PrecipitationIntensity.moderate,
      );
      expect(_conditionOf(readings[3]).intensity, PrecipitationIntensity.heavy);
      expect(_conditionOf(readings[4]).iceRisk, isTrue);
      expect(_conditionOf(readings[5]).intensity, PrecipitationIntensity.light);
      expect(_conditionOf(readings[5]).temperatureCelsius, 0.0);

      await sub.cancel();
    });

    test('scenario cycles back to Phase 0 after Phase 5', () async {
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(readings.length, greaterThanOrEqualTo(7));
      expect(_conditionOf(readings[6]).precipType, PrecipitationType.none);

      await sub.cancel();
    });

    test('stopMonitoring stops emissions', () async {
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final countBeforeStop = readings.length;

      await provider.stopMonitoring();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(readings.length, countBeforeStop);

      await sub.cancel();
    });

    test('dispose stops timer and allows cleanup', () async {
      final readings = <WeatherReading>[];
      await provider.startMonitoring();
      final sub = provider.conditions.listen(readings.add);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      final countBeforeDispose = readings.length;

      provider.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(readings.length, countBeforeDispose);

      await sub.cancel();
    });

    test('Phase 3 (heavy snow) is hazardous', () async {
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 250));

      expect(readings.length, greaterThanOrEqualTo(4));
      final c = _conditionOf(readings[3]);
      expect(c.hazard, SafetyVerdict.hazardous);
      expect(c.intensity, PrecipitationIntensity.heavy);
      expect(c.visibilityMeters, 150);

      await sub.cancel();
    });

    test('Phase 4 (ice risk) has iceRisk = true', () async {
      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(readings.length, greaterThanOrEqualTo(5));
      final c = _conditionOf(readings[4]);
      expect(c.iceRisk, isTrue);
      expect(c.hazard, SafetyVerdict.hazardous);

      await sub.cancel();
    });

    test('custom interval is respected', () async {
      provider.dispose();
      provider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 200),
      );

      final readings = <WeatherReading>[];
      final sub = provider.conditions.listen(readings.add);
      await provider.startMonitoring();

      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(readings.length, 1);

      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(readings.length, 2);

      await sub.cancel();
    });
  });
}
