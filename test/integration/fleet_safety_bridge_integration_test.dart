/// Fleet → Safety bridge integration tests.
///
/// Covers the widget-mediated coupling gaps identified on Day 11:
///
///   Gap 1 (HIGH): FleetBloc hasHazards → NavigationBloc SafetyAlertReceived
///     The `BlocListener<FleetBloc>` in SnowSceneScaffold dispatches
///     SafetyAlertReceived with critical/warning severity based on
///     RoadCondition. This is the most safety-critical untested bridge.
///
///   Gap 4 (MEDIUM): Full scenario — consent grant → fleet listening →
///     hazard arrival → safety alert dispatch.
///
/// Sprint 8 Day 11 — Test hardening (cross-BLoC integration).
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
import 'package:sngnav_snow_scene/models/fleet_report.dart';
import 'package:sngnav_snow_scene/widgets/snow_scene_scaffold.dart';

// ---------------------------------------------------------------------------
// Mocks
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

final _now = DateTime.now();

final _icyReport = FleetReport(
  vehicleId: 'V-001',
  position: const LatLng(35.0600, 137.2500),
  timestamp: _now,
  condition: RoadCondition.icy,
  confidence: 0.9,
);

final _snowyReport = FleetReport(
  vehicleId: 'V-002',
  position: const LatLng(35.0500, 137.3200),
  timestamp: _now,
  condition: RoadCondition.snowy,
  confidence: 0.85,
);

final _dryReport = FleetReport(
  vehicleId: 'V-003',
  position: const LatLng(35.1000, 137.0000),
  timestamp: _now,
  condition: RoadCondition.dry,
  confidence: 0.95,
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
    registerFallbackValue(const SafetyAlertReceived(
      message: '',
      severity: AlertSeverity.info,
    ));
    registerFallbackValue(const ManeuverAdvanced());
  });

  group('Fleet → Safety bridge (Gap 1)', () {
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

    testWidgets(
        'dispatches SafetyAlertReceived(critical) when fleet reports icy conditions',
        (tester) async {
      final fleetController = StreamController<FleetState>.broadcast();
      whenListen(
        fleetBloc,
        fleetController.stream,
        initialState: const FleetState.idle(),
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

      // Fleet transitions from no hazards to icy hazard
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _icyReport,
          'V-003': _dryReport,
        },
      ));
      await tester.pumpAndSettle();

      // Verify SafetyAlertReceived with critical severity
      verify(() => navigationBloc.add(any(
        that: isA<SafetyAlertReceived>()
            .having((e) => e.severity, 'severity', AlertSeverity.critical)
            .having(
              (e) => e.message,
              'message',
              contains('icy'),
            ),
      ))).called(1);

      await fleetController.close();
    });

    testWidgets(
        'dispatches SafetyAlertReceived(warning) when fleet reports snowy (no icy)',
        (tester) async {
      final fleetController = StreamController<FleetState>.broadcast();
      whenListen(
        fleetBloc,
        fleetController.stream,
        initialState: const FleetState.idle(),
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

      // Fleet transitions to snowy hazard (no icy)
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-002': _snowyReport,
          'V-003': _dryReport,
        },
      ));
      await tester.pumpAndSettle();

      // Verify SafetyAlertReceived with warning severity
      verify(() => navigationBloc.add(any(
        that: isA<SafetyAlertReceived>()
            .having((e) => e.severity, 'severity', AlertSeverity.warning)
            .having(
              (e) => e.message,
              'message',
              contains('snowy'),
            ),
      ))).called(1);

      await fleetController.close();
    });

    testWidgets(
        'does NOT dispatch safety alert when fleet has no hazards',
        (tester) async {
      final fleetController = StreamController<FleetState>.broadcast();
      whenListen(
        fleetBloc,
        fleetController.stream,
        initialState: const FleetState.idle(),
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

      // Fleet starts listening with only dry reports — no hazards
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-003': _dryReport},
      ));
      await tester.pumpAndSettle();

      // No safety alert dispatched
      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await fleetController.close();
    });

    testWidgets(
        'does NOT re-dispatch when fleet stays in hazardous state',
        (tester) async {
      // Start already with hazards
      final initialHazardState = FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _icyReport,
          'V-003': _dryReport,
        },
      );

      final fleetController = StreamController<FleetState>.broadcast();
      whenListen(
        fleetBloc,
        fleetController.stream,
        initialState: initialHazardState,
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

      // Another hazard report arrives — still hazardous
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _icyReport,
          'V-002': _snowyReport,
          'V-003': _dryReport,
        },
      ));
      await tester.pumpAndSettle();

      // listenWhen: !prev.hasHazards && curr.hasHazards
      // Since prev already had hazards, NO new alert should be dispatched
      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      await fleetController.close();
    });

    testWidgets('message includes vehicle count', (tester) async {
      final fleetController = StreamController<FleetState>.broadcast();
      whenListen(
        fleetBloc,
        fleetController.stream,
        initialState: const FleetState.idle(),
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

      // Two hazard reports
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _icyReport,
          'V-002': _snowyReport,
        },
      ));
      await tester.pumpAndSettle();

      verify(() => navigationBloc.add(any(
        that: isA<SafetyAlertReceived>()
            .having(
              (e) => e.message,
              'message',
              contains('2 vehicles reporting'),
            ),
      ))).called(1);

      await fleetController.close();
    });
  });

  group('Full scenario: fleet → hazard → safety (Gap 4)', () {
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

    testWidgets(
        'fleet idle → listening (dry only) → hazard arrives → safety alert',
        (tester) async {
      final fleetController = StreamController<FleetState>.broadcast();
      whenListen(
        fleetBloc,
        fleetController.stream,
        initialState: const FleetState.idle(),
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

      // Step 1: Fleet starts listening with dry reports only
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-003': _dryReport},
      ));
      await tester.pumpAndSettle();

      // No alert yet — no hazards
      verifyNever(
          () => navigationBloc.add(any(that: isA<SafetyAlertReceived>())));

      // Step 2: Icy report arrives → hasHazards transitions false→true
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _icyReport,
          'V-003': _dryReport,
        },
      ));
      await tester.pumpAndSettle();

      // Now the safety alert should fire
      verify(() => navigationBloc.add(any(
        that: isA<SafetyAlertReceived>()
            .having((e) => e.severity, 'severity', AlertSeverity.critical),
      ))).called(1);

      await fleetController.close();
    });
  });
}
