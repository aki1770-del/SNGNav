# offline_tiles

[![pub package](https://img.shields.io/pub/v/offline_tiles.svg)](https://pub.dev/packages/offline_tiles)
[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

**Your map goes blank when the network drops.** offline_tiles keeps the map
rendering with MBTiles-backed local fallback — pre-cache routes and regions,
resolve tiles locally when offline.

Use `offline_tiles` when your map must keep rendering through connectivity loss.
Separates what to cache (coverage tiers) from how tiles resolve at runtime.

## Features

- `OfflineTileManager` with `cacheRoute()`, `cacheRegion()`, and `tileProvider`
- runtime tile resolution order: RAM cache -> MBTiles -> lower-zoom fallback -> online -> placeholder
- pure Dart `_core` models for `TileSourceType`, `CoverageTier`, and `TileCacheConfig`
- generated MBTiles-friendly workflow for offline-first Flutter maps

## Install

```yaml
dependencies:
  offline_tiles: ^0.4.0
```

## Quick Start

```dart
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:offline_tiles/offline_tiles.dart';

final manager = OfflineTileManager(
  tileSource: TileSourceType.mbtiles,
  mbtilesPath: 'data/offline_tiles.mbtiles',
);

await manager.cacheRoute(
  routeShape: const [
    LatLng(35.1709, 136.9066),
    LatLng(34.9554, 137.1791),
  ],
);

final tileLayer = TileLayer(
  tileProvider: manager.tileProvider,
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  userAgentPackageName: 'com.example.app',
);
```

## API Overview

| API | Purpose |
|-----|---------|
| `cacheRoute()` | Register and optionally materialize T1 corridor caching |
| `cacheRegion()` | Register and optionally materialize T2-T4 bounded caching |
| `tileProvider` | Resolver-backed provider for `flutter_map` |

## Coverage Tiers

| Tier | Meaning | Default expiry | Default zooms |
|------|---------|----------------|---------------|
| `T1 corridor` | Active route corridor with 5 km buffer | 30 days | Z10-Z16 |
| `T2 metro` | User-initiated metro area cache | 90 days | Z9-Z15 |
| `T3 prefecture` | User-initiated prefecture cache | 90 days | Z7-Z13 |
| `T4 national` | User-initiated national overview cache | 90 days | Z5-Z10 |

## Runtime Resolution Order

The runtime resolver is intentionally separate from the coverage tiers.

`RAM cache -> MBTiles -> lower-zoom fallback -> online -> placeholder`

This means runtime lookup does **not** try `T1`, then `T2`, then `T3`. It asks
for the best local tile available for the requested coordinate and zoom,
regardless of which coverage tier originally populated that tile.

## Flags and Truthfulness

- `TILE_SOURCE=online` means the app should prefer online raster tiles.
- `TILE_SOURCE=mbtiles` means the app should prefer MBTiles if available.
- `MBTILES_PATH` must point to a real file for local lookup to succeed.
- Missing or unreadable MBTiles archives degrade to online or placeholder,
  depending on manager configuration.

## Example

Run the package example:

```bash
flutter run -d linux -t example/lib/main.dart
```

The example shows:

- online/offline mode toggle
- current viewport caching plan
- runtime status when no MBTiles archive is present

## Works With

| Package | How |
|---------|-----|
| [flutter_map](https://pub.dev/packages/flutter_map) | `manager.tileProvider` plugs directly into flutter_map's TileLayer |
| [routing_engine](https://pub.dev/packages/routing_engine) | Cache tiles along a calculated route with `cacheRoute()` |
| [latlong2](https://pub.dev/packages/latlong2) | Shared coordinate types for route shapes |

## See Also

- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Viewport state machine for navigation maps
- [routing_bloc](https://pub.dev/packages/routing_bloc) — Route lifecycle state machine
- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss

Part of [SNGNav](https://github.com/aki1770-del/SNGNav) — 11 packages for
offline-first navigation on Flutter.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
