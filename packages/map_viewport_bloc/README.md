# map_viewport_bloc

[![pub package](https://img.shields.io/pub/v/map_viewport_bloc.svg)](https://pub.dev/packages/map_viewport_bloc)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Camera follow, free look, route overview — without reinventing viewport
logic.** Declarative state machine for navigation map cameras and layer
composition.

Use `map_viewport_bloc` when you need stable camera rules (follow, free look,
overview) and a six-layer composition contract, but want freedom to choose your
own map renderer.

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
  map_viewport_bloc: ^0.3.0
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

## Design Principles

- Camera modes are explicit enum values, not boolean flags — testable by default.
- The Z-layer contract is fixed so safety (Z5) is never displaced by application code.
- The state machine owns no renderer code — swap `flutter_map`, Mapbox, or anything else without touching the bloc.
- Free-look and overview transitions are fully reversible and deterministic.

## Pure Dart Core

Use the `_core` barrel when you only need model access.

```dart
import 'package:map_viewport_bloc/map_viewport_bloc_core.dart';

final weatherZ = MapLayerType.weather.zIndex;
final safetyToggleable = MapLayerType.safety.isUserToggleable;
```

## API Overview

| Type | Purpose |
|------|---------|
| `MapBloc` | Viewport state machine for camera mode, bounds fitting, and layer visibility. |
| `MapState` | Current center, zoom, camera mode, visible layers, and fit-bounds state. |
| `MapEvent` | Inputs for initialization, camera changes, pans, bounds fitting, and layer toggles. |
| `CameraMode` | Canonical `follow`, `freeLook`, and `overview` camera states. |
| `MapLayerType` | Six-layer contract for route, fleet, hazard, weather, and safety rendering. |
| `MapLayerZ` | Stable Z-order constants for renderer integrations. |

## Example

The included example app shows camera mode buttons, user-toggleable layers,
and live state updates without requiring a specific renderer.

```bash
flutter run -d linux -t example/lib/main.dart
```

## Works With

| Package | How |
|---------|-----|
| [flutter_map](https://pub.dev/packages/flutter_map) | Drive flutter_map's camera from MapBloc state |
| [navigation_safety](https://pub.dev/packages/navigation_safety) | Safety overlay occupies Z5 — always on top, never user-toggleable |
| [offline_tiles](https://pub.dev/packages/offline_tiles) | Base tile layer (Z0) resolves through offline tile manager |

## See Also

- [routing_bloc](https://pub.dev/packages/routing_bloc) — Route lifecycle state machine
- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss
- [offline_tiles](https://pub.dev/packages/offline_tiles) — Offline tile management with MBTiles

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).