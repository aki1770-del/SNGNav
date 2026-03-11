/// Snow-scene demo flow integration test.
///
/// Verifies the composed widget flow through SnowSceneScaffold:
///   1. RouteRequested on RoutingBloc calculates a route
///   2. Scaffold reacts with NavigationStarted + fit-to-route
///   3. Auto-advance timer moves to the next maneuver after 8 seconds
///   4. Hazardous weather transition raises a safety alert in NavigationBloc
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:driving_consent/driving_consent.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';
import 'package:mocktail/mocktail.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';
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
import 'package:sngnav_snow_scene/widgets/snow_scene_scaffold.dart';

class MockLocationBloc extends MockBloc<LocationEvent, LocationState>
    implements LocationBloc {}

class MockConsentBloc extends MockBloc<ConsentEvent, ConsentState>
    implements ConsentBloc {}

class MockFleetBloc extends MockBloc<FleetEvent, FleetState>
    implements FleetBloc {}

class _ScriptedWeatherProvider implements WeatherProvider {
  final _controller = StreamController<WeatherCondition>.broadcast();

  @override
  Stream<WeatherCondition> get conditions => _controller.stream;

  void emit(WeatherCondition condition) {
    if (!_controller.isClosed) {
      _controller.add(condition);
    }
  }

  @override
  Future<void> startMonitoring() async {}

  @override
  Future<void> stopMonitoring() async {}

  @override
  void dispose() {
    _controller.close();
  }
}

class _ImmediateRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(name: 'test-demo-engine');

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    return RouteResult(
      shape: const [
        LatLng(35.1709, 136.9066),
        LatLng(35.1013, 137.0628),
        LatLng(34.9554, 137.1791),
      ],
      maneuvers: const [
        RouteManeuver(
          index: 0,
          instruction: 'Depart Sakae Station heading east',
          type: 'depart',
          lengthKm: 7.2,
          timeSeconds: 420,
          position: LatLng(35.1709, 136.9066),
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Continue southeast on Route 153',
          type: 'straight',
          lengthKm: 12.4,
          timeSeconds: 760,
          position: LatLng(35.1013, 137.0628),
        ),
        RouteManeuver(
          index: 2,
          instruction: 'Arrive at Higashiokazaki Station',
          type: 'arrive',
          lengthKm: 0.0,
          timeSeconds: 0,
          position: LatLng(34.9554, 137.1791),
        ),
      ],
      totalDistanceKm: 28.3,
      totalTimeSeconds: 2000,
      summary: 'Sakae Station → Route 153 → Higashiokazaki Station',
      engineInfo: info,
    );
  }

  @override
  Future<void> dispose() async {}
}

final _now = DateTime.now();

final _lightSnow = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.light,
  temperatureCelsius: -1.0,
  visibilityMeters: 3000,
  windSpeedKmh: 15,
  timestamp: _now,
);

final _blackIceWeather = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -4.0,
  visibilityMeters: 150,
  windSpeedKmh: 35,
  iceRisk: true,
  timestamp: _now.add(const Duration(minutes: 5)),
);

Widget _buildWidget({
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
  testWidgets(
      'RouteRequested drives navigation start, auto-advance, and weather safety alert',
      (tester) async {
    final locationBloc = MockLocationBloc();
    final consentBloc = MockConsentBloc();
    final fleetBloc = MockFleetBloc();
    final routingBloc = RoutingBloc(engine: _ImmediateRoutingEngine());
    final navigationBloc = NavigationBloc();
    final mapBloc = MapBloc();
    final weatherProvider = _ScriptedWeatherProvider();
    final weatherBloc = WeatherBloc(provider: weatherProvider);

    when(() => locationBloc.state)
        .thenReturn(const LocationState.uninitialized());
    when(() => consentBloc.state).thenReturn(ConsentState(
      status: ConsentBlocStatus.ready,
      consents: {
        ConsentPurpose.fleetLocation: ConsentRecord(
          purpose: ConsentPurpose.fleetLocation,
          status: ConsentStatus.denied,
          jurisdiction: Jurisdiction.appi,
          updatedAt: DateTime(2026, 3, 11),
        ),
      },
    ));
    when(() => fleetBloc.state).thenReturn(const FleetState.idle());

    await tester.pumpWidget(_buildWidget(
      locationBloc: locationBloc,
      routingBloc: routingBloc,
      navigationBloc: navigationBloc,
      mapBloc: mapBloc,
      weatherBloc: weatherBloc,
      consentBloc: consentBloc,
      fleetBloc: fleetBloc,
    ));

    await tester.pump();

    expect(mapBloc.state.status, MapStatus.ready);
    expect(navigationBloc.state.status, NavigationStatus.idle);

    weatherBloc.add(const WeatherMonitorStarted());
    weatherProvider.emit(_lightSnow);
    routingBloc.add(const RouteRequested(
      origin: LatLng(35.1709, 136.9066),
      destination: LatLng(34.9554, 137.1791),
      destinationLabel: 'Higashiokazaki Station',
    ));

    await tester.pump();
    await tester.pump();

    expect(routingBloc.state.status, RoutingStatus.routeActive);
    expect(navigationBloc.state.status, NavigationStatus.navigating);
    expect(navigationBloc.state.route, isNotNull);
    expect(navigationBloc.state.currentManeuverIndex, 0);
    expect(navigationBloc.state.destinationLabel, 'Higashiokazaki Station');
    expect(mapBloc.state.cameraMode, CameraMode.overview);
    expect(mapBloc.state.hasFitBounds, isTrue);
    expect(navigationBloc.state.hasSafetyAlert, isFalse);

    weatherProvider.emit(_blackIceWeather);
    await tester.pump();
    await tester.pump();

    expect(weatherBloc.state.isHazardous, isTrue);
    expect(navigationBloc.state.hasSafetyAlert, isTrue);
    expect(navigationBloc.state.alertSeverity, AlertSeverity.critical);
    expect(navigationBloc.state.alertMessage, contains('Black ice risk'));

    await tester.pump(const Duration(seconds: 8));
    await tester.pump();

    expect(navigationBloc.state.status, NavigationStatus.navigating);
    expect(navigationBloc.state.currentManeuverIndex, 1);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

  });
}