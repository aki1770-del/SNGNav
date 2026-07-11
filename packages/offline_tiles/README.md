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
  offline_tiles: ^0.5.3
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

## Android consumers: the SQLite native-library trap (read before shipping offline)

MBTiles reading rides `package:sqlite3`, which needs a native `libsqlite3.so`
on the device. On Flutter Android that library is NOT guaranteed to be
present:

- `sqlite3_flutter_libs` `0.6.0+eol` is a deprecated **no-op** — depending on
  it ships nothing. Pin the `0.5.x` line (e.g. `sqlite3_flutter_libs:
  ^0.5.42`, which is also 16 KB-page-size aligned) until you have verified a
  `package:sqlite3` build-hooks-delivered library on a real device.
- **The failure is silent and offline-shaped**: without the `.so`, opening
  the MBTiles archive throws, a broad `catch` degrades to the online tile
  path, and every host-side test still passes — the blank map appears only
  on a device in airplane mode. (Found in production integration testing,
  2026-07-10: the offline basemap had never actually rendered on Android
  while 220 host tests painted it.)
- Verification that counts: install a release build on a device/emulator,
  enable airplane mode BEFORE launch, and SEE the bundled region paint.
  Log MBTiles open-failures loudly instead of swallowing them.

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
