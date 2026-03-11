/// RoutingBloc unit tests — 4-state route lifecycle machine.
///
/// Tests the complete state machine with a MockRoutingEngine.
/// No HTTP required — pure logic testing.
///
/// Sprint 7 Day 3 — RoutingBloc extraction.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'package:sngnav_snow_scene/bloc/bloc.dart';
import 'package:routing_engine/routing_engine.dart';

// ---------------------------------------------------------------------------
// Mock engine — controllable for testing
// ---------------------------------------------------------------------------
class MockRoutingEngine implements RoutingEngine {
  RouteResult? resultToReturn;
  bool available = true;
  bool shouldThrow = false;
  String throwMessage = 'Engine error';
  bool disposed = false;
  int calculateCallCount = 0;
  RouteRequest? lastRequest;

  @override
  EngineInfo get info => const EngineInfo(name: 'mock');

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    calculateCallCount++;
    lastRequest = request;
    if (shouldThrow) {
      throw RoutingException(throwMessage);
    }
    return resultToReturn ?? _defaultRoute;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------
const _nagoya = LatLng(35.1709, 136.8815);
const _toyota = LatLng(35.0504, 137.1566);
const _inuyama = LatLng(35.3883, 136.9394);

final _defaultRoute = RouteResult(
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
  totalTimeSeconds: 1830,
  summary: '25.7 km, 31 min',
  engineInfo: const EngineInfo(name: 'mock', queryLatency: Duration(milliseconds: 5)),
);

final _secondRoute = RouteResult(
  shape: const [_nagoya, _inuyama],
  maneuvers: const [
    RouteManeuver(
      index: 0,
      instruction: 'Head north',
      type: 'depart',
      lengthKm: 18.0,
      timeSeconds: 1200,
      position: _nagoya,
    ),
    RouteManeuver(
      index: 1,
      instruction: 'Arrive at Inuyama',
      type: 'arrive',
      lengthKm: 0,
      timeSeconds: 0,
      position: _inuyama,
    ),
  ],
  totalDistanceKm: 18.0,
  totalTimeSeconds: 1200,
  summary: '18.0 km, 20 min',
  engineInfo: const EngineInfo(name: 'mock', queryLatency: Duration(milliseconds: 3)),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------
void main() {
  group('RouteResult model', () {
    test('eta computes correctly', () {
      expect(_defaultRoute.eta, equals(const Duration(seconds: 1830)));
    });

    test('hasGeometry true with 2+ points', () {
      expect(_defaultRoute.hasGeometry, isTrue);
    });

    test('hasGeometry false with 0 points', () {
      const empty = RouteResult(
        shape: [],
        maneuvers: [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '',
        engineInfo: EngineInfo(name: 'mock'),
      );
      expect(empty.hasGeometry, isFalse);
    });

    test('hasGeometry false with 1 point', () {
      const single = RouteResult(
        shape: [_nagoya],
        maneuvers: [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '',
        engineInfo: EngineInfo(name: 'mock'),
      );
      expect(single.hasGeometry, isFalse);
    });

    test('equality works (Equatable)', () {
      final a = RouteResult(
        shape: const [_nagoya, _toyota],
        maneuvers: const [],
        totalDistanceKm: 10,
        totalTimeSeconds: 600,
        summary: 'test',
        engineInfo: const EngineInfo(name: 'mock'),
      );
      final b = RouteResult(
        shape: const [_nagoya, _toyota],
        maneuvers: const [],
        totalDistanceKm: 10,
        totalTimeSeconds: 600,
        summary: 'test',
        engineInfo: const EngineInfo(name: 'mock'),
      );
      expect(a, equals(b));
    });

    test('toString includes distance and engine', () {
      final s = _defaultRoute.toString();
      expect(s, contains('25.7'));
      expect(s, contains('mock'));
    });
  });

  group('RouteManeuver model', () {
    test('equality works', () {
      const a = RouteManeuver(
        index: 0,
        instruction: 'Go',
        type: 'depart',
        lengthKm: 1.0,
        timeSeconds: 60,
        position: _nagoya,
      );
      const b = RouteManeuver(
        index: 0,
        instruction: 'Go',
        type: 'depart',
        lengthKm: 1.0,
        timeSeconds: 60,
        position: _nagoya,
      );
      expect(a, equals(b));
    });
  });

  group('EngineInfo model', () {
    test('defaults', () {
      const info = EngineInfo(name: 'osrm');
      expect(info.version, equals('unknown'));
      expect(info.queryLatency, equals(Duration.zero));
    });

    test('toString includes name and latency', () {
      const info = EngineInfo(
        name: 'valhalla',
        queryLatency: Duration(milliseconds: 464),
      );
      expect(info.toString(), contains('valhalla'));
      expect(info.toString(), contains('464'));
    });
  });

  group('RouteRequest model', () {
    test('defaults to auto costing and ja-JP', () {
      const req = RouteRequest(origin: _nagoya, destination: _toyota);
      expect(req.costing, equals('auto'));
      expect(req.language, equals('ja-JP'));
    });

    test('equality works', () {
      const a = RouteRequest(origin: _nagoya, destination: _toyota);
      const b = RouteRequest(origin: _nagoya, destination: _toyota);
      expect(a, equals(b));
    });
  });

  group('RoutingState', () {
    test('idle has no route and no error', () {
      const state = RoutingState.idle();
      expect(state.status, equals(RoutingStatus.idle));
      expect(state.hasRoute, isFalse);
      expect(state.isLoading, isFalse);
      expect(state.route, isNull);
      expect(state.errorMessage, isNull);
    });

    test('hasRoute true only when routeActive with route', () {
      final state = RoutingState(
        status: RoutingStatus.routeActive,
        route: _defaultRoute,
      );
      expect(state.hasRoute, isTrue);
    });

    test('hasRoute false when loading even with route', () {
      final state = RoutingState(
        status: RoutingStatus.loading,
        route: _defaultRoute,
      );
      expect(state.hasRoute, isFalse);
    });

    test('isLoading true when loading', () {
      const state = RoutingState(status: RoutingStatus.loading);
      expect(state.isLoading, isTrue);
    });

    test('copyWith preserves fields', () {
      final state = RoutingState(
        status: RoutingStatus.routeActive,
        route: _defaultRoute,
        destinationLabel: 'Toyota',
        engineAvailable: true,
      );
      final updated = state.copyWith(engineAvailable: false);
      expect(updated.route, equals(_defaultRoute));
      expect(updated.destinationLabel, equals('Toyota'));
      expect(updated.engineAvailable, isFalse);
    });
  });

  group('RoutingEvent', () {
    test('events are equatable', () {
      expect(
        const RouteRequested(origin: _nagoya, destination: _toyota),
        equals(const RouteRequested(origin: _nagoya, destination: _toyota)),
      );
      expect(
        const RouteClearRequested(),
        equals(const RouteClearRequested()),
      );
    });
  });

  group('RoutingBloc — initial state', () {
    late MockRoutingEngine engine;

    setUp(() {
      engine = MockRoutingEngine();
    });

    test('initial state is idle', () {
      final bloc = RoutingBloc(engine: engine);
      expect(bloc.state, equals(const RoutingState.idle()));
      bloc.close();
    });
  });

  group('RoutingBloc — route lifecycle', () {
    late MockRoutingEngine engine;

    setUp(() {
      engine = MockRoutingEngine();
    });

    blocTest<RoutingBloc, RoutingState>(
      'idle → loading → routeActive on successful route request',
      build: () => RoutingBloc(engine: engine),
      act: (bloc) => bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
        destinationLabel: 'Toyota HQ',
      )),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.loading)
            .having((s) => s.destinationLabel, 'label', 'Toyota HQ'),
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.routeActive)
            .having((s) => s.route, 'route', _defaultRoute)
            .having((s) => s.destinationLabel, 'label', 'Toyota HQ'),
      ],
      verify: (_) {
        expect(engine.calculateCallCount, equals(1));
        expect(engine.lastRequest!.origin, equals(_nagoya));
        expect(engine.lastRequest!.destination, equals(_toyota));
      },
    );

    blocTest<RoutingBloc, RoutingState>(
      'idle → loading → error on engine failure',
      build: () {
        engine.shouldThrow = true;
        engine.throwMessage = 'Connection refused';
        return RoutingBloc(engine: engine);
      },
      act: (bloc) => bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
      )),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.loading),
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.error)
            .having((s) => s.errorMessage, 'error',
                contains('Connection refused')),
      ],
    );

    blocTest<RoutingBloc, RoutingState>(
      'routeActive → idle on clear',
      build: () => RoutingBloc(engine: engine),
      seed: () => RoutingState(
        status: RoutingStatus.routeActive,
        route: _defaultRoute,
        destinationLabel: 'Toyota',
        engineAvailable: true,
      ),
      act: (bloc) => bloc.add(const RouteClearRequested()),
      expect: () => [const RoutingState.idle(engineAvailable: true)],
    );

    blocTest<RoutingBloc, RoutingState>(
      'routeActive → loading → routeActive on new route (replaces)',
      build: () {
        engine.resultToReturn = _secondRoute;
        return RoutingBloc(engine: engine);
      },
      seed: () => RoutingState(
        status: RoutingStatus.routeActive,
        route: _defaultRoute,
        destinationLabel: 'Toyota',
        engineAvailable: true,
      ),
      act: (bloc) => bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _inuyama,
        destinationLabel: 'Inuyama Castle',
      )),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.loading)
            .having((s) => s.destinationLabel, 'label', 'Inuyama Castle'),
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.routeActive)
            .having((s) => s.route, 'route', _secondRoute),
      ],
    );

    blocTest<RoutingBloc, RoutingState>(
      'error → loading → routeActive on retry',
      build: () => RoutingBloc(engine: engine),
      seed: () => const RoutingState(
        status: RoutingStatus.error,
        errorMessage: 'previous error',
      ),
      act: (bloc) => bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
      )),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.loading),
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.routeActive),
      ],
    );

    blocTest<RoutingBloc, RoutingState>(
      'passes costing through to engine',
      build: () => RoutingBloc(engine: engine),
      act: (bloc) => bloc.add(const RouteRequested(
        origin: _nagoya,
        destination: _toyota,
        costing: 'bicycle',
      )),
      verify: (_) {
        expect(engine.lastRequest!.costing, equals('bicycle'));
      },
    );
  });

  group('RoutingBloc — engine availability check', () {
    late MockRoutingEngine engine;

    setUp(() {
      engine = MockRoutingEngine();
    });

    blocTest<RoutingBloc, RoutingState>(
      'updates engineAvailable on check (available)',
      build: () {
        engine.available = true;
        return RoutingBloc(engine: engine);
      },
      act: (bloc) => bloc.add(const RoutingEngineCheckRequested()),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.engineAvailable, 'available', isTrue),
      ],
    );

    blocTest<RoutingBloc, RoutingState>(
      'updates engineAvailable on check (unavailable)',
      build: () {
        engine.available = false;
        return RoutingBloc(engine: engine);
      },
      act: (bloc) => bloc.add(const RoutingEngineCheckRequested()),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.engineAvailable, 'available', isFalse),
      ],
    );

    blocTest<RoutingBloc, RoutingState>(
      'preserves route state during engine check',
      build: () {
        engine.available = true;
        return RoutingBloc(engine: engine);
      },
      seed: () => RoutingState(
        status: RoutingStatus.routeActive,
        route: _defaultRoute,
        destinationLabel: 'Toyota',
      ),
      act: (bloc) => bloc.add(const RoutingEngineCheckRequested()),
      expect: () => [
        isA<RoutingState>()
            .having((s) => s.status, 'status', RoutingStatus.routeActive)
            .having((s) => s.route, 'route', _defaultRoute)
            .having((s) => s.engineAvailable, 'available', isTrue),
      ],
    );
  });

  group('RoutingBloc — close', () {
    test('close disposes engine', () async {
      final engine = MockRoutingEngine();
      final bloc = RoutingBloc(engine: engine);
      await bloc.close();
      expect(engine.disposed, isTrue);
    });
  });
}
