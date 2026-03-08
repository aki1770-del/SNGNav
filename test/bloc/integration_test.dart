/// BLoC integration tests — widget-mediated cross-BLoC workflows.
///
/// A63 §5.4: "Each BLoC owns a single domain. Each widget subscribes
/// to only the BLoC it needs." Communication is widget-mediated.
///
/// These tests simulate what a widget orchestrator would do:
///   1. Read one BLoC's state
///   2. Dispatch to another BLoC based on that state
///
/// No Flutter widget tree needed — pure Dart integration testing.
///
/// Sprint 7 Day 4 — BLoC integration wiring.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:kalman_dr/kalman_dr.dart';
import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:sngnav_snow_scene/models/models.dart';
import 'package:sngnav_snow_scene/providers/providers.dart';

// ---------------------------------------------------------------------------
// Mock engine (reusable from routing_bloc_test)
// ---------------------------------------------------------------------------
class MockRoutingEngine implements RoutingEngine {
  RouteResult? resultToReturn;
  bool available = true;
  bool shouldThrow = false;

  @override
  EngineInfo get info => const EngineInfo(name: 'mock');

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    if (shouldThrow) throw RoutingException('Engine error');
    return resultToReturn ?? _defaultRoute;
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);

final _defaultRoute = RouteResult(
  shape: const [_nagoya, _toyota],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head east on Route 153',
      type: 'depart',
      lengthKm: 12.5,
      timeSeconds: 720,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Arrive at Toyota HQ',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _toyota,
    ),
  ],
  totalDistanceKm: 25.7,
  totalTimeSeconds: 1200,
  summary: '25.7 km, 20 min',
  engineInfo: const EngineInfo(name: 'mock'),
);

