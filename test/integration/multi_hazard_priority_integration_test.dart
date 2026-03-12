library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';

import 'package:sngnav_snow_scene/bloc/consent_bloc.dart';
import 'package:sngnav_snow_scene/bloc/consent_event.dart';
import 'package:sngnav_snow_scene/bloc/consent_state.dart';
import 'package:sngnav_snow_scene/bloc/fleet_bloc.dart';
import 'package:sngnav_snow_scene/bloc/fleet_event.dart';
import 'package:sngnav_snow_scene/bloc/fleet_state.dart';
import 'package:sngnav_snow_scene/bloc/location_bloc.dart';
import 'package:sngnav_snow_scene/bloc/location_event.dart';
import 'package:sngnav_snow_scene/bloc/location_state.dart';
import 'package:sngnav_snow_scene/bloc/weather_bloc.dart';
import 'package:sngnav_snow_scene/bloc/weather_event.dart';
import 'package:sngnav_snow_scene/bloc/weather_state.dart';
import 'package:sngnav_snow_scene/widgets/snow_scene_scaffold.dart';

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockRoutingBloc extends MockBloc<RoutingEvent, RoutingState>
    implements RoutingBloc {}

class MockWeatherBloc extends MockBloc<WeatherEvent, WeatherState>
    implements WeatherBloc {}

class MockConsentBloc extends MockBloc<ConsentEvent, ConsentState>
    implements ConsentBloc {}

class MockFleetBloc extends MockBloc<FleetEvent, FleetState>
    implements FleetBloc {}

final _lightSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: 1.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: DateTime(2026, 3, 12, 6),
);

final _heavySnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -4.0,
  visibilityMeters: 300,
  windSpeedKmh: 45,
  timestamp: DateTime(2026, 3, 12, 6, 5),
);

final _iceRisk = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.moderate,
  temperatureCelsius: -3.0,
  visibilityMeters: 500,
  windSpeedKmh: 20,
  iceRisk: true,
  timestamp: DateTime(2026, 3, 12, 6, 7),
);

final _icyReport = FleetReport(
  vehicleId: 'V-001',
  position: const LatLng(35.0600, 137.2500),
  timestamp: DateTime(2026, 3, 12, 6, 10),
  condition: RoadCondition.icy,
  confidence: 0.9,
);

final _snowyReport = FleetReport(
  vehicleId: 'V-002',
  position: const LatLng(35.0500, 137.3200),
  timestamp: DateTime(2026, 3, 12, 6, 11),
  condition: RoadCondition.snowy,
  confidence: 0.85,
);

final _dryReport = FleetReport(
  vehicleId: 'V-003',
  position: const LatLng(35.1000, 137.0000),
  timestamp: DateTime(2026, 3, 12, 6, 12),
  condition: RoadCondition.dry,
  confidence: 0.95,
);

Widget _buildScaffold({
  required LocationBloc locationBloc,
  required RoutingBloc routingBloc,
  required NavigationBloc navigationBloc,
  required MapBloc mapBloc,
  required WeatherBloc weatherBloc,
  required ConsentBloc consentBloc,
  required FleetBloc fleetBloc,
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

void main() {
  group('Multi-hazard priority integration', () {
    late MockLocationBloc locationBloc;
    late MockRoutingBloc routingBloc;
    late NavigationBloc navigationBloc;
    late MapBloc mapBloc;
    late MockWeatherBloc weatherBloc;
    late MockConsentBloc consentBloc;
    late MockFleetBloc fleetBloc;

    setUp(() {
      locationBloc = MockLocationBloc();
      routingBloc = MockRoutingBloc();
      navigationBloc = NavigationBloc();
      mapBloc = MapBloc();
      weatherBloc = MockWeatherBloc();
      consentBloc = MockConsentBloc();
      fleetBloc = MockFleetBloc();

      when(() => locationBloc.state)
          .thenReturn(const LocationState.uninitialized());
      when(() => routingBloc.state)
          .thenReturn(const RoutingState.idle());
      when(() => weatherBloc.state)
          .thenReturn(const WeatherState.unavailable());
      when(() => consentBloc.state)
          .thenReturn(const ConsentState(status: ConsentBlocStatus.loading));
      when(() => fleetBloc.state)
          .thenReturn(const FleetState.idle());
    });

    tearDown(() async {
      await navigationBloc.close();
      await mapBloc.close();
    });

    testWidgets(
        'fleet critical alert overrides an earlier weather warning',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lightSnow,
        ),
      );
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

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _heavySnow,
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.warning);

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-001': _icyReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Fleet reports'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'later weather warning does not downgrade an existing fleet critical alert',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: const WeatherState.unavailable(),
      );
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

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-001': _icyReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Fleet reports'));

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _heavySnow,
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Fleet reports'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'dry fleet report does not replace an existing weather warning',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lightSnow,
        ),
      );
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

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _heavySnow,
      ));
      await tester.pumpAndSettle();

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-003': _dryReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.warning);
      expect(navigationBloc.state.alertMessage, contains('Heavy'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'snowy fleet warning replaces an earlier weather warning message at same severity',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: WeatherState(
          status: WeatherStatus.monitoring,
          condition: _lightSnow,
        ),
      );
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

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _heavySnow,
      ));
      await tester.pumpAndSettle();

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-002': _snowyReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.warning);
      expect(navigationBloc.state.alertMessage, contains('Fleet reports'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'weather critical ice risk overrides an earlier fleet warning',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: const WeatherState.unavailable(),
      );
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

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-002': _snowyReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.warning);

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _iceRisk,
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Black ice risk'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'later snowy fleet warning does not downgrade an existing weather critical alert',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: const WeatherState.unavailable(),
      );
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

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _iceRisk,
      ));
      await tester.pumpAndSettle();

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-002': _snowyReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Black ice risk'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'later dry fleet report does not clear an existing fleet critical alert',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: const WeatherState.unavailable(),
      );
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

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-001': _icyReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Fleet reports'));

      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {
          'V-001': _icyReport,
          'V-003': _dryReport,
        },
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
      expect(navigationBloc.state.alertMessage, contains('Fleet reports'));

      await weatherController.close();
      await fleetController.close();
    });

    testWidgets(
        'non-hazard weather plus dry fleet keeps navigation alert-free',
        (tester) async {
      final weatherController = StreamController<WeatherState>.broadcast();
      final fleetController = StreamController<FleetState>.broadcast();

      whenListen(
        weatherBloc,
        weatherController.stream,
        initialState: const WeatherState.unavailable(),
      );
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

      weatherController.add(WeatherState(
        status: WeatherStatus.monitoring,
        condition: _lightSnow,
      ));
      fleetController.add(FleetState(
        status: FleetStatus.listening,
        activeReports: {'V-003': _dryReport},
      ));
      await tester.pumpAndSettle();

      expect(navigationBloc.state.hasSafetyAlert, isFalse);

      await weatherController.close();
      await fleetController.close();
    });
  });
}
