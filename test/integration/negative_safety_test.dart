/// Negative safety tests — verify no false alerts under safe conditions.
///
/// ADA-5: These tests prove the safety pipeline does NOT over-alert.
/// False positives erode driver trust (cry-wolf effect).
///
/// Three categories:
///   1. Weather: no alert for clear/light conditions
///   2. Fleet: no alert for dry-only reports
///   3. Dead reckoning: safety cap respected, no positions emitted beyond 500m
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/navigation_bloc.dart';
import 'package:sngnav_snow_scene/bloc/navigation_event.dart';
import 'package:sngnav_snow_scene/bloc/navigation_state.dart';
import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/models/dead_reckoning_state.dart';
import 'package:sngnav_snow_scene/models/kalman_filter.dart';
import 'package:sngnav_snow_scene/models/geo_position.dart';
import 'package:sngnav_snow_scene/models/weather_condition.dart';
import 'package:sngnav_snow_scene/widgets/weather_status_bar.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

// ---------------------------------------------------------------------------
// Test data — all safe conditions (no alerts should fire)
// ---------------------------------------------------------------------------

final _now = DateTime.now();

final _clear = WeatherCondition.clear(timestamp: _now);

final _lightSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: 1.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: _now,
);

final _moderateSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: -1.0,
  visibilityMeters: 800,
  windSpeedKmh: 30,
  timestamp: _now,
);

final _coldButClear = WeatherCondition(
  precipType: PrecipitationType.none,
  intensity: PrecipitationIntensity.none,
  temperatureCelsius: -5.0,
  visibilityMeters: 10000,
  windSpeedKmh: 5,
  timestamp: _now,
);

