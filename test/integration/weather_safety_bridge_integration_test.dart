/// Weather → Safety bridge integration tests.
///
/// Covers the widget-mediated coupling in WeatherStatusBar:
///   WeatherBloc isHazardous transitions false→true →
///   SafetyAlertReceived dispatched to NavigationBloc.
///
/// Three hazard triggers tested:
///   1. Ice risk → critical severity
///   2. Heavy precipitation → warning severity
///   3. Very low visibility (<200m) → warning severity
///
/// Also tests:
///   - No alert when weather stays non-hazardous
///   - No re-dispatch when weather stays hazardous
///   - Correct hazard message content for each trigger type
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';

import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/widgets/weather_status_bar.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _now = DateTime.now();

final _clearCondition = WeatherCondition.simulatedClear(timestamp: _now);

final _lightSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: 1.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: _now,
  source: ObservationSource.measured,
  iceRisk: false,
);

final _heavySnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -4.0,
  visibilityMeters: 300,
  windSpeedKmh: 45,
  timestamp: _now,
  source: ObservationSource.measured,
  iceRisk: false,
);

final _iceRisk = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: -3.0,
  visibilityMeters: 500,
  windSpeedKmh: 20,
  iceRisk: true,
  timestamp: _now,
  source: ObservationSource.measured,
);

/// her Akita radiative-frost morning: +2 °C, 70 % RH, clear sky, perfect
/// visibility. Raw `isHazardous` is FALSE — only the measured-humidity
/// classifier knows the road surface is frozen.
final _radiativeFrost = WeatherCondition(
  precipType: PrecipitationType.none,
  intensity: PrecipitationIntensity.none,
  temperatureCelsius: 2.0,
  visibilityMeters: 10000,
  windSpeedKmh: 5,
  humidityRH: 70,
  timestamp: _now,
  source: ObservationSource.measured,
  iceRisk: false,
);

