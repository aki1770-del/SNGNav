/// Provider chain integration tests — full guardian pipeline.
///
/// Tests the complete provider composition chain using REAL providers
/// (not mocks) to verify the guardian system works end-to-end:
///
///   SimulatedLocationProvider → DeadReckoningProvider → LocationBloc
///   MockRoutingEngine → RoutingBloc → NavigationBloc
///   SimulatedWeatherProvider → WeatherBloc
///
/// These tests verify what unit tests cannot: that the providers compose
/// correctly through the BLoC layer, that DR activates during the tunnel
/// phase of the simulated route, and that the system remains coherent
/// when all providers run concurrently.
///
/// Sprint 14 — S14-1: Kaizen (改善).
/// Architecture reference: A63 v3.0 §4 (location pipeline), §5 (BLoC wiring).
/// PHIL-001 trace: D3 (driver in snow) → D5 (evidence chain).
library;

import 'package:driving_weather/driving_weather.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:sngnav_snow_scene/config/provider_config.dart';
import 'package:kalman_dr/kalman_dr.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:sngnav_snow_scene/providers/simulated_location_provider.dart';

// ---------------------------------------------------------------------------
// Mock routing engine (network-free, deterministic)
// ---------------------------------------------------------------------------
class _MockRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(name: 'mock-integration');

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
          instruction: 'Arrive at Higashiokazaki',
          type: 'arrive',
          lengthKm: 0,
          timeSeconds: 0,
          position: request.destination,
        ),
      ],
      totalDistanceKm: 25.7,
      totalTimeSeconds: 1200,
      summary: 'Route 153, 25.7 km',
      engineInfo: const EngineInfo(name: 'mock-integration'),
    );
  }

  @override
  Future<void> dispose() async {}
}

// ---------------------------------------------------------------------------
// Test constants — Sakae → Higashiokazaki scenario
// ---------------------------------------------------------------------------
const _sakae = LatLng(35.1709, 136.9066);
const _higashiokazaki = LatLng(34.9554, 137.1791);

