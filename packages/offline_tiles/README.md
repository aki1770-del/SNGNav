# offline_tiles

Offline tile management for Flutter navigation maps with MBTiles-backed local
fallback.

`offline_tiles` separates two concerns that are often mixed together:

- coverage tiers: what to pre-download
- runtime resolution: how a single tile request is resolved while rendering

## When to use this package

Use `offline_tiles` when your map must keep rendering through connectivity loss
and you need explicit control over what gets cached versus how lookups resolve.

## Features

- `OfflineTileManager` with `cacheRoute()`, `cacheRegion()`, and `tileProvider`
- runtime tile resolution order: RAM cache -> MBTiles -> lower-zoom fallback -> online -> placeholder
- pure Dart `_core` models for `TileSourceType`, `CoverageTier`, and `TileCacheConfig`
- generated MBTiles-friendly workflow for offline-first Flutter maps

## Install

```yaml
dependencies:
  offline_tiles: ^0.1.1
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

## See Also

- [routing_bloc](https://pub.dev/packages/routing_bloc) — Flutter route lifecycle state machine and progress UI
- [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc) — Flutter viewport and layer composition state machine
- [navigation_safety](https://pub.dev/packages/navigation_safety) — Flutter navigation safety state machine and safety overlay
- [routing_engine](https://pub.dev/packages/routing_engine) — Engine-agnostic routing backend abstraction
- [kalman_dr](https://pub.dev/packages/kalman_dr) — Dead reckoning through GPS loss (tunnels, urban canyons)
- [driving_weather](https://pub.dev/packages/driving_weather) — Weather condition model for driving (snow, ice, visibility)
- [driving_consent](https://pub.dev/packages/driving_consent) — Privacy consent with Jidoka semantics (UNKNOWN = DENIED)
- [fleet_hazard](https://pub.dev/packages/fleet_hazard) — Fleet telemetry hazard model and geographic clustering
- [driving_conditions](https://pub.dev/packages/driving_conditions) — Pure Dart computation models for road surface, visibility, and safety score simulation

## Part of SNGNav

`offline_tiles` is one of the 10 packages in
[SNGNav](https://github.com/aki1770-del/SNGNav), an offline-first,
driver-assisting navigation reference product for embedded Linux.

## License

BSD-3-Clause — see [LICENSE](LICENSE).