final _lowVisibility = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: -1.0,
  visibilityMeters: 150,
  windSpeedKmh: 30,
  timestamp: _now,
  source: ObservationSource.measured,
  iceRisk: false,
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildWidget({
  required MockNavigationBloc navigationBloc,
  required MockWeatherBloc weatherBloc,
}) {
  return MaterialApp(
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<NavigationBloc>.value(value: navigationBloc),
          BlocProvider<WeatherBloc>.value(value: weatherBloc),
        ],
        child: const WeatherStatusBar(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late MockNavigationBloc navigationBloc;
  late MockWeatherBloc weatherBloc;

  setUpAll(() {
    registerFallbackValue(
      const SafetyAlertReceived(message: '', severity: AlertSeverity.info),
    );
  });

  setUp(() {
    navigationBloc = MockNavigationBloc();
    weatherBloc = MockWeatherBloc();

    when(() => navigationBloc.state).thenReturn(const NavigationState.idle());
  });

  group('Weather → Safety bridge: hazard triggers', () {
    testWidgets('ice risk → dispatches SafetyAlertReceived(critical)', (
      tester,
    ) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lightSnow,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      // Transition: non-hazardous → ice risk (hazardous)
      controller.add(
        WeatherState(status: WeatherStatus.monitoring, condition: _iceRisk),
      );
      await tester.pumpAndSettle();

      verify(
        () => navigationBloc.add(
          any(
            that: isA<SafetyAlertReceived>()
                .having((e) => e.severity, 'severity', AlertSeverity.critical)
                .having((e) => e.message, 'message', contains('ice')),
          ),
        ),
      ).called(1);

      await controller.close();
    });

    testWidgets('radiative frost (+2°C / 70% RH, raw isHazardous FALSE) → '
        'dispatches SafetyAlertReceived(warning) with the looks-wet '
        'ブラックアイスバーン line', (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _clearCondition,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      // The bond-#3 founding gap: this condition's raw isHazardous is
      // false, so the pre-fix status bar stayed SILENT on the exact
      // surface that looks safest.
      expect(_radiativeFrost.hazard, SafetyVerdict.notHazardous);

      controller.add(
        WeatherState(
          status: WeatherStatus.monitoring,
          condition: _radiativeFrost,
        ),
      );
      await tester.pumpAndSettle();

      verify(
        () => navigationBloc.add(
          any(
            that: isA<SafetyAlertReceived>()
                // Dew-point INFERENCE, not a surface measurement → warning
                // tier (critical stays reserved for the explicit feed flag).
                .having((e) => e.severity, 'severity', AlertSeverity.warning)
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    startsWith('ブラックアイスバーン'),
                    // The invisible-ice fact, possibility-graded.
                    contains('濡れて見え'),
                    contains('おそれ'),
                  ),
                ),
          ),
        ),
      ).called(1);

      await controller.close();
    });

    testWidgets(
      'standing radiative frost (alertable, not hazardous) ESCALATING to '
      'feed ice risk fires a SECOND dispatch at critical',
      (tester) async {
        // Pins the listenWhen escalation clause: without it, the widened
        // predicate swallows the frost-morning-turns-hazardous transition
        // (prev already alertable → no false→true edge) and the driver standing
        // warning never upgrades to the critical alert.
        final controller = StreamController<WeatherState>.broadcast();
        whenListen(
          weatherBloc,
          controller.stream,
          initialState: WeatherState(
            status: WeatherStatus.monitoring,
            condition: _clearCondition,
          ),
        );

        await tester.pumpWidget(
          _buildWidget(
            navigationBloc: navigationBloc,
            weatherBloc: weatherBloc,
          ),
        );
        await tester.pump();

        controller.add(
          WeatherState(
            status: WeatherStatus.monitoring,
            condition: _radiativeFrost,
          ),
        );
        await tester.pumpAndSettle();

        controller.add(
          WeatherState(status: WeatherStatus.monitoring, condition: _iceRisk),
        );
        await tester.pumpAndSettle();

        verify(
          () => navigationBloc.add(
            any(
              that: isA<SafetyAlertReceived>().having(
                (e) => e.severity,
                'severity',
                AlertSeverity.warning,
              ),
            ),
          ),
        ).called(1);
        verify(
          () => navigationBloc.add(
            any(
              that: isA<SafetyAlertReceived>().having(
                (e) => e.severity,
                'severity',
                AlertSeverity.critical,
              ),
            ),
          ),
        ).called(1);

        await controller.close();
      },
    );

    testWidgets('heavy snow → dispatches SafetyAlertReceived(warning)', (
      tester,
    ) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lightSnow,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      // Transition: light snow (non-hazardous) → heavy snow (hazardous)
      controller.add(
        WeatherState(status: WeatherStatus.monitoring, condition: _heavySnow),
      );
      await tester.pumpAndSettle();

      verify(
        () => navigationBloc.add(
          any(
            that: isA<SafetyAlertReceived>()
                .having((e) => e.severity, 'severity', AlertSeverity.warning)
                // Heavy snow at −4 °C classifies as compacted snow (圧雪) —
                // the message now names the surface the driver knows.
                .having((e) => e.message, 'message', contains('圧雪')),
          ),
        ),
      ).called(1);

      await controller.close();
    });

    testWidgets(
      'very low visibility (<200m) → dispatches SafetyAlertReceived(warning)',
      (tester) async {
        final controller = StreamController<WeatherState>.broadcast();
        whenListen(
          weatherBloc,
          controller.stream,
          initialState: WeatherState(
            status: WeatherStatus.monitoring,
            condition: _clearCondition,
          ),
        );

        await tester.pumpWidget(
          _buildWidget(
            navigationBloc: navigationBloc,
            weatherBloc: weatherBloc,
          ),
        );
        await tester.pump();

        // Transition: clear → low visibility (hazardous)
        controller.add(
          WeatherState(
            status: WeatherStatus.monitoring,
            condition: _lowVisibility,
          ),
        );
        await tester.pumpAndSettle();

        verify(
          () => navigationBloc.add(
            any(
              that: isA<SafetyAlertReceived>()
                  .having((e) => e.severity, 'severity', AlertSeverity.warning)
                  .having((e) => e.message, 'message', contains('Visibility')),
            ),
          ),
        ).called(1);

        await controller.close();
      },
    );
  });

  group('Weather → Safety bridge: non-hazard cases', () {
    testWidgets('no alert dispatched when weather stays non-hazardous', (
      tester,
    ) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _clearCondition,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      // Transition: clear → light snow (both non-hazardous)
      controller.add(
        WeatherState(status: WeatherStatus.monitoring, condition: _lightSnow),
      );
      await tester.pumpAndSettle();

      verifyNever(
        () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())),
      );

      await controller.close();
    });

    testWidgets('no re-dispatch when weather stays hazardous', (tester) async {
      // Start already hazardous
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _heavySnow,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      // Another hazardous condition — still hazardous
      controller.add(
        WeatherState(status: WeatherStatus.monitoring, condition: _iceRisk),
      );
      await tester.pumpAndSettle();

      // listenWhen: !prev.hazard == SafetyVerdict.hazardous && curr.hazard == SafetyVerdict.hazardous
      // Since prev was already hazardous, NO new alert
      verifyNever(
        () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())),
      );

      await controller.close();
    });

    testWidgets('no alert when weather unavailable', (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      // Weather becomes available but non-hazardous
      controller.add(
        WeatherState(
          status: WeatherStatus.monitoring,
          condition: _clearCondition,
        ),
      );
      await tester.pumpAndSettle();

      verifyNever(
        () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())),
      );

      await controller.close();
    });
  });

  group('Weather → Safety bridge: hazard message content', () {
    testWidgets('ice risk message names ブラックアイスバーン precisely', (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _clearCondition,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      controller.add(
        WeatherState(status: WeatherStatus.monitoring, condition: _iceRisk),
      );
      await tester.pumpAndSettle();

      verify(
        () => navigationBloc.add(
          any(
            that: isA<SafetyAlertReceived>()
                // The precise JAF term the driver knows, ja-primary, possibility-
                // graded, with an EN line. The feed-flagged path fires during
                // visible precipitation, so it must NOT claim the road merely
                // "looks wet" — that variant belongs to the invisible-ice
                // window only.
                .having(
                  (e) => e.message,
                  'message',
                  allOf(
                    startsWith('ブラックアイスバーン'),
                    contains('凍結'),
                    contains('おそれ'),
                    isNot(contains('濡れて見え')),
                    contains('Black ice'),
                  ),
                ),
          ),
        ),
      ).called(1);

      await controller.close();
    });

    testWidgets('low visibility message includes distance value', (
      tester,
    ) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _clearCondition,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      controller.add(
        WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lowVisibility,
        ),
      );
      await tester.pumpAndSettle();

      verify(
        () => navigationBloc.add(
          any(
            that: isA<SafetyAlertReceived>().having(
              (e) => e.message,
              'message',
              contains('150'),
            ),
          ),
        ),
      ).called(1);

      await controller.close();
    });

    testWidgets('heavy snow message names the classified surface (圧雪)', (
      tester,
    ) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _clearCondition,
        ),
      );

      await tester.pumpWidget(
        _buildWidget(navigationBloc: navigationBloc, weatherBloc: weatherBloc),
      );
      await tester.pump();

      controller.add(
        WeatherState(status: WeatherStatus.monitoring, condition: _heavySnow),
      );
      await tester.pumpAndSettle();

      verify(
        () => navigationBloc.add(
          any(
            that: isA<SafetyAlertReceived>().having(
              (e) => e.message,
              'message',
              allOf(contains('圧雪'), contains('Compacted snow')),
            ),
          ),
        ),
      ).called(1);

      await controller.close();
    });
  });

  group('Weather → Safety bridge: full scenario', () {
    testWidgets(
      'clear → light snow → heavy snow (alert) → ice risk (no re-alert)',
      (tester) async {
        final controller = StreamController<WeatherState>.broadcast();
        whenListen(
          weatherBloc,
          controller.stream,
          initialState: WeatherState(
            status: WeatherStatus.monitoring,
            condition: _clearCondition,
          ),
        );

        await tester.pumpWidget(
          _buildWidget(
            navigationBloc: navigationBloc,
            weatherBloc: weatherBloc,
          ),
        );
        await tester.pump();

        // Step 1: Clear → light snow (both non-hazardous)
        controller.add(
          WeatherState(status: WeatherStatus.monitoring, condition: _lightSnow),
        );
        await tester.pumpAndSettle();
        verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())),
        );

        // Step 2: Light snow → heavy snow (hazardous! alert fires)
        controller.add(
          WeatherState(status: WeatherStatus.monitoring, condition: _heavySnow),
        );
        await tester.pumpAndSettle();
        verify(
          () => navigationBloc.add(
            any(
              that: isA<SafetyAlertReceived>().having(
                (e) => e.severity,
                'severity',
                AlertSeverity.warning,
              ),
            ),
          ),
        ).called(1);

        // Step 3: Heavy snow → ice risk (still hazardous — no re-dispatch)
        controller.add(
          WeatherState(status: WeatherStatus.monitoring, condition: _iceRisk),
        );
        await tester.pumpAndSettle();
        // No additional call — listenWhen prevents re-dispatch
        verifyNever(
          () => navigationBloc.add(
            any(
              that: isA<SafetyAlertReceived>().having(
                (e) => e.severity,
                'severity',
                AlertSeverity.critical,
              ),
            ),
          ),
        );

        await controller.close();
      },
    );
  });
}
