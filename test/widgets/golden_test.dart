/// Golden tests — visual regression snapshots for key widgets.
///
/// These tests generate reference images stored in `test/goldens/`.
/// Run `flutter test --update-goldens` to regenerate baselines.
///
/// Visual verification (E9-4): golden tests serve as the baseline for
/// visual regression. On Wayland (Machine D), screenshot tools (grim,
/// gnome-screenshot) are blocked. Golden tests provide pixel-level
/// verification without needing a visible display.
///
/// Sprint 9 Day 9 — Visual verification (D-SC-ADHOC-S9-4).
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/bloc/navigation_bloc.dart';
import 'package:sngnav_snow_scene/bloc/navigation_event.dart';
import 'package:sngnav_snow_scene/bloc/navigation_state.dart';
import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/models/geo_position.dart';
import 'package:sngnav_snow_scene/models/route_result.dart';
import 'package:sngnav_snow_scene/models/weather_condition.dart';
import 'package:sngnav_snow_scene/widgets/route_progress_bar.dart';
import 'package:sngnav_snow_scene/widgets/safety_overlay.dart';
import 'package:sngnav_snow_scene/widgets/speed_display.dart';
import 'package:sngnav_snow_scene/widgets/weather_status_bar.dart';

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _now = DateTime.now();

final _lightSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: -2.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: _now,
);

final _heavySnowIce = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -8.0,
  visibilityMeters: 150,
  windSpeedKmh: 40,
  iceRisk: true,
  timestamp: _now,
);

final _gpsPosition = GeoPosition(
  latitude: 35.1709,
  longitude: 136.8815,
  accuracy: 5.0,
  speed: 16.67, // 60 km/h
  heading: 90,
  timestamp: _now,
);

