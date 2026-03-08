/// SnowSceneScaffold widget tests.
///
/// Tests:
///   1. Renders app bar with title
///   2. Shows navigation status chip (idle)
///   3. Contains MapLayer at Z=0
///   4. Contains SafetyOverlay at Z=2
///   5. Contains WeatherStatusBar in overlay
///   6. Contains SpeedDisplay in overlay
///   7. Contains ConsentGate in overlay
///   8. Contains RouteProgressBar in overlay
///   9. Dispatches MapInitialized on first frame
///  10. Widget-mediated: RoutingBloc routeActive → NavigationStarted
///  11. Widget-mediated: LocationBloc position + follow mode → CenterChanged
///  12. Does NOT dispatch NavigationStarted when no route
///
/// Sprint 7 Day 11 — Test hardening.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:mocktail/mocktail.dart';

import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';
import 'package:sngnav_snow_scene/bloc/fleet_bloc.dart';
import 'package:sngnav_snow_scene/bloc/fleet_event.dart';
import 'package:sngnav_snow_scene/bloc/fleet_state.dart';
import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/bloc/map_bloc.dart';
import 'package:sngnav_snow_scene/bloc/map_event.dart';
import 'package:sngnav_snow_scene/bloc/map_state.dart';
import 'package:sngnav_snow_scene/bloc/navigation_bloc.dart';
import 'package:sngnav_snow_scene/bloc/navigation_event.dart';
import 'package:sngnav_snow_scene/bloc/navigation_state.dart';
import 'package:sngnav_snow_scene/bloc/routing_bloc.dart';
import 'package:sngnav_snow_scene/bloc/routing_event.dart';
import 'package:sngnav_snow_scene/bloc/routing_state.dart';
import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:sngnav_snow_scene/widgets/consent_gate.dart';
import 'package:sngnav_snow_scene/widgets/map_layer.dart';
import 'package:sngnav_snow_scene/widgets/route_progress_bar.dart';
import 'package:sngnav_snow_scene/widgets/safety_overlay.dart';
import 'package:sngnav_snow_scene/widgets/snow_scene_scaffold.dart';
import 'package:sngnav_snow_scene/widgets/speed_display.dart';
import 'package:sngnav_snow_scene/widgets/weather_status_bar.dart';

// ---------------------------------------------------------------------------
// Mocks (all 7 BLoCs)
// ---------------------------------------------------------------------------

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockRoutingBloc extends MockBloc<RoutingEvent, RoutingState>
    implements RoutingBloc {}

class MockNavigationBloc extends MockBloc<NavigationEvent, NavigationState>
    implements NavigationBloc {}

class MockMapBloc extends MockBloc<MapEvent, MapState> implements MapBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class MockConsentBloc extends MockBloc<ConsentEvent, ConsentState>
    implements ConsentBloc {}

class MockFleetBloc extends MockBloc<FleetEvent, FleetState>
    implements FleetBloc {}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

final _testRoute = RouteResult(
  shape: const [
    LatLng(35.1709, 136.8815),
    LatLng(35.0500, 137.3200),
  ],
  totalDistanceKm: 45.0,
  totalTimeSeconds: 3600,
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head east',
      type: 'depart',
      lengthKm: 10.0,
      timeSeconds: 600,
      position: LatLng(35.1709, 136.8815),
    ),
  ],
  summary: 'Nagoya → Mt. Sanage',
  engineInfo: const EngineInfo(
    name: 'mock',
    version: '1.0',
    queryLatency: Duration.zero,
  ),
);