// ==========================================================================
// Group 1: ProviderConfig → real provider composition
// ==========================================================================
void main() {
  group('ProviderConfig creates working providers', () {
    test('simulated + DR(kalman) config produces positions through BLoC',
        () async {
      final config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        deadReckoningEnabled: true,
        drMode: DeadReckoningMode.kalman,
      );

      final provider = config.createLocationProvider(
        simulatedInterval: const Duration(milliseconds: 20),
      );
      final bloc = LocationBloc(provider: provider);

      bloc.add(const LocationStartRequested());

      // Wait for at least one position
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.quality, equals(LocationQuality.fix));
      expect(bloc.state.hasPosition, isTrue);
      expect(bloc.state.position!.latitude, closeTo(35.17, 0.02));

      await bloc.close();
    });

    test('simulated + DR(linear) config produces positions through BLoC',
        () async {
      final config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        deadReckoningEnabled: true,
        drMode: DeadReckoningMode.linear,
      );

      final provider = config.createLocationProvider(
        simulatedInterval: const Duration(milliseconds: 20),
      );
      final bloc = LocationBloc(provider: provider);

      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.quality, equals(LocationQuality.fix));
      expect(bloc.state.hasPosition, isTrue);

      await bloc.close();
    });

    test('simulated + DR disabled config produces raw GPS positions', () async {
      final config = ProviderConfig(
        locationType: LocationProviderType.simulated,
        deadReckoningEnabled: false,
      );

      final provider = config.createLocationProvider(
        simulatedInterval: const Duration(milliseconds: 20),
      );

      // Should NOT be wrapped in DeadReckoningProvider
      expect(provider, isA<SimulatedLocationProvider>());

      final bloc = LocationBloc(provider: provider);
      bloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(bloc.state.hasPosition, isTrue);

      await bloc.close();
    });

    test('simulated weather config produces conditions through BLoC',
        () async {
      final config = ProviderConfig(
        weatherType: WeatherProviderType.simulated,
      );

      final provider = config.createWeatherProvider(
        simulatedInterval: const Duration(milliseconds: 50),
      );
      final bloc = WeatherBloc(provider: provider);

      bloc.add(const WeatherMonitorStarted());
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(bloc.state.status, equals(WeatherStatus.monitoring));
      expect(bloc.state.hasCondition, isTrue);

      await bloc.close();
    });
  });

  // ==========================================================================
  // Group 2: SimulatedLocationProvider → DR → LocationBloc (tunnel scenario)
  // ==========================================================================
  group('Real SimulatedLocationProvider tunnel scenario', () {
    late SimulatedLocationProvider simGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc bloc;

    // Timing: 100ms interval × 20 steps = 2000ms full cycle
    // Tunnel phase: steps 10-14 × 100ms = 500ms (enough for 200ms GPS timeout)
    // GPS timeout: 200ms. DR activates at ~step 10 + 200ms = ~1200ms.
    // Tunnel exit: step 15 at 1500ms. DR deactivates after GPS recovery.

    setUp(() {
      simGps = SimulatedLocationProvider(
        interval: const Duration(milliseconds: 100),
        includeTunnel: true,
      );
      drProvider = DeadReckoningProvider(
        inner: simGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      bloc = LocationBloc(provider: drProvider);
    });

    tearDown(() async {
      await bloc.close();
    });

    test('phases 1-2: city + suburban driving produce continuous fixes',
        () async {
      bloc.add(const LocationStartRequested());

      // Let simulated provider run through city + suburban phases (steps 0-9)
      // 10 steps × 100ms = 1000ms
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(bloc.state.quality, equals(LocationQuality.fix));
      expect(bloc.state.hasPosition, isTrue);
      // Should be somewhere between Sakae and Okazaki
      expect(bloc.state.position!.latitude, lessThan(35.18));
      expect(bloc.state.position!.latitude, greaterThan(35.05));
    });

    test('phase 3: tunnel activates DR — BLoC keeps receiving positions',
        () async {
      bloc.add(const LocationStartRequested());

      // Step 10 (tunnel start) at ~1000ms. GPS timeout fires at ~1200ms.
      // Wait until DR is active (1300ms to be safe).
      await Future<void>.delayed(const Duration(milliseconds: 1300));

      // SimulatedLocationProvider should be in tunnel phase (step 10-14)
      expect(simGps.currentStep, greaterThanOrEqualTo(10));
      expect(simGps.currentStep, lessThanOrEqualTo(14));

      // DR should be active (tunnel = no GPS emissions)
      expect(drProvider.isDrActive, isTrue);

      // BLoC should NOT be stale — DR is feeding positions
      expect(bloc.state.quality, isNot(LocationQuality.stale));
      expect(bloc.state.quality, isNot(LocationQuality.uninitialized));
      expect(bloc.state.hasPosition, isTrue);
    });

    test('phase 4: tunnel exit recovers GPS — DR deactivates', () async {
      bloc.add(const LocationStartRequested());

      // Step 15 (tunnel exit) at ~1500ms. GPS recovery → DR deactivates.
      // Wait until step 16+ (1600ms + margin).
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      // Provider should be past tunnel (steps 15-19)
      expect(simGps.currentStep, greaterThanOrEqualTo(15));

      // GPS recovery: DR should deactivate
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(drProvider.isDrActive, isFalse);
      expect(bloc.state.quality, equals(LocationQuality.fix));
    });

    test('full cycle: city → suburban → tunnel (DR) → exit (GPS)', () async {
      bloc.add(const LocationStartRequested());
      final positions = <GeoPosition>[];

      // Collect positions for 1 full cycle
      final sub = bloc.stream.listen((state) {
        if (state.hasPosition) positions.add(state.position!);
      });

      // Full cycle: 20 steps × 100ms = 2000ms + DR + margin
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      await sub.cancel();

      // Should have received many positions (GPS + DR combined)
      expect(positions.length, greaterThan(10),
          reason: 'Expected positions from GPS + DR across full cycle');

      // First position should be near Sakae (phase 1)
      expect(positions.first.latitude, closeTo(35.17, 0.02));

      // Should have positions during tunnel (DR-generated)
      // DR positions continue in the direction of last GPS heading
      final hasMovedSouth = positions.any((p) => p.latitude < 35.10);
      expect(hasMovedSouth, isTrue,
          reason: 'DR should extrapolate southward through tunnel');
    });
  });

  // ==========================================================================
  // Group 3: DR mode comparison — Linear vs Kalman
  // ==========================================================================
  group('DR mode comparison: linear vs kalman through tunnel', () {
    test('both modes produce positions during tunnel phase', () async {
      final linearPositions = <GeoPosition>[];
      final kalmanPositions = <GeoPosition>[];

      // --- Linear mode ---
      final linearGps = SimulatedLocationProvider(
        interval: const Duration(milliseconds: 100),
        includeTunnel: true,
      );
      final linearDr = DeadReckoningProvider(
        inner: linearGps,
        mode: DeadReckoningMode.linear,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      final linearBloc = LocationBloc(provider: linearDr);
      linearBloc.add(const LocationStartRequested());

      final linearSub = linearBloc.stream.listen((state) {
        if (state.hasPosition) linearPositions.add(state.position!);
      });

      // --- Kalman mode ---
      final kalmanGps = SimulatedLocationProvider(
        interval: const Duration(milliseconds: 100),
        includeTunnel: true,
      );
      final kalmanDr = DeadReckoningProvider(
        inner: kalmanGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      final kalmanBloc = LocationBloc(provider: kalmanDr);
      kalmanBloc.add(const LocationStartRequested());

      final kalmanSub = kalmanBloc.stream.listen((state) {
        if (state.hasPosition) kalmanPositions.add(state.position!);
      });

      // Run through full cycle (20 steps × 100ms = 2000ms + DR + margin)
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      await linearSub.cancel();
      await kalmanSub.cancel();

      // Both should have produced positions
      expect(linearPositions, isNotEmpty);
      expect(kalmanPositions, isNotEmpty);

      // Both should have positions in the tunnel region (south of 35.10°)
      final linearTunnel = linearPositions.where((p) => p.latitude < 35.10);
      final kalmanTunnel = kalmanPositions.where((p) => p.latitude < 35.10);

      expect(linearTunnel, isNotEmpty,
          reason: 'Linear DR should produce tunnel positions');
      expect(kalmanTunnel, isNotEmpty,
          reason: 'Kalman DR should produce tunnel positions');

      await linearBloc.close();
      await kalmanBloc.close();
    });
  });

  // ==========================================================================
  // Group 4: Full guardian chain — Location + DR + Route + Navigate
  // ==========================================================================
  group('Full guardian chain: location → DR → route → navigate', () {
    late SimulatedLocationProvider simGps;
    late DeadReckoningProvider drProvider;
    late LocationBloc locationBloc;
    late RoutingBloc routingBloc;
    late NavigationBloc navigationBloc;

    setUp(() {
      simGps = SimulatedLocationProvider(
        interval: const Duration(milliseconds: 100),
        includeTunnel: true,
      );
      drProvider = DeadReckoningProvider(
        inner: simGps,
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      locationBloc = LocationBloc(provider: drProvider);
      routingBloc = RoutingBloc(engine: _MockRoutingEngine());
      navigationBloc = NavigationBloc();
    });

    tearDown(() async {
      await locationBloc.close();
      await routingBloc.close();
      await navigationBloc.close();
    });

    test('driver scenario: get fix → request route → start navigation',
        () async {
      // Step 1: Location fix — wait for first position through DR wrapper
      locationBloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(locationBloc.state.quality, equals(LocationQuality.fix));
      final origin = LatLng(
        locationBloc.state.position!.latitude,
        locationBloc.state.position!.longitude,
      );

      // Step 2: Request route
      routingBloc.add(RouteRequested(
        origin: origin,
        destination: _higashiokazaki,
        destinationLabel: '東岡崎駅',
      ));

      await expectLater(
        routingBloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.routeActive),
        ]),
      );

      // Step 3: Start navigation
      navigationBloc.add(NavigationStarted(
        route: routingBloc.state.route!,
        destinationLabel: '東岡崎駅',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(navigationBloc.state.status, equals(NavigationStatus.navigating));
      expect(navigationBloc.state.destinationLabel, equals('東岡崎駅'));
      expect(navigationBloc.state.route!.totalDistanceKm, closeTo(25.7, 0.1));
    });

    test('navigation survives tunnel: DR keeps location alive', () async {
      // Start location + route + navigation
      locationBloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      routingBloc.add(const RouteRequested(
        origin: _sakae,
        destination: _higashiokazaki,
        destinationLabel: '東岡崎駅',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      navigationBloc.add(NavigationStarted(
        route: routingBloc.state.route!,
        destinationLabel: '東岡崎駅',
      ));
      await Future<void>.delayed(Duration.zero);

      expect(navigationBloc.state.isNavigating, isTrue);

      // Drive into tunnel: step 10 at ~1000ms from start() + 100ms setup = ~1100ms.
      // GPS timeout fires ~200ms later = ~1300ms. Need ~1200ms from here.
      await Future<void>.delayed(const Duration(milliseconds: 1200));

      // Verify: navigation still active during tunnel
      expect(navigationBloc.state.isNavigating, isTrue);

      // Verify: DR active, location still providing positions
      expect(drProvider.isDrActive, isTrue);
      expect(locationBloc.state.hasPosition, isTrue);
      expect(locationBloc.state.quality, isNot(LocationQuality.stale));

      // The guardian chain holds: DR protects navigation from GPS loss
    });

    test('post-tunnel: all BLoCs remain healthy after GPS recovery', () async {
      locationBloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      routingBloc.add(const RouteRequested(
        origin: _sakae,
        destination: _higashiokazaki,
        destinationLabel: '東岡崎駅',
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      navigationBloc.add(NavigationStarted(
        route: routingBloc.state.route!,
        destinationLabel: '東岡崎駅',
      ));
      await Future<void>.delayed(Duration.zero);

      // Run through full cycle including tunnel exit (step 15 at ~1500ms + margin)
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      // All BLoCs healthy after tunnel exit
      expect(locationBloc.state.hasPosition, isTrue);
      expect(routingBloc.state.status, equals(RoutingStatus.routeActive));
      expect(navigationBloc.state.isNavigating, isTrue);

      // GPS should have recovered
      expect(drProvider.isDrActive, isFalse);
      expect(locationBloc.state.quality, equals(LocationQuality.fix));
    });

    test('route clear + navigation stop: clean teardown', () async {
      locationBloc.add(const LocationStartRequested());
      await Future<void>.delayed(const Duration(milliseconds: 100));

      routingBloc.add(const RouteRequested(
        origin: _sakae,
        destination: _higashiokazaki,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 100));

      navigationBloc.add(NavigationStarted(
        route: routingBloc.state.route!,
      ));
      await Future<void>.delayed(Duration.zero);

      // Clear route and stop navigation
      navigationBloc.add(const NavigationStopped());
      routingBloc.add(const RouteClearRequested());
      await Future<void>.delayed(Duration.zero);

      expect(navigationBloc.state.status, equals(NavigationStatus.idle));
      expect(routingBloc.state.status, equals(RoutingStatus.idle));

      // Location still running (driver didn't turn off GPS)
      expect(locationBloc.state.hasPosition, isTrue);
    });
  });

  // ==========================================================================
  // Group 5: Concurrent provider operation
  // ==========================================================================
  group('Concurrent providers: weather + location + navigation', () {
    test('all providers run simultaneously without interference', () async {
      // Create all providers
      final locationProvider = DeadReckoningProvider(
        inner: SimulatedLocationProvider(
          interval: const Duration(milliseconds: 100),
          includeTunnel: true,
        ),
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      final weatherProvider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 50),
      );

      // Create all BLoCs
      final locationBloc = LocationBloc(provider: locationProvider);
      final weatherBloc = WeatherBloc(provider: weatherProvider);
      final routingBloc = RoutingBloc(engine: _MockRoutingEngine());
      final navigationBloc = NavigationBloc();

      // Start all providers
      locationBloc.add(const LocationStartRequested());
      weatherBloc.add(const WeatherMonitorStarted());
      routingBloc.add(const RouteRequested(
        origin: _sakae,
        destination: _higashiokazaki,
        destinationLabel: '東岡崎駅',
      ));

      // Let them all run concurrently
      await Future<void>.delayed(const Duration(milliseconds: 300));

      // Start navigation
      if (routingBloc.state.hasRoute) {
        navigationBloc.add(NavigationStarted(
          route: routingBloc.state.route!,
          destinationLabel: '東岡崎駅',
        ));
      }
      await Future<void>.delayed(Duration.zero);

      // All systems healthy
      expect(locationBloc.state.hasPosition, isTrue);
      expect(weatherBloc.state.hasCondition, isTrue);
      expect(routingBloc.state.status, equals(RoutingStatus.routeActive));
      expect(navigationBloc.state.isNavigating, isTrue);

      // Let them run through tunnel + exit (step 15 at ~1500ms from start)
      await Future<void>.delayed(const Duration(milliseconds: 1800));

      // All still healthy after tunnel
      expect(locationBloc.state.hasPosition, isTrue);
      expect(weatherBloc.state.hasCondition, isTrue);
      expect(navigationBloc.state.isNavigating, isTrue);

      // Clean teardown — no crashes, no leaked subscriptions
      await locationBloc.close();
      await weatherBloc.close();
      await routingBloc.close();
      await navigationBloc.close();
    });

    test('weather hazard during tunnel — both guardians active', () async {
      final locationProvider = DeadReckoningProvider(
        inner: SimulatedLocationProvider(
          interval: const Duration(milliseconds: 100),
          includeTunnel: true,
        ),
        mode: DeadReckoningMode.kalman,
        gpsTimeout: const Duration(milliseconds: 200),
        extrapolationInterval: const Duration(milliseconds: 100),
      );
      final weatherProvider = SimulatedWeatherProvider(
        interval: const Duration(milliseconds: 50),
      );

      final locationBloc = LocationBloc(provider: locationProvider);
      final weatherBloc = WeatherBloc(provider: weatherProvider);

      locationBloc.add(const LocationStartRequested());
      weatherBloc.add(const WeatherMonitorStarted());

      // Run into tunnel phase (step 10 at ~1000ms, DR at ~1200ms)
      await Future<void>.delayed(const Duration(milliseconds: 1300));

      // Both guardians should be active:
      // - DR guardian: providing positions during tunnel
      // - Weather guardian: still monitoring conditions
      expect(locationBloc.state.hasPosition, isTrue);
      expect(weatherBloc.state.status, equals(WeatherStatus.monitoring));
      expect(weatherBloc.state.hasCondition, isTrue);

      // The driver is protected by BOTH guardians simultaneously:
      // DR gives position, weather gives conditions — even in the tunnel
      await locationBloc.close();
      await weatherBloc.close();
    });
  });

  // ==========================================================================
  // Group 6: Routing engine unavailability
  // ==========================================================================
  group('Routing engine failure: graceful degradation', () {
    test('engine unavailable → location still works', () async {
      final unavailableEngine = _UnavailableRoutingEngine();

      final locationBloc = LocationBloc(
        provider: SimulatedLocationProvider(
          interval: const Duration(milliseconds: 100),
          includeTunnel: false,
        ),
      );
      final routingBloc = RoutingBloc(engine: unavailableEngine);

      locationBloc.add(const LocationStartRequested());
      routingBloc.add(const RoutingEngineCheckRequested());

      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Location works regardless of routing engine status
      expect(locationBloc.state.hasPosition, isTrue);
      expect(locationBloc.state.quality, equals(LocationQuality.fix));

      // Routing reports unavailable
      expect(routingBloc.state.engineAvailable, isFalse);

      await locationBloc.close();
      await routingBloc.close();
    });

    test('engine error on route request → location unaffected', () async {
      final failingEngine = _FailingRoutingEngine();

      final locationBloc = LocationBloc(
        provider: SimulatedLocationProvider(
          interval: const Duration(milliseconds: 100),
          includeTunnel: false,
        ),
      );
      final routingBloc = RoutingBloc(engine: failingEngine);
      final navigationBloc = NavigationBloc();

      locationBloc.add(const LocationStartRequested());
      routingBloc.add(const RouteRequested(
        origin: _sakae,
        destination: _higashiokazaki,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Location is fine
      expect(locationBloc.state.hasPosition, isTrue);

      // Routing errored
      expect(routingBloc.state.status, equals(RoutingStatus.error));

      // Navigation never started
      expect(navigationBloc.state.status, equals(NavigationStatus.idle));

      await locationBloc.close();
      await routingBloc.close();
      await navigationBloc.close();
    });
  });
}

// ---------------------------------------------------------------------------
// Helper engines for error scenarios
// ---------------------------------------------------------------------------
class _UnavailableRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(name: 'unavailable');

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    throw RoutingException('Engine unavailable');
  }

  @override
  Future<void> dispose() async {}
}

class _FailingRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(name: 'failing');

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    throw RoutingException('Network timeout');
  }

  @override
  Future<void> dispose() async {}
}