final _demoRoute = RouteResult(
  shape: const [
    LatLng(35.1709, 136.8815),
    LatLng(35.0700, 137.4000),
  ],
  maneuvers: [
    const RouteManeuver(
      index: 0,
      instruction: 'Depart Nagoya Station via Route 153 East',
      type: 'depart',
      lengthKm: 2.1,
      timeSeconds: 180,
      position: LatLng(35.1709, 136.8815),
    ),
    const RouteManeuver(
      index: 1,
      instruction: 'Continue east on Route 153',
      type: 'straight',
      lengthKm: 4.5,
      timeSeconds: 270,
      position: LatLng(35.1680, 136.9100),
    ),
    const RouteManeuver(
      index: 2,
      instruction: 'Arrive at Mikawa Highlands',
      type: 'arrive',
      lengthKm: 0.0,
      timeSeconds: 0,
      position: LatLng(35.0700, 137.4000),
    ),
  ],
  totalDistanceKm: 38.1,
  totalTimeSeconds: 3060,
  summary: 'Nagoya → Mikawa Highlands',
  engineInfo: const EngineInfo(
    name: 'mock',
    queryLatency: Duration(milliseconds: 5),
  ),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wrap a widget with required BLoC providers for golden testing.
Widget _goldenFrame({
  required Widget child,
  WeatherState? weatherState,
  NavigationState? navState,
  LocationState? locationState,
  Size size = const Size(400, 100),
}) {
  final weatherBloc = MockWeatherBloc();
  final navBloc = MockNavigationBloc();
  final locationBloc = MockLocationBloc();

  when(() => weatherBloc.state).thenReturn(
    weatherState ?? const WeatherState.unavailable(),
  );
  when(() => navBloc.state).thenReturn(
    navState ?? const NavigationState.idle(),
  );
  when(() => locationBloc.state).thenReturn(
    locationState ?? const LocationState.uninitialized(),
  );

  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1A73E8),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    home: Scaffold(
      body: MultiBlocProvider(
        providers: [
          BlocProvider<WeatherBloc>.value(value: weatherBloc),
          BlocProvider<NavigationBloc>.value(value: navBloc),
          BlocProvider<LocationBloc>.value(value: locationBloc),
        ],
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: child,
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Golden tests
// ---------------------------------------------------------------------------

void main() {
  group('Golden — WeatherStatusBar', () {
    testWidgets('light snow', (tester) async {
      await tester.pumpWidget(_goldenFrame(
        child: const WeatherStatusBar(),
        weatherState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lightSnow,
        ),
        size: const Size(600, 60),
      ));

      await expectLater(
        find.byType(WeatherStatusBar),
        matchesGoldenFile('goldens/weather_bar_light_snow.png'),
      );
    });

    testWidgets('heavy snow with ice', (tester) async {
      await tester.pumpWidget(_goldenFrame(
        child: const WeatherStatusBar(),
        weatherState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _heavySnowIce,
        ),
        size: const Size(600, 60),
      ));

      await expectLater(
        find.byType(WeatherStatusBar),
        matchesGoldenFile('goldens/weather_bar_heavy_ice.png'),
      );
    });

    testWidgets('stale data (15m old)', (tester) async {
      final stale = WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.light,
        temperatureCelsius: -2.0,
        visibilityMeters: 3000,
        windSpeedKmh: 15,
        timestamp: DateTime.now().subtract(const Duration(minutes: 15)),
      );
      await tester.pumpWidget(_goldenFrame(
        child: const WeatherStatusBar(),
        weatherState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: stale,
        ),
        size: const Size(600, 60),
      ));

      await expectLater(
        find.byType(WeatherStatusBar),
        matchesGoldenFile('goldens/weather_bar_stale.png'),
      );
    });
  });

  group('Golden — SpeedDisplay', () {
    testWidgets('60 km/h with GPS fix', (tester) async {
      await tester.pumpWidget(_goldenFrame(
        child: const SpeedDisplay(),
        locationState: LocationState(
          quality: LocationQuality.fix,
          position: _gpsPosition,
        ),
        size: const Size(120, 120),
      ));

      await expectLater(
        find.byType(SpeedDisplay),
        matchesGoldenFile('goldens/speed_display_60kmh.png'),
      );
    });

    testWidgets('no GPS (uninitialized)', (tester) async {
      await tester.pumpWidget(_goldenFrame(
        child: const SpeedDisplay(),
        size: const Size(120, 120),
      ));

      await expectLater(
        find.byType(SpeedDisplay),
        matchesGoldenFile('goldens/speed_display_no_gps.png'),
      );
    });
  });

  group('Golden — SafetyOverlay', () {
    testWidgets('critical alert', (tester) async {
      final criticalState = NavigationState(
        status: NavigationStatus.navigating,
        route: _demoRoute,
        currentManeuverIndex: 0,
        alertMessage: 'Black ice risk — reduce speed',
        alertSeverity: AlertSeverity.critical,
        alertDismissible: true,
      );
      // SafetyOverlay uses Positioned.fill — needs a Stack parent.
      await tester.pumpWidget(_goldenFrame(
        child: const Stack(children: [SafetyOverlay()]),
        navState: criticalState,
        size: const Size(400, 300),
      ));

      await expectLater(
        find.byType(Stack).last,
        matchesGoldenFile('goldens/safety_overlay_critical.png'),
      );
    });

    testWidgets('warning alert', (tester) async {
      final warningState = NavigationState(
        status: NavigationStatus.navigating,
        route: _demoRoute,
        currentManeuverIndex: 0,
        alertMessage: 'Heavy snow — reduced traction and visibility',
        alertSeverity: AlertSeverity.warning,
        alertDismissible: true,
      );
      await tester.pumpWidget(_goldenFrame(
        child: const Stack(children: [SafetyOverlay()]),
        navState: warningState,
        size: const Size(400, 300),
      ));

      await expectLater(
        find.byType(Stack).last,
        matchesGoldenFile('goldens/safety_overlay_warning.png'),
      );
    });
  });

  group('Golden — RouteProgressBar', () {
    testWidgets('navigating', (tester) async {
      final navState = NavigationState(
        status: NavigationStatus.navigating,
        route: _demoRoute,
        currentManeuverIndex: 0,
      );
      await tester.pumpWidget(_goldenFrame(
        child: const RouteProgressBar(),
        navState: navState,
        size: const Size(400, 120),
      ));

      await expectLater(
        find.byType(RouteProgressBar),
        matchesGoldenFile('goldens/route_progress_navigating.png'),
      );
    });

    testWidgets('arrived', (tester) async {
      final arrivedState = NavigationState(
        status: NavigationStatus.arrived,
        route: _demoRoute,
        currentManeuverIndex: 2,
        destinationLabel: 'Mikawa Highlands',
      );
      await tester.pumpWidget(_goldenFrame(
        child: const RouteProgressBar(),
        navState: arrivedState,
        size: const Size(400, 80),
      ));

      await expectLater(
        find.byType(RouteProgressBar),
        matchesGoldenFile('goldens/route_progress_arrived.png'),
      );
    });
  });
}