final _testPosition = GeoPosition(
  latitude: 35.1800,
  longitude: 136.9000,
  accuracy: 5.0,
  speed: 16.7,
  heading: 90.0,
  timestamp: DateTime(2026),
);

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Widget _buildScaffold({
  required MockLocationBloc locationBloc,
  required MockRoutingBloc routingBloc,
  required MockNavigationBloc navigationBloc,
  required MockMapBloc mapBloc,
  required MockWeatherBloc weatherBloc,
  required MockConsentBloc consentBloc,
  required MockFleetBloc fleetBloc,
}) {
  return MaterialApp(
    home: MultiBlocProvider(
      providers: [
        BlocProvider<LocationBloc>.value(value: locationBloc),
        BlocProvider<RoutingBloc>.value(value: routingBloc),
        BlocProvider<NavigationBloc>.value(value: navigationBloc),
        BlocProvider<MapBloc>.value(value: mapBloc),
        BlocProvider<WeatherBloc>.value(value: weatherBloc),
        BlocProvider<ConsentBloc>.value(value: consentBloc),
        BlocProvider<FleetBloc>.value(value: fleetBloc),
      ],
      child: const SnowSceneScaffold(),
    ),
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    registerFallbackValue(const MapInitialized(
      center: LatLng(0, 0),
      zoom: 1,
    ));
    registerFallbackValue(NavigationStarted(
      route: _testRoute,
      destinationLabel: '',
    ));
    registerFallbackValue(const CenterChanged(LatLng(0, 0)));
    registerFallbackValue(const ManeuverAdvanced());
  });

  group('SnowSceneScaffold', () {
    late MockLocationBloc locationBloc;
    late MockRoutingBloc routingBloc;
    late MockNavigationBloc navigationBloc;
    late MockMapBloc mapBloc;
    late MockWeatherBloc weatherBloc;
    late MockConsentBloc consentBloc;
    late MockFleetBloc fleetBloc;

    setUp(() {
      locationBloc = MockLocationBloc();
      routingBloc = MockRoutingBloc();
      navigationBloc = MockNavigationBloc();
      mapBloc = MockMapBloc();
      weatherBloc = MockWeatherBloc();
      consentBloc = MockConsentBloc();
      fleetBloc = MockFleetBloc();

      // Default states
      when(() => locationBloc.state)
          .thenReturn(const LocationState.uninitialized());
      when(() => routingBloc.state)
          .thenReturn(const RoutingState.idle());
      when(() => navigationBloc.state)
          .thenReturn(const NavigationState.idle());
      when(() => mapBloc.state)
          .thenReturn(const MapState.loading());
      when(() => weatherBloc.state)
          .thenReturn(const WeatherState.unavailable());
      when(() => consentBloc.state)
          .thenReturn(const ConsentState(status: ConsentBlocStatus.loading));
      when(() => fleetBloc.state)
          .thenReturn(const FleetState.idle());
    });

    testWidgets('renders app bar with title', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.text('SNGNav Snow Scene v0.3'), findsOneWidget);
    });

    testWidgets('shows navigation status chip (idle)', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.text('IDLE'), findsOneWidget);
      expect(find.byType(Chip), findsOneWidget);
    });

    testWidgets('contains MapLayer at Z=0', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.byType(MapLayer), findsOneWidget);
    });

    testWidgets('contains SafetyOverlay at Z=2', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.byType(SafetyOverlay), findsOneWidget);
    });

    testWidgets('contains WeatherStatusBar in overlay', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.byType(WeatherStatusBar), findsOneWidget);
    });

    testWidgets('contains SpeedDisplay in overlay', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.byType(SpeedDisplay), findsOneWidget);
    });

    testWidgets('contains ConsentGate in overlay', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.byType(ConsentGate), findsOneWidget);
    });

    testWidgets('contains RouteProgressBar in overlay', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      expect(find.byType(RouteProgressBar), findsOneWidget);
    });

    testWidgets('dispatches MapInitialized on first frame', (tester) async {
      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      // addPostFrameCallback fires after first pump
      await tester.pump();

      verify(() => mapBloc.add(any(that: isA<MapInitialized>()))).called(1);
    });

    testWidgets(
        'widget-mediated: RoutingBloc routeActive → NavigationStarted',
        (tester) async {
      final routingController = StreamController<RoutingState>.broadcast();
      whenListen(
        routingBloc,
        routingController.stream,
        initialState: const RoutingState.idle(),
      );

      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      // Emit route active state
      routingController.add(RoutingState(
        status: RoutingStatus.routeActive,
        route: _testRoute,
        destinationLabel: 'Mt. Sanage',
      ));
      await tester.pumpAndSettle();

      // Verify NavigationStarted dispatched
      verify(() => navigationBloc.add(any(
        that: isA<NavigationStarted>()
            .having((e) => e.destinationLabel, 'dest', 'Mt. Sanage'),
      ))).called(1);

      await routingController.close();
    });

    testWidgets(
        'widget-mediated: LocationBloc position + follow mode → CenterChanged',
        (tester) async {
      // MapBloc in follow mode
      when(() => mapBloc.state).thenReturn(const MapState(
        status: MapStatus.ready,
        center: LatLng(35.1709, 136.8815),
        zoom: 12.0,
        cameraMode: CameraMode.follow,
      ));

      final locationController = StreamController<LocationState>.broadcast();
      whenListen(
        locationBloc,
        locationController.stream,
        initialState: const LocationState.uninitialized(),
      );

      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      // Emit position update
      locationController.add(LocationState(
        quality: LocationQuality.fix,
        position: _testPosition,
      ));
      await tester.pumpAndSettle();

      // Verify CenterChanged dispatched to MapBloc
      verify(() => mapBloc.add(any(
        that: isA<CenterChanged>(),
      ))).called(1);

      await locationController.close();
    });

    testWidgets('does NOT dispatch CenterChanged when not in follow mode',
        (tester) async {
      // MapBloc in freeLook mode (default)
      when(() => mapBloc.state).thenReturn(const MapState(
        status: MapStatus.ready,
        center: LatLng(35.1709, 136.8815),
        zoom: 12.0,
        cameraMode: CameraMode.freeLook,
      ));

      final locationController = StreamController<LocationState>.broadcast();
      whenListen(
        locationBloc,
        locationController.stream,
        initialState: const LocationState.uninitialized(),
      );

      await tester.pumpWidget(_buildScaffold(
        locationBloc: locationBloc,
        routingBloc: routingBloc,
        navigationBloc: navigationBloc,
        mapBloc: mapBloc,
        weatherBloc: weatherBloc,
        consentBloc: consentBloc,
        fleetBloc: fleetBloc,
      ));
      await tester.pump();

      // Emit position update
      locationController.add(LocationState(
        quality: LocationQuality.fix,
        position: _testPosition,
      ));
      await tester.pumpAndSettle();

      // CenterChanged should NOT be dispatched (freeLook mode)
      verifyNever(() => mapBloc.add(any(that: isA<CenterChanged>())));

      await locationController.close();
    });
  });
}
