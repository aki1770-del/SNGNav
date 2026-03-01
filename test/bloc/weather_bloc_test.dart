/// WeatherBloc unit tests — weather condition monitoring state machine.
///
/// Tests model properties, state getters, event equality, provider
/// simulation, and BLoC state transitions with a mock provider.
///
/// Sprint 7 Day 7 — WeatherBloc extraction.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/models/weather_condition.dart';
import 'package:sngnav_snow_scene/providers/simulated_weather_provider.dart';
import 'package:sngnav_snow_scene/providers/weather_provider.dart';

// ---------------------------------------------------------------------------
// Mock provider — controllable stream for testing
// ---------------------------------------------------------------------------
class MockWeatherProvider implements WeatherProvider {
  final _controller = StreamController<WeatherCondition>.broadcast();
  bool started = false;
  bool stopped = false;
  bool disposed = false;
  bool shouldThrowOnStart = false;

  @override
  Stream<WeatherCondition> get conditions => _controller.stream;

  @override
  Future<void> startMonitoring() async {
    if (shouldThrowOnStart) {
      throw Exception('Weather service unavailable');
    }
    started = true;
  }

  @override
  Future<void> stopMonitoring() async {
    stopped = true;
  }

  @override
  void dispose() {
    disposed = true;
    _controller.close();
  }

  void emitCondition(WeatherCondition condition) {
    _controller.add(condition);
  }

  void emitError(Object error) {
    _controller.addError(error);
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
final _ts = DateTime(2026, 2, 27, 10, 0);

final _clearCondition = WeatherCondition.clear(timestamp: _ts);

final _lightSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: 1.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: _ts,
);

final _heavySnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -4.0,
  visibilityMeters: 150,
  windSpeedKmh: 45,
  timestamp: _ts,
);

final _iceRisk = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: -3.0,
  visibilityMeters: 500,
  windSpeedKmh: 20,
  iceRisk: true,
  timestamp: _ts,
);

final _rain = WeatherCondition(
  precipType: PrecipitationType.rain,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: 8.0,
  visibilityMeters: 2000,
  windSpeedKmh: 25,
  timestamp: _ts,
);

final _zeroVisibility = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: -2.0,
  visibilityMeters: 100,
  windSpeedKmh: 30,
  timestamp: _ts,
);