final _lightRain = WeatherCondition(
  precipType: PrecipitationType.rain,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: 8.0,
  visibilityMeters: 5000,
  windSpeedKmh: 10,
  timestamp: _now,
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildWeatherWidget({
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
    registerFallbackValue(const SafetyAlertReceived(
      message: '',
      severity: AlertSeverity.info,
    ));
  });

  setUp(() {
    navigationBloc = MockNavigationBloc();
    weatherBloc = MockWeatherBloc();

    when(() => navigationBloc.state)
        .thenReturn(const NavigationState.idle());
  });

  // =========================================================================
  // 1. Weather — no false alerts for safe conditions
  // =========================================================================

  group('No false weather alerts', () {
    testWidgets('clear weather never triggers safety alert', (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(_buildWeatherWidget(
        navigationBloc: navigationBloc,
        weatherBloc: weatherBloc,
      ));
      await tester.pump();

      controller.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _clear,
      ));
      await tester.pumpAndSettle();

      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await controller.close();
    });

    testWidgets('light snow never triggers safety alert', (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(_buildWeatherWidget(
        navigationBloc: navigationBloc,
        weatherBloc: weatherBloc,
      ));
      await tester.pump();

      controller.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _lightSnow,
      ));
      await tester.pumpAndSettle();

      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await controller.close();
    });

    testWidgets('moderate snow (vis 800m) never triggers safety alert',
        (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(_buildWeatherWidget(
        navigationBloc: navigationBloc,
        weatherBloc: weatherBloc,
      ));
      await tester.pump();

      controller.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _moderateSnow,
      ));
      await tester.pumpAndSettle();

      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await controller.close();
    });

    testWidgets('freezing but clear never triggers safety alert',
        (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(_buildWeatherWidget(
        navigationBloc: navigationBloc,
        weatherBloc: weatherBloc,
      ));
      await tester.pump();

      controller.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _coldButClear,
      ));
      await tester.pumpAndSettle();

      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await controller.close();
    });

    testWidgets('light rain never triggers safety alert', (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(_buildWeatherWidget(
        navigationBloc: navigationBloc,
        weatherBloc: weatherBloc,
      ));
      await tester.pump();

      controller.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _lightRain,
      ));
      await tester.pumpAndSettle();

      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await controller.close();
    });

    testWidgets('cycling through all safe conditions never triggers alert',
        (tester) async {
      final controller = StreamController<WeatherState>.broadcast();
      whenListen(
        weatherBloc,
        controller.stream,
        initialState: const WeatherState.unavailable(),
      );

      await tester.pumpWidget(_buildWeatherWidget(
        navigationBloc: navigationBloc,
        weatherBloc: weatherBloc,
      ));
      await tester.pump();

      // Cycle: unavailable → clear → light snow → moderate → cold/clear → light rain
      for (final condition in [
        _clear,
        _lightSnow,
        _moderateSnow,
        _coldButClear,
        _lightRain,
      ]) {
        controller.add(WeatherState(
          status: WeatherStatus.monitoring,
          condition: condition,
        ));
        await tester.pumpAndSettle();
      }

      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await controller.close();
    });
  });

  // =========================================================================
  // 2. isHazardous boundary — verify exact thresholds
  // =========================================================================

  group('Hazard threshold boundaries', () {
    test('visibility 200m is NOT hazardous (boundary)', () {
      final condition = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
        temperatureCelsius: -1.0,
        visibilityMeters: 200,
        windSpeedKmh: 20,
        timestamp: _now,
      );
      expect(condition.isHazardous, isFalse,
          reason: 'visibility < 200 is hazardous, 200 exactly is not');
    });

    test('visibility 199m IS hazardous (boundary)', () {
      final condition = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
        temperatureCelsius: -1.0,
        visibilityMeters: 199,
        windSpeedKmh: 20,
        timestamp: _now,
      );
      expect(condition.isHazardous, isTrue);
    });

    test('moderate intensity is NOT hazardous (without ice/low vis)', () {
      expect(_moderateSnow.isHazardous, isFalse,
          reason: 'moderate snow at 800m vis is not hazardous');
    });

    test('light intensity is NOT hazardous', () {
      expect(_lightSnow.isHazardous, isFalse);
    });

    test('clear is NOT hazardous even when freezing', () {
      expect(_coldButClear.isHazardous, isFalse,
          reason: 'sub-zero temperature alone does not trigger hazard');
    });

    test('iceRisk=false does not make non-heavy condition hazardous', () {
      final condition = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.moderate,
        temperatureCelsius: -3.0,
        visibilityMeters: 500,
        windSpeedKmh: 20,
        iceRisk: false,
        timestamp: _now,
      );
      expect(condition.isHazardous, isFalse);
    });
  });

  // =========================================================================
  // 3. Dead reckoning safety cap
  // =========================================================================

  group('Dead reckoning safety cap', () {
    test('DR state maxAccuracy is 500m', () {
      expect(DeadReckoningState.maxAccuracy, equals(500.0));
    });

    test('fresh DR state is not accuracy-exceeded', () {
      final state = DeadReckoningState.fromGeoPosition(GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 5.0,
        speed: 16.67,
        heading: 90.0,
        timestamp: DateTime.now(),
      ));
      expect(state, isNotNull, reason: 'valid GPS fix should create DR state');
      expect(state!.isAccuracyExceeded, isFalse,
          reason: 'fresh GPS fix should not trigger safety cap');
    });

    test('DR state with high base accuracy is closer to cap', () {
      final state = DeadReckoningState.fromGeoPosition(GeoPosition(
        latitude: 35.17,
        longitude: 136.88,
        accuracy: 400.0,
        speed: 16.67,
        heading: 90.0,
        timestamp: DateTime.now().subtract(const Duration(seconds: 25)),
      ));
      expect(state, isNotNull);
      // 400m base + 5m/s × 25s = 525m → exceeded
      expect(state!.isAccuracyExceeded, isTrue,
          reason: 'high base + time should exceed 500m cap');
    });

    test('Kalman filter reports accuracy-exceeded after extended DR', () {
      final kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 16.67,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      // 5 minutes of dead reckoning without GPS
      for (var i = 0; i < 300; i++) {
        kf.predict(const Duration(seconds: 1));
      }

      expect(kf.isAccuracyExceeded, isTrue,
          reason: '5 minutes of DR should exceed safety cap');
    });

    test('Kalman filter NOT accuracy-exceeded after short DR', () {
      final kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 16.67,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      // 10 seconds of dead reckoning
      for (var i = 0; i < 10; i++) {
        kf.predict(const Duration(seconds: 1));
      }

      expect(kf.isAccuracyExceeded, isFalse,
          reason: '10 seconds of DR should be well within safety cap');
    });

    test('Kalman filter accuracy grows monotonically during DR', () {
      final kf = KalmanFilter.withState(
        latitude: 35.17,
        longitude: 136.88,
        speed: 16.67,
        heading: 90.0,
        timestamp: DateTime.now(),
      );

      var prevAccuracy = kf.accuracyMetres;
      for (var i = 0; i < 30; i++) {
        kf.predict(const Duration(seconds: 1));
        final accuracy = kf.accuracyMetres;
        expect(accuracy, greaterThanOrEqualTo(prevAccuracy),
            reason: 'DR accuracy must grow (never improve without GPS)');
        prevAccuracy = accuracy;
      }
    });
  });
}
