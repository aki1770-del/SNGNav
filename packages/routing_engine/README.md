# routing_engine

[![pub package](https://img.shields.io/pub/v/routing_engine.svg)](https://pub.dev/packages/routing_engine)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**One routing API, multiple backends.** Switch between OSRM, Valhalla, or your
own engine without rewriting app logic.

Use `routing_engine` when you need route calculation that works with a public
server today and a local server tomorrow — same code, same interface.

## Features

- **Abstract interface**: `RoutingEngine` defines `calculateRoute`, `isAvailable`, `info`, `dispose`
- **OSRM engine**: sub-frame latency (4.9ms for 10km), polyline5 decoding
- **Valhalla engine**: multi-modal routing, isochrone support, Japanese language
- **Engine identity**: `EngineInfo` reports name, version, and query latency
- **Build-time selection**: swap engines without code changes

## Install

```yaml
dependencies:
  routing_engine: ^0.3.0
  latlong2: ^0.9.1          # for LatLng coordinates
```

## Quick Start

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

### Local Valhalla

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

`ValhallaRoutingEngine.local()` targets `http://localhost:8005`. Override
`host`, `port`, `availabilityTimeout`, or `routeTimeout` when needed.

## Integration Pattern

In a Flutter app, `routing_engine` typically sits behind a button or bloc
event: choose the backend once, fetch the route asynchronously, then render the
summary and maneuver list. Keep the engine creation close to app start so you
can swap OSRM, Valhalla, or a local backend without touching the route screen.

```dart
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';

class RoutePreviewCard extends StatefulWidget {
  const RoutePreviewCard({super.key});

  @override
  State<RoutePreviewCard> createState() => _RoutePreviewCardState();
}

class _RoutePreviewCardState extends State<RoutePreviewCard> {
  late final RoutingEngine engine;
  Future<RouteResult>? pendingRoute;

  @override
  void initState() {
    super.initState();
    engine = ValhallaRoutingEngine.local();
    pendingRoute = engine.calculateRoute(const RouteRequest(
      origin: LatLng(35.1709, 136.9066),
      destination: LatLng(34.9551, 137.1771),
    ));
  }

  @override
  void dispose() {
    engine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<RouteResult>(
      future: pendingRoute,
      builder: (context, snapshot) {
        final route = snapshot.data;
        if (route == null) {
          return const Text('Calculating route...');
        }

        return Card(
          child: ListTile(
            title: Text(route.summary),
            subtitle: Text(
              '${route.totalDistanceKm.toStringAsFixed(1)} km, '
              '${route.maneuvers.length} maneuvers via '
              '${route.engineInfo.name}',
            ),
          ),
        );
      },
    );
  }
}
```

When you later adopt `routing_bloc`, keep this same seam: the bloc owns the
async lifecycle, `routing_engine` stays the backend abstraction.

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

## API Overview

| Type | Purpose |
|------|---------|
| `RoutingEngine` | Abstract interface for route calculation, availability checks, and cleanup. |
| `RouteRequest` | Defines origin, destination, and optional waypoints for a route query. |
| `RouteResult` | Returns maneuvers, geometry, distance, duration, and engine metadata. |
| `EngineInfo` | Reports engine name, version, and observed query latency. |
| `OsrmRoutingEngine` / `ValhallaRoutingEngine` | Concrete implementations for OSRM and Valhalla backends. |

## Works With

| Package | How |
|---------|-----|
| [flutter_map](https://pub.dev/packages/flutter_map) | Render route geometry on the map |
| [kalman_dr](https://pub.dev/packages/kalman_dr) | Dead reckoning during GPS loss along the route |
| [latlong2](https://pub.dev/packages/latlong2) | Shared coordinate types (already a dependency) |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Route lifecycle state machine for Flutter
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Offline tile management with MBTiles

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

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
