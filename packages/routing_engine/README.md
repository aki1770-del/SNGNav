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
    origin: LatLng(35.1709, 136.8815),   // Nagoya
    destination: LatLng(34.9551, 137.1771), // Okazaki
  ));

  print('${result.totalDistanceKm} km, ${result.maneuvers.length} turns');
  print('Engine: ${result.engineInfo.name} '
      '(${result.engineInfo.queryLatency.inMilliseconds}ms)');
}

// Clean up
await engine.dispose();
```

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

## License

BSD-3-Clause — see [LICENSE](LICENSE).