// ---------------------------------------------------------------------------
// Integration tests
// ---------------------------------------------------------------------------
void main() {
  group('Cross-BLoC workflow: route request → navigate → arrive', () {
    late MockRoutingEngine engine;
    late RoutingBloc routingBloc;
    late NavigationBloc navigationBloc;
    late MapBloc mapBloc;

    setUp(() {
      engine = MockRoutingEngine();
      routingBloc = RoutingBloc(engine: engine);
      navigationBloc = NavigationBloc();
      mapBloc = MapBloc();

      // Initialize map
      mapBloc.add(const MapInitialized(center: _nagoya, zoom: 14.0));
    });

    tearDown(() async {
      await routingBloc.close();
      await navigationBloc.close();
      await mapBloc.close();
    });

    test('full lifecycle: request → route → navigate → advance → arrive → clear', () async {
      // --- Step 1: User requests a route (widget dispatches to RoutingBloc) ---
      routingBloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
        destinationLabel: 'Toyota HQ',
      ));

      // Wait for RoutingBloc to reach routeActive
      await expectLater(
        routingBloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.routeActive),
        ]),
      );

      // --- Step 2: Widget reads RoutingBloc → dispatches to NavigationBloc + MapBloc ---
      // (This is what a BlocListener in the widget tree would do)
      final route = routingBloc.state.route!;

      navigationBloc.add(NavigationStarted(
        route: route,
        destinationLabel: 'Toyota HQ',
      ));

      // Widget also fits map to route bounds
      mapBloc.add(FitToBounds(
        southWest: LatLng(
          route.shape.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
          route.shape.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
        ),
        northEast: LatLng(
          route.shape.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
          route.shape.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
        ),
      ));

      await Future<void>.delayed(Duration.zero); // let BLoCs process

      // Verify NavigationBloc is navigating
      expect(navigationBloc.state.status, equals(NavigationStatus.navigating));
      expect(navigationBloc.state.route, equals(route));
      expect(navigationBloc.state.currentManeuverIndex, equals(0));
      expect(navigationBloc.state.destinationLabel, equals('Toyota HQ'));

      // Verify MapBloc is in overview mode with bounds
      expect(mapBloc.state.cameraMode, equals(CameraMode.overview));
      expect(mapBloc.state.hasFitBounds, isTrue);

      // --- Step 3: Driver advances through maneuvers ---
      navigationBloc.add(const ManeuverAdvanced()); // index 0 → 1
      await Future<void>.delayed(Duration.zero);
      navigationBloc.add(const ManeuverAdvanced()); // index 1 (last) → arrived

      await Future<void>.delayed(Duration.zero);

      // Last maneuver → arrived
      expect(navigationBloc.state.status, equals(NavigationStatus.arrived));
      expect(navigationBloc.state.progress, equals(1.0));

      // --- Step 4: User clears route ---
      routingBloc.add(const RouteClearRequested());
      navigationBloc.add(const NavigationStopped());
      mapBloc.add(const CameraModeChanged(CameraMode.freeLook));

      await Future<void>.delayed(Duration.zero);

      // All BLoCs back to initial/idle states
      expect(routingBloc.state.status, equals(RoutingStatus.idle));
      expect(navigationBloc.state.status, equals(NavigationStatus.idle));
      expect(mapBloc.state.cameraMode, equals(CameraMode.freeLook));
      expect(mapBloc.state.hasFitBounds, isFalse);
    });
  });

  group('Cross-BLoC workflow: location → map follow', () {
    late LocationBloc locationBloc;
    late MapBloc mapBloc;

    setUp(() {
      locationBloc = LocationBloc(
        provider: _MockLocationProvider(),
      );
      mapBloc = MapBloc();
      mapBloc.add(const MapInitialized(center: _nagoya, zoom: 14.0));
    });

    tearDown(() async {
      await locationBloc.close();
      await mapBloc.close();
    });

    test('position update → map center (follow mode)', () async {
      await Future<void>.delayed(Duration.zero); // let map init

      // Enable follow mode
      mapBloc.add(const CameraModeChanged(CameraMode.follow));
      await Future<void>.delayed(Duration.zero);
      expect(mapBloc.state.isFollowing, isTrue);

      // Simulate: LocationBloc receives position → widget dispatches to MapBloc
      const newPosition = LatLng(35.0504, 137.1566); // Toyota
      mapBloc.add(const CenterChanged(newPosition));
      await Future<void>.delayed(Duration.zero);

      expect(mapBloc.state.center, equals(newPosition));
      expect(mapBloc.state.isFollowing, isTrue); // still following

      // User pans → follow disabled
      mapBloc.add(const UserPanDetected());
      await Future<void>.delayed(Duration.zero);

      expect(mapBloc.state.isFollowing, isFalse);
      expect(mapBloc.state.cameraMode, equals(CameraMode.freeLook));
    });
  });

  group('Cross-BLoC workflow: safety alert during navigation', () {
    late NavigationBloc navigationBloc;

    setUp(() {
      navigationBloc = NavigationBloc();
    });

    tearDown(() async {
      await navigationBloc.close();
    });

    test('weather alert arrives during active navigation', () async {
      // Start navigation
      navigationBloc.add(NavigationStarted(
        route: _defaultRoute,
        destinationLabel: 'Toyota HQ',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(navigationBloc.state.isNavigating, isTrue);
      expect(navigationBloc.state.hasSafetyAlert, isFalse);

      // Weather system sends alert
      navigationBloc.add(const SafetyAlertReceived(
        message: 'Heavy snow warning — Aichi mountain pass',
        severity: AlertSeverity.warning,
      ));
      await Future<void>.delayed(Duration.zero);

      // Navigation continues with alert overlay
      expect(navigationBloc.state.isNavigating, isTrue);
      expect(navigationBloc.state.hasSafetyAlert, isTrue);
      expect(navigationBloc.state.alertSeverity, equals(AlertSeverity.warning));

      // Driver dismisses
      navigationBloc.add(const SafetyAlertDismissed());
      await Future<void>.delayed(Duration.zero);

      expect(navigationBloc.state.hasSafetyAlert, isFalse);
      expect(navigationBloc.state.isNavigating, isTrue); // still navigating
    });
  });

  group('Cross-BLoC workflow: route error → no navigation', () {
    late MockRoutingEngine engine;
    late RoutingBloc routingBloc;
    late NavigationBloc navigationBloc;

    setUp(() {
      engine = MockRoutingEngine()..shouldThrow = true;
      routingBloc = RoutingBloc(engine: engine);
      navigationBloc = NavigationBloc();
    });

    tearDown(() async {
      await routingBloc.close();
      await navigationBloc.close();
    });

    test('routing error does not start navigation', () async {
      routingBloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
      ));

      await expectLater(
        routingBloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.error),
        ]),
      );

      // Widget sees error → does NOT dispatch to NavigationBloc
      expect(navigationBloc.state.status, equals(NavigationStatus.idle));
      expect(navigationBloc.state.hasRoute, isFalse);
    });
  });

  group('Cross-BLoC workflow: layer visibility across BLoCs', () {
    late MapBloc mapBloc;

    setUp(() {
      mapBloc = MapBloc();
      mapBloc.add(const MapInitialized(center: _nagoya, zoom: 14.0));
    });

    tearDown(() async {
      await mapBloc.close();
    });

    test('enable weather + safety layers for Snow Scene', () async {
      await Future<void>.delayed(Duration.zero);

      // Default: only route visible
      expect(mapBloc.state.isLayerVisible(MapLayerType.route), isTrue);
      expect(mapBloc.state.isLayerVisible(MapLayerType.weather), isFalse);
      expect(mapBloc.state.isLayerVisible(MapLayerType.safety), isFalse);

      // Snow Scene enables weather and safety overlays
      mapBloc.add(const LayerToggled(
          layer: MapLayerType.weather, visible: true));
      mapBloc.add(const LayerToggled(
          layer: MapLayerType.safety, visible: true));
      await Future<void>.delayed(Duration.zero);

      expect(mapBloc.state.isLayerVisible(MapLayerType.route), isTrue);
      expect(mapBloc.state.isLayerVisible(MapLayerType.weather), isTrue);
      expect(mapBloc.state.isLayerVisible(MapLayerType.safety), isTrue);
      expect(mapBloc.state.isLayerVisible(MapLayerType.fleet), isFalse);
    });
  });

  group('ADR-OL-2 proof: engine swap — RoutingBloc identical with any engine', () {
    // This test proves that RoutingBloc produces identical state transitions
    // regardless of which RoutingEngine is injected. The BLoC doesn't change —
    // only the engine. ADR-OL-2 value proposition in code.

    final osrmRoute = RouteResult(
      shape: const [_nagoya, _toyota],
      maneuvers: const [
        RouteManeuver(
          index: 0,
          instruction: 'Depart on Route 153',
          type: 'depart',
          lengthKm: 12.5,
          timeSeconds: 720,
          position: _nagoya,
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Arrive at destination',
          type: 'arrive',
          lengthKm: 0,
          timeSeconds: 0,
          position: _toyota,
        ),
      ],
      totalDistanceKm: 25.7,
      totalTimeSeconds: 1200,
      summary: '25.7 km, 20 min',
      engineInfo: const EngineInfo(name: 'osrm'),
    );

    final valhallaRoute = RouteResult(
      shape: const [_nagoya, _toyota],
      maneuvers: const [
        RouteManeuver(
          index: 0,
          instruction: 'Head east',
          type: 'depart',
          lengthKm: 12.5,
          timeSeconds: 720,
          position: _nagoya,
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Arrive at Toyota',
          type: 'arrive',
          lengthKm: 0,
          timeSeconds: 0,
          position: _toyota,
        ),
      ],
      totalDistanceKm: 25.7,
      totalTimeSeconds: 1200,
      summary: '25.7 km, 20 min',
      engineInfo: const EngineInfo(name: 'valhalla'),
    );

    test('OSRM engine: idle → loading → routeActive', () async {
      final engine = MockRoutingEngine()..resultToReturn = osrmRoute;
      final bloc = RoutingBloc(engine: engine);

      bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
        destinationLabel: 'Toyota HQ',
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.routeActive)
              .having((s) => s.route?.engineInfo.name, 'engine', 'osrm'),
        ]),
      );

      // NavigationBloc accepts the route without caring about engine.
      final navBloc = NavigationBloc();
      navBloc.add(NavigationStarted(
        route: bloc.state.route!,
        destinationLabel: 'Toyota HQ',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(navBloc.state.status, NavigationStatus.navigating);
      expect(navBloc.state.route?.engineInfo.name, 'osrm');

      await navBloc.close();
      await bloc.close();
    });

    test('Valhalla engine: identical state transitions', () async {
      final engine = MockRoutingEngine()..resultToReturn = valhallaRoute;
      final bloc = RoutingBloc(engine: engine);

      bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
        destinationLabel: 'Toyota HQ',
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.routeActive)
              .having((s) => s.route?.engineInfo.name, 'engine', 'valhalla'),
        ]),
      );

      // NavigationBloc accepts Valhalla route identically.
      final navBloc = NavigationBloc();
      navBloc.add(NavigationStarted(
        route: bloc.state.route!,
        destinationLabel: 'Toyota HQ',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(navBloc.state.status, NavigationStatus.navigating);
      expect(navBloc.state.route?.engineInfo.name, 'valhalla');

      await navBloc.close();
      await bloc.close();
    });
  });
}

// ---------------------------------------------------------------------------
// Minimal mock for LocationBloc (just needs the interface)
// ---------------------------------------------------------------------------
class _MockLocationProvider implements LocationProvider {
  final _controller = StreamController<GeoPosition>.broadcast();

  @override
  Stream<GeoPosition> get positions => _controller.stream;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    await _controller.close();
  }
}
