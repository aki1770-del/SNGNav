/// ScenarioPhaseIndicator widget tests.
///
/// Tests:
///   1. Hidden when no weather condition
///   2. Shows clear phase label
///   3. Shows light snow label
///   4. Shows heavy snow label
///   5. Shows ice risk label
///   6. Shows correct icon for each phase
///
/// Sprint 7 Day 12 — Snow Scene polish.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:driving_weather/driving_weather.dart';

import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/widgets/scenario_phase_indicator.dart';

// ---------------------------------------------------------------------------
// Mock
// ---------------------------------------------------------------------------

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildIndicator({required MockWeatherBloc weatherBloc}) {
  return MaterialApp(
    home: Scaffold(
      body: BlocProvider<WeatherBloc>.value(
        value: weatherBloc,
        child: const ScenarioPhaseIndicator(),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ScenarioPhaseIndicator', () {
    late MockWeatherBloc weatherBloc;

    setUp(() {
      weatherBloc = MockWeatherBloc();
    });

    testWidgets('hidden when no weather condition', (tester) async {
      when(() => weatherBloc.state)
          .thenReturn(const WeatherState.unavailable());

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.byType(ScenarioPhaseIndicator), findsOneWidget);
      // The indicator returns SizedBox.shrink when no condition
      expect(find.text('Clear — City Departure'), findsNothing);
    });

    testWidgets('shows clear phase label', (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition.clear(timestamp: DateTime(2026)),
      ));

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.text('Clear — City Departure'), findsOneWidget);
      expect(find.text('Route 153 east from Nagoya Station'), findsOneWidget);
    });

    testWidgets('shows light snow label', (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.light,
          temperatureCelsius: 1.0,
          visibilityMeters: 3000,
          windSpeedKmh: 15,
          timestamp: DateTime(2026),
        ),
      ));

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.text('Light Snow — Mountain Approach'), findsOneWidget);
    });

    testWidgets('shows heavy snow label', (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -4.0,
          visibilityMeters: 150,
          windSpeedKmh: 45,
          timestamp: DateTime(2026),
        ),
      ));

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.text('Heavy Snow — Pass Summit'), findsOneWidget);
      expect(find.text('Visibility critically low, hazardous conditions'),
          findsOneWidget);
    });

    testWidgets('shows ice risk label', (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -3.0,
          visibilityMeters: 500,
          windSpeedKmh: 20,
          iceRisk: true,
          timestamp: DateTime(2026),
        ),
      ));

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.text('Ice Risk — Pass Descent'), findsOneWidget);
      expect(find.text('Black ice warning, reduce speed'), findsOneWidget);
    });

    testWidgets('shows correct icon for clear phase', (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition.clear(timestamp: DateTime(2026)),
      ));

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.byIcon(Icons.wb_sunny), findsOneWidget);
    });

    testWidgets('shows correct icon for ice risk', (tester) async {
      when(() => weatherBloc.state).thenReturn(WeatherState(
        status: WeatherStatus.monitoring,
        condition: WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.moderate,
          temperatureCelsius: -3.0,
          visibilityMeters: 500,
          windSpeedKmh: 20,
          iceRisk: true,
          timestamp: DateTime(2026),
        ),
      ));

      await tester.pumpWidget(_buildIndicator(weatherBloc: weatherBloc));
      await tester.pump();

      expect(find.byIcon(Icons.ac_unit), findsOneWidget);
    });
  });
}
