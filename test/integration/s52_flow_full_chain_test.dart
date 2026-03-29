library;

import 'dart:async';

import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:latlong2/latlong.dart';
import 'package:navigation_safety/navigation_safety.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:sngnav_snow_scene/providers/simulated_location_provider.dart';

import 's52_test_fixtures.dart';

class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(name: 'mock-s52-full-chain');

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    return RouteResult(
      shape: [request.origin, request.destination],
      maneuvers: [
        RouteManeuver(
          index: 0,
          instruction: 'Head east on Route 153',
          type: 'depart',
          lengthKm: 25.7,
          timeSeconds: 1200,
          position: request.origin,
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Arrive at mountain pass destination',
          type: 'arrive',
          lengthKm: 0,
          timeSeconds: 0,
          position: request.destination,
        ),
      ],
      totalDistanceKm: 25.7,
      totalTimeSeconds: 1200,
      summary: 'Unexpected snow scenario route',
      engineInfo: const EngineInfo(name: 'mock-s52-full-chain'),
    );
  }

  @override
  Future<void> dispose() async {}
}

class _ScriptedWeatherProvider implements WeatherProvider {
  _ScriptedWeatherProvider();

  final _controller = StreamController<WeatherCondition>.broadcast();
  final List<Timer> _timers = [];

  @override
  Stream<WeatherCondition> get conditions => _controller.stream;

  @override
  Future<void> startMonitoring() async {
    _emit(S52TestFixtures.clearWeather, Duration.zero);
    _emit(
      WeatherCondition(
        precipType: PrecipitationType.snow,
        intensity: PrecipitationIntensity.heavy,
        temperatureCelsius: -4.0,
        visibilityMeters: 150,
        windSpeedKmh: 40,
        timestamp: DateTime.now(),
      ),
      const Duration(milliseconds: 900),
    );
    _emit(S52TestFixtures.blackIceWeather, const Duration(milliseconds: 1600));
  }

  void _emit(WeatherCondition condition, Duration delay) {
    final timer = Timer(delay, () {
      if (!_controller.isClosed) {
        _controller.add(condition);
      }
    });
    _timers.add(timer);
  }

  @override
  Future<void> stopMonitoring() async {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();
    _controller.close();
  }
}

LatLng _southWestBounds(List<LatLng> shape) {
  return LatLng(
    shape.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
    shape.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
  );
}

LatLng _northEastBounds(List<LatLng> shape) {
  return LatLng(
    shape.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
    shape.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
  );
}

void main() {
  test('S52 full-chain D3 proof: unexpected snow scenario holds through tunnel and recovery', () async {
    final locationProvider = DeadReckoningProvider(
      inner: SimulatedLocationProvider(
        interval: const Duration(milliseconds: 100),
        includeTunnel: true,
      ),
      mode: DeadReckoningMode.kalman,
      gpsTimeout: const Duration(milliseconds: 200),
      extrapolationInterval: const Duration(milliseconds: 100),
    );
    final weatherProvider = _ScriptedWeatherProvider();
    final locationBloc = LocationBloc(provider: locationProvider);
    final weatherBloc = WeatherBloc(provider: weatherProvider);
    final routingBloc = RoutingBloc(engine: _MockRoutingEngine());
    final navigationBloc = NavigationBloc();
    final mapBloc = MapBloc();
    const safetyConfig = NavigationSafetyConfig();

    late final StreamSubscription locationSub;
    late final StreamSubscription routingSub;
    late final StreamSubscription weatherSub;

    mapBloc.add(const MapInitialized(center: S52TestFixtures.nagoya, zoom: 14));

    locationSub = locationBloc.stream.listen((state) {
      if (!state.hasPosition) return;
      if (!mapBloc.state.isFollowing) return;
      mapBloc.add(CenterChanged(LatLng(
        state.position!.latitude,
        state.position!.longitude,
      )));
    });

    routingSub = routingBloc.stream.listen((state) {
      if (!state.hasRoute || navigationBloc.state.isNavigating) return;
      final route = state.route!;
      navigationBloc.add(NavigationStarted(
        route: route,
        destinationLabel: state.destinationLabel,
      ));
      mapBloc.add(FitToBounds(
        southWest: _southWestBounds(route.shape),
        northEast: _northEastBounds(route.shape),
      ));
      mapBloc.add(const CameraModeChanged(CameraMode.follow));
    });

    weatherSub = weatherBloc.stream.listen((state) {
      if (!state.hasCondition) return;
      final assessment = DrivingConditionAssessment.fromCondition(state.condition!);
      const simulator = SafetyScoreSimulator();
      final result = simulator.simulate(
        runs: 200,
        speed: 70,
        gripFactor: assessment.gripFactor,
        surface: assessment.surfaceState,
        visibilityMeters: state.condition!.visibilityMeters,
        seed: S52TestFixtures.transitionSeed,
      );
      final severity = result.score.toAlertSeverity(safetyConfig);
      if (severity != null) {
        navigationBloc.add(SafetyAlertReceived(
          message: assessment.advisoryMessage,
          severity: severity,
        ));
      }
    });

    locationBloc.add(const LocationStartRequested());
    weatherBloc.add(const WeatherMonitorStarted());
    routingBloc.add(const RouteRequested(
      origin: S52TestFixtures.sakae,
      destination: S52TestFixtures.higashiokazaki,
      destinationLabel: 'Mountain pass destination',
    ));

    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(locationBloc.state.hasPosition, isTrue);
    expect(routingBloc.state.hasRoute, isTrue);
    expect(navigationBloc.state.isNavigating, isTrue);
    expect(mapBloc.state.cameraMode, CameraMode.follow);

    await Future<void>.delayed(const Duration(milliseconds: 1100));

    expect(locationBloc.state.hasPosition, isTrue);
    expect(locationBloc.state.isDeadReckoning, isTrue,
        reason: 'Tunnel phase should be protected by DR');
    expect(navigationBloc.state.isNavigating, isTrue);
    expect(weatherBloc.state.isHazardous, isTrue,
        reason: 'Unexpected snow should be hazardous by the tunnel segment');
    expect(navigationBloc.state.hasSafetyAlert, isTrue);
    expect(navigationBloc.state.alertSeverity, isNotNull);
    expect(mapBloc.state.cameraMode, CameraMode.follow);

    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(locationBloc.state.hasPosition, isTrue);
    expect(locationBloc.state.isDeadReckoning, isFalse,
        reason: 'GPS should have recovered after the tunnel');
    expect(locationBloc.state.quality, LocationQuality.fix);
    expect(navigationBloc.state.isNavigating, isTrue);
    expect(navigationBloc.state.hasSafetyAlert, isTrue);
    expect(
      navigationBloc.state.alertSeverity,
      equals(AlertSeverity.critical),
      reason: 'Black ice should drive the final advisory to critical',
    );
    expect(
      navigationBloc.state.alertMessage,
      contains('Black ice risk'),
    );
    expect(mapBloc.state.cameraMode, CameraMode.follow);
    expect(mapBloc.state.center.latitude, lessThan(S52TestFixtures.nagoya.latitude));
    expect(mapBloc.state.isLayerVisible(MapLayerType.safety), isTrue);
    expect(mapBloc.state.isLayerVisible(MapLayerType.weather), isTrue);

    await locationSub.cancel();
    await routingSub.cancel();
    await weatherSub.cancel();
    await locationBloc.close();
    await weatherBloc.close();
    await routingBloc.close();
    await navigationBloc.close();
    await mapBloc.close();
  });
}