# map_viewport_bloc

Declarative viewport state machine for driver-assisting navigation maps.

`map_viewport_bloc` standardizes camera behavior, layer visibility, and route
overview transitions so edge developers can plug a renderer into a stable
contract instead of rebuilding viewport rules from scratch.

## Features

- `MapBloc` with three camera modes: `follow`, `freeLook`, `overview`.
- Six-layer composition contract: base tile, route, fleet, hazard, weather,
  safety.
- Pure Dart `_core` exports for `CameraMode`, `MapLayerType`, and `MapLayerZ`.
- Free-look auto-return timer with a default 10 second idle threshold.
- Safety-compatible follow override path for alert-driven recentering.

## Install

```yaml
dependencies:
  map_viewport_bloc: ^0.1.0
```

## Quick Start

```dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';
import 'package:map_viewport_bloc/map_viewport_bloc.dart';

class MapViewportExample extends StatelessWidget {
  const MapViewportExample({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => MapBloc()
        ..add(const MapInitialized(
          center: LatLng(35.1709, 136.8815),
          zoom: 15,
        )),
      child: BlocBuilder<MapBloc, MapState>(
        builder: (context, state) {
          return Text(
            'Camera: ${state.cameraMode.name} | '
            'Layers: ${state.visibleLayers.map((layer) => layer.name).join(', ')}',
          );
        },
      ),
    );
  }
}
```

## Camera Modes

| Mode | Purpose | Trigger | Auto-return |
|------|---------|---------|-------------|
| `follow` | Keeps the driver centered during active guidance | Startup, return button, safety override | — |
| `freeLook` | Gives the user direct viewport control | User pan or pinch gesture | After 10 seconds idle by default |
| `overview` | Fits the route into frame | Route preview or fit-to-bounds request | Ends on user pan or explicit follow |

## Z-Layer Contract

| Z | Layer | Type | Visibility rule |
|:-:|-------|------|-----------------|
| 0 | Base tile | Raster | Always on |
| 1 | Route | Vector | Toggleable |
| 2 | Fleet | Icons | Toggleable |
| 3 | Hazard | Filled polygon / clusters | Toggleable |
| 4 | Weather | Semi-transparent overlay | Toggleable |
| 5 | Safety | Full-screen alert plane | Not user-toggleable |

User toggles are intentionally restricted to Z1 through Z4. Z0 is foundational
and Z5 is safety-critical.

## KSF Summary

| KSF | Package behavior |
|-----|------------------|
| KSF-1 | Camera modes remain explicit and testable instead of hiding behind booleans |
| KSF-2 | Layer composition uses a canonical six-layer Z-order |
| KSF-3 | Renderer work stays outside the bloc so the state machine remains lightweight |
| KSF-4 | Free-look and overview transitions can be restored or replayed deterministically |
| KSF-5 | Edge developers can swap renderers while preserving safety-critical viewport rules |

## Pure Dart Core

Use the `_core` barrel when you only need model access.

```dart
import 'package:map_viewport_bloc/map_viewport_bloc_core.dart';

final weatherZ = MapLayerType.weather.zIndex;
final safetyToggleable = MapLayerType.safety.isUserToggleable;
```

## Example

The included example app shows camera mode buttons, user-toggleable layers,
and live state updates without requiring a specific renderer.

```bash
flutter run -d linux -t example/lib/main.dart
```

## See Also

- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine and safety overlay
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine and progress UI
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Flutter offline tile manager with MBTiles fallback
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing backend abstraction
- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation

All ten extracted packages are part of [SNGNav](https://github.com/aki1770-del/SNGNav), a driver-assisting navigation reference product.

## License

BSD-3-Clause — see [LICENSE](LICENSE).