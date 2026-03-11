# routing_bloc

Engine-agnostic route lifecycle state machine and glanceable route progress UI
for driver-assisting navigation applications.

`routing_bloc` manages route request, loading, active-route, and error state
while keeping route guidance small enough to read quickly. It depends on
`routing_engine` for backend routing and does not require a specific engine
implementation.

## Features

- `RoutingBloc` for the 4-state route lifecycle: idle, loading, routeActive,
  error.
- `RouteProgressBar` for glanceable route guidance UI.
- `ManeuverIcons` for engine-agnostic maneuver icon mapping.
- Pure Dart `_core` exports for `RoutingStatus`, `RoutingState`, and
  `RouteProgressStatus`.
- Reusable README/example posture for edge developers.

## Install

```yaml
dependencies:
  routing_bloc: ^0.1.0
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

## API

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

## See Also

- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing backend abstraction
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine and safety overlay
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport and layer composition state machine
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with MBTiles fallback
- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation

All ten extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause — see [LICENSE](LICENSE).