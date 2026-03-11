# routing_engine

Engine-agnostic routing interface for Dart with OSRM and Valhalla implementations.

## Features

- **Abstract interface**: `RoutingEngine` defines `calculateRoute`, `isAvailable`, `info`, `dispose`
- **OSRM engine**: sub-frame latency (4.9ms for 10km), polyline5 decoding
- **Valhalla engine**: multi-modal routing, isochrone support, Japanese language
- **Engine identity**: `EngineInfo` reports name, version, and query latency
- **Build-time selection**: swap engines without code changes

## Usage

```dart
import 'package:routing_engine/routing_engine.dart';

// Create an engine
final engine = OsrmRoutingEngine(baseUrl: 'http://localhost:5000');

// Check availability
if (await engine.isAvailable()) {
  // Calculate a route
  final result = await engine.calculateRoute(RouteRequest(
    origin: LatLng(35.1709, 136.9066),   // Sakae Station
    destination: LatLng(34.9551, 137.1771), // Higashiokazaki Station
  ));

  print('${result.totalDistanceKm} km, ${result.maneuvers.length} turns');
  print('Engine: ${result.engineInfo.name} '
      '(${result.engineInfo.queryLatency.inMilliseconds}ms)');
}

// Clean up
await engine.dispose();
```

### Local Valhalla (canonical Machine E path)

```dart
final engine = ValhallaRoutingEngine.local();

if (await engine.isAvailable()) {
  final route = await engine.calculateRoute(const RouteRequest(
    origin: LatLng(35.1709, 136.9066),
    destination: LatLng(34.9551, 137.1771),
  ));

  print('Local Valhalla: ${route.engineInfo.queryLatency.inMilliseconds}ms');
}
```

`ValhallaRoutingEngine.local()` targets `http://localhost:8005`, which matches the canonical Machine E local runtime path proven in SNGNav. The plain `ValhallaRoutingEngine()` constructor still preserves the historical `http://localhost:8002` default for compatibility. Override `host`, `port`, `availabilityTimeout`, or `routeTimeout` when needed.

### Implement a custom engine

```dart
class MyRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(
    name: 'my-engine', version: '1.0.0',
    queryLatency: Duration(milliseconds: 10),
  );

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    // Your routing logic here
  }

  @override
  Future<void> dispose() async {}
}
```

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- `navigation_safety` — Flutter navigation safety state machine with pure Dart `_core` models (currently in the SNGNav monorepo)
- `map_viewport_bloc` — Flutter viewport state machine with pure Dart `_core` models (currently in the SNGNav monorepo)
- `routing_bloc` — Flutter route lifecycle state machine with pure Dart `_core` models (currently in the SNGNav monorepo)
- `offline_tiles` — Flutter offline tile manager with pure Dart `_core` models (currently in the SNGNav monorepo)

All nine extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## Local Integration Test

Run the real-network local Valhalla test only when a local server is up:

```bash
cd packages/routing_engine
RUN_LOCAL_VALHALLA_TEST=1 dart test test/valhalla_local_integration_test.dart
```

Optional override:

```bash
VALHALLA_BASE_URL=http://machine-e:8005 RUN_LOCAL_VALHALLA_TEST=1 dart test test/valhalla_local_integration_test.dart
```

## Benchmark Utility

Run the exact-payload Valhalla benchmark used for local/public latency comparison:

```bash
cd packages/routing_engine
dart run tool/valhalla_benchmark.dart
```

Optional environment overrides:

```bash
LOCAL_VALHALLA_BASE_URL=http://localhost:8005 \
PUBLIC_VALHALLA_BASE_URL=https://valhalla1.openstreetmap.de \
RUN_PUBLIC_VALHALLA_BENCHMARK=1 \
dart run tool/valhalla_benchmark.dart
```

## License

BSD-3-Clause — see [LICENSE](LICENSE).
