# ARM Deployment Guide

This guide moves SNGNav from the default x64 Linux desktop workflow to an arm64
Linux target such as Raspberry Pi 4 or Raspberry Pi 5.

The repo does not carry a custom ARM build system. The recommended path today
is a native build on the target device, then optional local routing services
through Docker. The same Dart entrypoints and `--dart-define` flags are used on
ARM as on x64.

## Scope

Validated target profile for this guide:

| Target | Recommendation |
|--------|----------------|
| Raspberry Pi 4 (4 GB) | Good for offline map demo and OSRM-backed routing |
| Raspberry Pi 5 (8 GB) | Preferred for full demo plus Valhalla tile builds |
| Other arm64 Linux SBCs | Viable if Flutter Linux desktop and GTK dependencies are available |

Use a 64-bit Linux image. Docker images for OSRM and Valhalla expect arm64,
and Flutter Linux desktop support is materially simpler on arm64 than on 32-bit
Pi images.

## 1. Prepare The Device

Install the same system packages used by the repo setup script.

```bash
sudo apt-get update
sudo apt-get install -y \
  clang \
  cmake \
  ninja-build \
  libgtk-3-dev \
  libsqlite3-dev \
  pkg-config \
  docker.io
```

Then verify Flutter on the device.

```bash
flutter config --enable-linux-desktop
flutter doctor
flutter --version
```

If `flutter doctor` reports missing Linux desktop support, resolve that before
moving forward. SNGNav uses the standard Flutter Linux embedder, not a custom
embedded shell.

## 2. Clone And Resolve Dependencies

```bash
git clone https://github.com/aki1770-del/SNGNav.git
cd SNGNav
flutter pub get
```

If you want the repo's full bring-up path, run the existing setup script:

```bash
./scripts/setup.sh
```

That script installs the same Debian and Ubuntu packages, runs `flutter pub
get`, analyzes the repo, executes tests, and builds the Linux release binary.

## 3. Start With The Smallest Successful Run

The safest first proof on ARM is the minimal offline map demo.

```bash
flutter run -d linux -t lib/main.dart
```

What this validates:

- Flutter Linux desktop is healthy on the target.
- GTK and SQLite native dependencies are present.
- The app can render a map surface.
- `offline_tiles` can load MBTiles if the archive is present.

If `data/offline_tiles.mbtiles` does not exist yet, the app falls back to
online OSM tiles rather than failing.

## 4. Run The Full Snow Scene On ARM

After the minimal demo works, move to the full application.

### Demo-Safe Offline Profile

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=ROUTING_ENGINE=mock \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles \
  --dart-define=DEAD_RECKONING=true \
  --dart-define=DR_MODE=kalman
```

This profile removes network and GPS dependency while keeping the complete UI
stack active.

### Real Routing Profile

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=WEATHER_PROVIDER=open_meteo \
  --dart-define=ROUTING_ENGINE=osrm
```

Use OSRM first on Raspberry Pi 4. Move to Valhalla when the device has enough
RAM and you need multi-modal routing or Japanese turn instructions.

## 5. Build A Release Binary

For a release bundle on the ARM target:

```bash
flutter build linux --release -t lib/snow_scene.dart
```

The output lands under:

```text
build/linux/arm64/release/bundle/
```

Some Flutter toolchains still emit `build/linux/x64/...` paths in script text
or local habits. On an ARM device, trust the actual build output directory that
Flutter creates on disk.

## 6. Add Offline Tiles

SNGNav's offline path expects an MBTiles archive at
`data/offline_tiles.mbtiles` by default.

Recommended sequence:

1. Prepare or copy the MBTiles file onto the device.
2. Place it under `data/offline_tiles.mbtiles`.
3. Start with `lib/main.dart` or the demo-safe profile above.
4. Watch the startup log for coverage warnings instead of hard failures.

If you store the file elsewhere, point the app at it explicitly:

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=/absolute/path/to/offline_tiles.mbtiles
```

## 7. Add Local Routing Services

For full offline routing, follow `docs/local_routing.md`. The short version:

| Engine | Pi 4 | Pi 5 | Recommendation |
|--------|:----:|:----:|----------------|
| OSRM | Good | Good | Primary choice for driving routes |
| Valhalla tile build | Slow | Good | Use when you need multi-modal routing |
| Valhalla server | Acceptable | Good | Better fit on 8 GB devices |

OSRM bring-up on ARM:

```bash
docker run -d --name osrm -p 5000:5000 \
  -v $(pwd)/data/routing:/data \
  ghcr.io/project-osrm/osrm-backend:latest \
  osrm-routed --algorithm mld /data/chubu-latest.osrm
```

Then point SNGNav at it:

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=ROUTING_ENGINE=osrm
```

For Valhalla, follow the full tile-build and server steps in
`docs/local_routing.md`.

## 8. Verification Checklist

Use this sequence when bringing up a new ARM target.

| Check | Expected result |
|-------|-----------------|
| `flutter doctor` | Linux desktop support available |
| `flutter run -d linux -t lib/main.dart` | Window opens and renders map |
| MBTiles enabled | Status changes to offline, or logs hybrid fallback warning |
| `flutter run -d linux -t lib/snow_scene.dart ...mock...` | Route enters `NAVIGATING` and weather phases advance |
| Local OSRM curl check | Route API returns `"code": "Ok"` |
| `flutter build linux --release -t lib/snow_scene.dart` | Release bundle created successfully |

## 9. Known Tradeoffs

| Topic | Current position |
|-------|------------------|
| Build model | Native on-device build is the recommended path |
| Cross-compilation | Not documented or automated in this repo yet |
| Routing choice | OSRM is the safer default on Pi 4; Valhalla is heavier but richer |
| Demo profile | Simulated weather + simulated location + mock routing is the most reliable first-run path |

## 10. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `flutter run -d linux` fails before compile | Missing Linux desktop packages | Re-run the apt install step or `./scripts/setup.sh` |
| App opens but no offline tiles appear | MBTiles file missing or path mismatch | Check `MBTILES_PATH` and the file location |
| Routing requests fail | OSRM or Valhalla container not running | Verify with `curl` before launching SNGNav |
| Valhalla tile build is too slow | Underpowered device or low RAM | Prefer OSRM on Pi 4, or build tiles on Pi 5 |

## Next Reading

- For the code layout, read `docs/architecture.md`.
- For local routing engine setup, read `docs/local_routing.md`.
- For contribution flow, read `CONTRIBUTING.md`.
