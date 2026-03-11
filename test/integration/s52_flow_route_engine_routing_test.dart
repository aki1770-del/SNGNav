library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

import 's52_test_fixtures.dart';

class _ScenarioRoutingEngine implements RoutingEngine {
  _ScenarioRoutingEngine({
    this.result,
    this.error,
    this.delay = Duration.zero,
    this.available = true,
  });

  final RouteResult? result;
  final Object? error;
  final Duration delay;
  final bool available;

  int calculateCallCount = 0;
  RouteRequest? lastRequest;
  bool disposed = false;

  @override
  EngineInfo get info => EngineInfo(name: 'mock-s52-routing', queryLatency: delay);

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    calculateCallCount++;
    lastRequest = request;
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    if (error != null) {
      throw error!;
    }
    return result ?? S52TestFixtures.nagoyaToOkazakiRoute;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  group('S52 Flow 2: route -> engine -> routing bloc', () {
    test('successful route request flows from engine to routeActive state', () async {
      final engine = _ScenarioRoutingEngine(
        result: S52TestFixtures.nagoyaToOkazakiRoute,
      );
      final bloc = RoutingBloc(engine: engine);

      bloc.add(const RouteRequested(
        origin: S52TestFixtures.nagoya,
        destination: S52TestFixtures.higashiokazaki,
        destinationLabel: 'Higashiokazaki',
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading)
              .having((s) => s.destinationLabel, 'label', 'Higashiokazaki'),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.routeActive)
              .having((s) => s.route, 'route', S52TestFixtures.nagoyaToOkazakiRoute)
              .having((s) => s.engineAvailable, 'engineAvailable', isTrue),
        ]),
      );

      expect(engine.calculateCallCount, 1);
      expect(engine.lastRequest, S52TestFixtures.nagoyaToOkazakiRequest);

      await bloc.close();
      expect(engine.disposed, isTrue);
    });

    test('engine failure surfaces as error state with message', () async {
      final engine = _ScenarioRoutingEngine(
        error: RoutingException('No route found'),
      );
      final bloc = RoutingBloc(engine: engine);

      bloc.add(const RouteRequested(
        origin: S52TestFixtures.nagoya,
        destination: S52TestFixtures.higashiokazaki,
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.error)
              .having((s) => s.errorMessage, 'errorMessage', contains('No route found')),
        ]),
      );

      await bloc.close();
    });

    test('delayed engine keeps bloc in loading until route arrives', () async {
      final engine = _ScenarioRoutingEngine(
        result: S52TestFixtures.nagoyaToOkazakiRoute,
        delay: const Duration(milliseconds: 40),
      );
      final bloc = RoutingBloc(engine: engine);

      bloc.add(const RouteRequested(
        origin: S52TestFixtures.nagoya,
        destination: S52TestFixtures.higashiokazaki,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(bloc.state.status, RoutingStatus.loading);

      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(bloc.state.status, RoutingStatus.routeActive);
      expect(bloc.state.route, S52TestFixtures.nagoyaToOkazakiRoute);

      await bloc.close();
    });

    test('new route request after active route replaces the route', () async {
      final engine = _ScenarioRoutingEngine(
        result: S52TestFixtures.nagoyaToInuyamaRoute,
      );
      final bloc = RoutingBloc(engine: engine);

      bloc.emit(RoutingState(
        status: RoutingStatus.routeActive,
        route: S52TestFixtures.nagoyaToOkazakiRoute,
        destinationLabel: 'Higashiokazaki',
        engineAvailable: true,
      ));

      bloc.add(const RouteRequested(
        origin: S52TestFixtures.nagoya,
        destination: S52TestFixtures.inuyama,
        destinationLabel: 'Inuyama Castle',
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.loading)
              .having((s) => s.destinationLabel, 'label', 'Inuyama Castle'),
          isA<RoutingState>()
              .having((s) => s.status, 'status', RoutingStatus.routeActive)
              .having((s) => s.route, 'route', S52TestFixtures.nagoyaToInuyamaRoute)
              .having((s) => s.destinationLabel, 'label', 'Inuyama Castle'),
        ]),
      );

      await bloc.close();
    });

    test('engine availability and route contract assumptions remain stable', () async {
      final engine = _ScenarioRoutingEngine(
        result: S52TestFixtures.nagoyaToOkazakiRoute,
        available: true,
      );
      final bloc = RoutingBloc(engine: engine);

      bloc.add(const RoutingEngineCheckRequested());
      await Future<void>.delayed(Duration.zero);

      expect(bloc.state.engineAvailable, isTrue);

      bloc.add(const RouteRequested(
        origin: S52TestFixtures.nagoya,
        destination: S52TestFixtures.higashiokazaki,
      ));
      await Future<void>.delayed(Duration.zero);

      final route = bloc.state.route;
      expect(route, isNotNull);
      expect(route!.hasGeometry, isTrue);
      expect(route.maneuvers, isNotEmpty);
      expect(route.engineInfo.name, 'mock-s52');

      await bloc.close();
    });
  });
}