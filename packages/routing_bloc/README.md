# routing_bloc

[![pub package](https://img.shields.io/pub/v/routing_bloc.svg)](https://pub.dev/packages/routing_bloc)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Route lifecycle in four states: idle, loading, active, error.** Clean
state machine for route requests with a glanceable progress UI — works with
any routing backend.

Use `routing_bloc` when you want route lifecycle state and a progress bar
widget without coupling your screens to OSRM, Valhalla, or any specific
routing engine.

## Features

- `RoutingBloc` for the 4-state route lifecycle: idle, loading, routeActive,
  error.
- `RouteProgressBar` for glanceable route guidance UI.
- `ManeuverIcons` for engine-agnostic maneuver icon mapping.
- Pure Dart `_core` exports for `RoutingStatus`, `RoutingState`, and
  `RouteProgressStatus`.
- Composable with `navigation_safety` and `voice_guidance` without coupling to either.

## Install

```yaml
dependencies:
  routing_bloc: ^0.3.0
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_bloc/routing_bloc.dart';
import 'package:routing_engine/routing_engine.dart';

class ExampleScreen extends StatelessWidget {
  const ExampleScreen({super.key, required this.engine});

  final RoutingEngine engine;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => RoutingBloc(engine: engine)
        ..add(const RoutingEngineCheckRequested())
        ..add(const RouteRequested(
          origin: LatLng(35.1709, 136.8815),
          destination: LatLng(35.0831, 137.1559),
          destinationLabel: 'Toyota City Hall',
        )),
      child: BlocBuilder<RoutingBloc, RoutingState>(
        builder: (context, state) {
          return RouteProgressBar(
            status: state.hasRoute
                ? RouteProgressStatus.active
                : RouteProgressStatus.idle,
            route: state.route,
            destinationLabel: state.destinationLabel,
          );
        },
      ),
    );
  }
}
```

## API Overview

| API | Purpose |
|-----|---------|
| `RoutingBloc` | Route request / clear / engine-check lifecycle |
| `RoutingState` | Current lifecycle state, route result, engine availability |
| `RoutingEvent` | Route request, clear, and engine-check inputs |
| `RouteProgressBar` | Glanceable route guidance presentation layer |
| `ManeuverIcons` | Maneuver type to Material icon mapping |
| `RouteProgressStatus` | Pure Dart display status for route progress UI |

## Routing State Machine

| State | Meaning | Trigger in |
|-------|---------|------------|
| `idle` | No route active | startup, clear |
| `loading` | Route calculation in progress | route request |
| `routeActive` | Route calculated successfully | engine success |
| `error` | Route calculation failed | engine exception |

## Glanceability Rule

The route progress widget exists to be read quickly while driving. Keep the
primary instruction first, distance and ETA second, and avoid turning the route
header into a dense control surface.

## Maneuver Icons

Representative mappings:

| Maneuver type | Icon |
|---------------|------|
| `depart` | `Icons.flag` |
| `arrive` | `Icons.sports_score` |
| `left`, `slight_left`, `sharp_left` | `Icons.turn_left` |
| `right`, `slight_right`, `sharp_right` | `Icons.turn_right` |
| `straight`, `continue` | `Icons.straight` |
| `merge` | `Icons.merge` |
| `ramp_right`, `ramp_left` | `Icons.ramp_right` |

## Pure Dart Core

Use the `_core` barrel when you only need route lifecycle models.

```dart
import 'package:routing_bloc/routing_bloc_core.dart';

const idle = RoutingState.idle();
const status = RouteProgressStatus.active;
```

## Example

The included example app demonstrates:

- a mock `RoutingEngine`
- engine availability check
- route request
- route clear
- active route UI
- error path

```bash
flutter run -d linux -t example/lib/main.dart
```

## Works With

| Package | How |
|---------|-----|
| [routing_engine](https://pub.dev/packages/routing_engine) | Backend abstraction — RoutingBloc wraps any RoutingEngine |
| [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) | Route layer renders at Z1 in the viewport stack |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Safety overlay responds to route state changes |

## See Also

- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Offline tile management with MBTiles
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition monitoring

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).