void main() {
  // -------------------------------------------------------------------------
  // WeatherCondition model tests
  // -------------------------------------------------------------------------
  group('WeatherCondition model', () {
    test('clear has expected defaults', () {
      expect(_clearCondition.precipType, PrecipitationType.none);
      expect(_clearCondition.intensity, PrecipitationIntensity.none);
      expect(_clearCondition.temperatureCelsius, 5.0);
      expect(_clearCondition.visibilityMeters, 10000.0);
      expect(_clearCondition.windSpeedKmh, 0.0);
      expect(_clearCondition.iceRisk, false);
    });

    test('isSnowing returns true for snow with intensity', () {
      expect(_lightSnow.isSnowing, true);
      expect(_heavySnow.isSnowing, true);
    });

    test('isSnowing returns false for clear and rain', () {
      expect(_clearCondition.isSnowing, false);
      expect(_rain.isSnowing, false);
    });

    test('hasReducedVisibility true when < 1000m', () {
      expect(_heavySnow.hasReducedVisibility, true); // 150m
      expect(_iceRisk.hasReducedVisibility, true); // 500m
      expect(_lightSnow.hasReducedVisibility, false); // 3000m
      expect(_clearCondition.hasReducedVisibility, false); // 10000m
    });

    test('isHazardous true for heavy precip', () {
      expect(_heavySnow.isHazardous, true);
    });

    test('isHazardous true for ice risk', () {
      expect(_iceRisk.isHazardous, true);
    });

    test('isHazardous true for very low visibility', () {
      expect(_zeroVisibility.isHazardous, true); // 100m < 200m
    });

    test('isHazardous false for light snow', () {
      expect(_lightSnow.isHazardous, false);
    });

    test('isFreezing true at and below 0°C', () {
      expect(_heavySnow.isFreezing, true); // -4°C
      expect(_iceRisk.isFreezing, true); // -3°C
      expect(
        WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 0.0,
          visibilityMeters: 5000,
          windSpeedKmh: 10,
          timestamp: _ts,
        ).isFreezing,
        true,
      ); // exactly 0°C
    });

    test('isFreezing false above 0°C', () {
      expect(_lightSnow.isFreezing, false); // 1°C
      expect(_clearCondition.isFreezing, false); // 5°C
    });

    test('toString includes key fields', () {
      final s = _heavySnow.toString();
      expect(s, contains('snow'));
      expect(s, contains('heavy'));
      expect(s, contains('-4.0'));
    });

    test('Equatable: same values are equal', () {
      final a = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: 1.0,
        visibilityMeters: 3000,
        windSpeedKmh: 15,
        timestamp: _ts,
      );
      expect(a, equals(_lightSnow));
    });

    test('Equatable: different values are not equal', () {
      expect(_lightSnow, isNot(equals(_heavySnow)));
    });
  });

  // -------------------------------------------------------------------------
  // WeatherState tests
  // -------------------------------------------------------------------------
  group('WeatherState', () {
    test('unavailable has expected defaults', () {
      const state = WeatherState.unavailable();
      expect(state.status, WeatherStatus.unavailable);
      expect(state.condition, isNull);
      expect(state.errorMessage, isNull);
      expect(state.isMonitoring, false);
      expect(state.hasCondition, false);
    });

    test('convenience getters return false when no condition', () {
      const state = WeatherState.unavailable();
      expect(state.isHazardous, false);
      expect(state.isSnowing, false);
      expect(state.hasIceRisk, false);
      expect(state.hasReducedVisibility, false);
    });

    test('convenience getters delegate to condition', () {
      final state = WeatherState(
        status: WeatherStatus.monitoring,
        condition: _heavySnow,
      );
      expect(state.isHazardous, true);
      expect(state.isSnowing, true);
      expect(state.hasReducedVisibility, true);
    });

    test('hasIceRisk delegates correctly', () {
      final state = WeatherState(
        status: WeatherStatus.monitoring,
        condition: _iceRisk,
      );
      expect(state.hasIceRisk, true);
    });

    test('copyWith updates fields', () {
      final state = WeatherState(
        status: WeatherStatus.monitoring,
        condition: _lightSnow,
      );
      final updated = state.copyWith(condition: _heavySnow);
      expect(updated.condition, _heavySnow);
      expect(updated.status, WeatherStatus.monitoring);
    });

    test('copyWith clearCondition removes condition', () {
      final state = WeatherState(
        status: WeatherStatus.monitoring,
        condition: _lightSnow,
      );
      final cleared = state.copyWith(
        status: WeatherStatus.unavailable,
        clearCondition: true,
      );
      expect(cleared.condition, isNull);
    });

    test('toString includes status', () {
      const state = WeatherState.unavailable();
      expect(state.toString(), contains('unavailable'));
    });
  });

  // -------------------------------------------------------------------------
  // WeatherEvent tests
  // -------------------------------------------------------------------------
  group('WeatherEvent', () {
    test('events are Equatable', () {
      expect(
        const WeatherMonitorStarted(),
        equals(const WeatherMonitorStarted()),
      );
      expect(
        WeatherConditionReceived(_lightSnow),
        equals(WeatherConditionReceived(_lightSnow)),
      );
      expect(
        const WeatherErrorOccurred('fail'),
        equals(const WeatherErrorOccurred('fail')),
      );
    });

    test('different conditions produce unequal events', () {
      expect(
        WeatherConditionReceived(_lightSnow),
        isNot(equals(WeatherConditionReceived(_heavySnow))),
      );
    });
  });

  // -------------------------------------------------------------------------
  // SimulatedWeatherProvider tests
  // -------------------------------------------------------------------------
  group('SimulatedWeatherProvider', () {
    test('emits conditions on start', () async {
      final provider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 50),
      );
      final conditions = <WeatherCondition>[];
      provider.conditions.listen(conditions.add);

      await provider.startMonitoring();
      // First condition emitted immediately
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(conditions, hasLength(1));
      expect(conditions.first.precipType, PrecipitationType.none); // phase 0

      provider.dispose();
    });

    test('cycles through 6 phases', () async {
      final provider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 20),
      );
      final conditions = <WeatherCondition>[];
      provider.conditions.listen(conditions.add);

      await provider.startMonitoring();
      // Wait for all 6 phases + 1 cycle restart
      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(conditions.length, greaterThanOrEqualTo(6));
      // Phase 0: clear
      expect(conditions[0].precipType, PrecipitationType.none);
      // Phase 1: light snow
      expect(conditions[1].precipType, PrecipitationType.snow);
      expect(conditions[1].intensity, PrecipitationIntensity.light);
      // Phase 3: heavy snow
      expect(conditions[3].intensity, PrecipitationIntensity.heavy);
      // Phase 4: ice risk
      expect(conditions[4].iceRisk, true);

      provider.dispose();
    });

    test('stopMonitoring stops emissions', () async {
      final provider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 20),
      );
      final conditions = <WeatherCondition>[];
      provider.conditions.listen(conditions.add);

      await provider.startMonitoring();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await provider.stopMonitoring();
      final countAfterStop = conditions.length;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(conditions.length, countAfterStop);

      provider.dispose();
    });

    test('dispose closes stream', () async {
      final provider = SimulatedWeatherProvider();
      // Access conditions to create controller
      final sub = provider.conditions.listen((_) {});
      provider.dispose();
      await sub.cancel();
      // No error means clean disposal
    });
  });

  // -------------------------------------------------------------------------
  // WeatherBloc state machine tests
  // -------------------------------------------------------------------------
  group('WeatherBloc', () {
    late MockWeatherProvider provider;

    setUp(() {
      provider = MockWeatherProvider();
    });

    test('initial state is unavailable', () {
      final bloc = WeatherBloc(provider: provider);
      expect(bloc.state, const WeatherState.unavailable());
      bloc.close();
    });

    blocTest<WeatherBloc, WeatherState>(
      'emits monitoring on start',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) => bloc.add(const WeatherMonitorStarted()),
      expect: () => [
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring)
            .having((s) => s.condition, 'condition', isNull),
      ],
      verify: (_) {
        expect(provider.started, true);
      },
    );

    blocTest<WeatherBloc, WeatherState>(
      'emits monitoring with condition on update',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_lightSnow);
      },
      expect: () => [
        // First: monitoring (no condition yet)
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring)
            .having((s) => s.condition, 'condition', isNull),
        // Second: monitoring with condition
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring)
            .having((s) => s.condition, 'condition', _lightSnow),
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'updates condition on each emission',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_clearCondition);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_lightSnow);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_heavySnow);
      },
      expect: () => [
        // monitoring (empty)
        isA<WeatherState>()
            .having((s) => s.condition, 'condition', isNull),
        // clear
        isA<WeatherState>()
            .having((s) => s.condition, 'condition', _clearCondition),
        // light snow
        isA<WeatherState>()
            .having((s) => s.condition, 'condition', _lightSnow),
        // heavy snow
        isA<WeatherState>()
            .having((s) => s.condition, 'condition', _heavySnow)
            .having((s) => s.isHazardous, 'isHazardous', true),
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'emits unavailable on stop',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_lightSnow);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const WeatherMonitorStopped());
      },
      expect: () => [
        // monitoring (empty)
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring),
        // monitoring (light snow)
        isA<WeatherState>()
            .having((s) => s.condition, 'condition', _lightSnow),
        // stopped
        const WeatherState.unavailable(),
      ],
      verify: (_) {
        expect(provider.stopped, true);
      },
    );

    blocTest<WeatherBloc, WeatherState>(
      'ignores duplicate start when already monitoring',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const WeatherMonitorStarted()); // duplicate — ignored
      },
      expect: () => [
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring),
        // No second emission — idempotent
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'emits error on provider start failure',
      build: () {
        provider.shouldThrowOnStart = true;
        return WeatherBloc(provider: provider);
      },
      act: (bloc) => bloc.add(const WeatherMonitorStarted()),
      expect: () => [
        // First: monitoring attempt
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring),
        // Then: error
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.error)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              contains('Weather service unavailable'),
            ),
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'emits error on stream error',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitError(Exception('Sensor failure'));
      },
      expect: () => [
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring),
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.error)
            .having(
              (s) => s.errorMessage,
              'errorMessage',
              contains('Sensor failure'),
            ),
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'recovers from error on restart',
      build: () => WeatherBloc(provider: provider),
      seed: () => const WeatherState(
        status: WeatherStatus.error,
        errorMessage: 'previous error',
      ),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_lightSnow);
      },
      expect: () => [
        // Back to monitoring
        isA<WeatherState>()
            .having((s) => s.status, 'status', WeatherStatus.monitoring),
        // Condition received
        isA<WeatherState>()
            .having((s) => s.condition, 'condition', _lightSnow),
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'hazardous condition detected via state getter',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_iceRisk);
      },
      expect: () => [
        isA<WeatherState>()
            .having((s) => s.isHazardous, 'isHazardous', false),
        isA<WeatherState>()
            .having((s) => s.isHazardous, 'isHazardous', true)
            .having((s) => s.hasIceRisk, 'hasIceRisk', true)
            .having((s) => s.isSnowing, 'isSnowing', true),
      ],
    );

    blocTest<WeatherBloc, WeatherState>(
      'snow scene progression: clear → light → heavy → ice → clearing',
      build: () => WeatherBloc(provider: provider),
      act: (bloc) async {
        bloc.add(const WeatherMonitorStarted());
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_clearCondition);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_lightSnow);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_heavySnow);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_iceRisk);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        provider.emitCondition(_lightSnow);
      },
      expect: () => [
        // monitoring (empty)
        isA<WeatherState>().having((s) => s.hasCondition, 'has', false),
        // clear — not hazardous
        isA<WeatherState>()
            .having((s) => s.isSnowing, 'snow', false)
            .having((s) => s.isHazardous, 'haz', false),
        // light snow — snowing but not hazardous
        isA<WeatherState>()
            .having((s) => s.isSnowing, 'snow', true)
            .having((s) => s.isHazardous, 'haz', false),
        // heavy snow — hazardous
        isA<WeatherState>()
            .having((s) => s.isSnowing, 'snow', true)
            .having((s) => s.isHazardous, 'haz', true),
        // ice risk — hazardous
        isA<WeatherState>()
            .having((s) => s.hasIceRisk, 'ice', true)
            .having((s) => s.isHazardous, 'haz', true),
        // clearing (light snow) — no longer hazardous
        isA<WeatherState>()
            .having((s) => s.isSnowing, 'snow', true)
            .having((s) => s.isHazardous, 'haz', false),
      ],
    );

    test('close disposes provider', () async {
      final bloc = WeatherBloc(provider: provider);
      await bloc.close();
      expect(provider.disposed, true);
    });
  });
}
