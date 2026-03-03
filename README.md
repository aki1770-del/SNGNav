# sngnav

**Snow Guard Navigation** — offline-first navigation for Flutter on embedded Linux.

Navigation that doesn't abandon you when conditions fail unexpectedly.

```
Status:   v0.3.1
Tests:    926 pass (868 app + 24 kalman_dr + 34 routing_engine)
Platform: Linux desktop (Flutter 3.41.1)
Safety:   ASIL-QM (display-only, no vehicle control) — see SAFETY.md
Packages: kalman_dr, routing_engine
```

## Why "Snow Guard"?

SNG stands for **Snow Guard** — navigation that guards the driver when conditions fail unexpectedly.

A driver leaves Nagoya at 6 AM. Clear skies. By 7:15 she's on a mountain pass and the sky turns white. GPS dies in a tunnel. The network dropped two kilometers back. She didn't expect any of this.

SNGNav exists for that moment. Every feature is a guardian against a different unexpected failure:

| Guardian | Protects Against |
|----------|-----------------|
| Dead reckoning | GPS loss (tunnel, canyon, interference) |
| Offline tiles | Network failure (rural, congestion) |
| Local routing | Cloud unavailability (no signal) |
| Kalman filter | Sensor degradation (cold, old hardware) |
| Config system | Target variation (different deployments) |

Five guardians. Five failure modes. No single component's failure abandons the driver.

---

## Quick Start

```bash
# Prerequisites
sudo apt install clang cmake ninja-build libgtk-3-dev

# Build and run
flutter pub get
flutter run -d linux -t lib/snow_scene.dart
```

First run shows a simulated drive from Sakae Station to Higashiokazaki Station
with real weather from Open-Meteo. No API keys required.

**Clone-to-render target**: < 15 minutes on fresh Ubuntu 24.04.

## What You See

A navigation display with three layers:

| Layer | Z | Content |
|-------|:-:|---------|
| Map | 0 | OSM tiles (online or offline MBTiles), route polyline, fleet markers, weather zones |
| Navigation | 1 | Weather bar, speed, maneuver instructions, route progress, consent gate |
| Safety | 2 | Always-on overlay — modal alerts for ice risk, heavy snow, GPS loss |

The safety overlay follows five rules: always rendered, always on top,
passthrough when inactive, modal when active, independent state.

---

## Configuration

All behavior is controlled via `--dart-define` flags. No code changes needed.

| Flag | Default | Options |
|------|---------|---------|
| `WEATHER_PROVIDER` | `open_meteo` | `simulated`, `open_meteo` |
| `LOCATION_PROVIDER` | `simulated` | `simulated`, `geoclue` |
| `DEAD_RECKONING` | `true` | `true`, `false` |
| `DR_MODE` | `kalman` | `kalman`, `linear` |
| `ROUTING_ENGINE` | `mock` | `mock`, `osrm`, `valhalla` |
| `TILE_SOURCE` | `online` | `online`, `mbtiles` |
| `MBTILES_PATH` | `data/offline_tiles.mbtiles` | any path |

### Example Runs

```bash
# Demo weather scenario (6-phase snow progression)
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated

# Real GPS via GeoClue2 D-Bus
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=LOCATION_PROVIDER=geoclue

# Valhalla routing with linear dead reckoning
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=ROUTING_ENGINE=valhalla \
  --dart-define=DR_MODE=linear

# Fully offline (MBTiles + simulated everything)
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=WEATHER_PROVIDER=simulated

# Minimal offline map demo (no BLoCs, no routing)
flutter run -d linux -t lib/main.dart
```

---

## Platform

Designed for Flutter on embedded Linux. Targets compositors like
[ivi-homescreen](https://github.com/toyota-connected/ivi-homescreen).

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│ Widgets (Z-layered)                             │
│  SafetyOverlay > NavigationOverlay > MapLayer   │
└──────────────────┬──────────────────────────────┘
                   │ BlocBuilder / BlocListener
┌──────────────────┴──────────────────────────────┐
│ BLoCs (7)                                       │
│  Location · Weather · Routing · Navigation      │
│  Map · Consent · Fleet                          │
└──────────────────┬──────────────────────────────┘
                   │ constructor injection
┌──────────────────┴──────────────────────────────┐
│ Providers (abstract interfaces)                 │
│  LocationProvider · WeatherProvider             │
│  RoutingEngine · ConsentService                 │
└──────────────────┬──────────────────────────────┘
                   │ ProviderConfig.fromEnvironment()
┌──────────────────┴──────────────────────────────┐
│ --dart-define flags (7)                         │
└─────────────────────────────────────────────────┘
```

**Key design decisions**:
- BLoCs never reference each other directly — all coupling is widget-mediated
- Provider interfaces allow swapping implementations without touching BLoC logic
- Dead reckoning wraps any LocationProvider (decorator pattern)
- Consent is deny-by-default, per-purpose, revocable, SQLite-backed

### Directory Layout

```
lib/
├── bloc/        7 BLoCs (location, weather, routing, navigation, map, consent, fleet)
├── config/      ProviderConfig — reads --dart-define flags, creates providers
├── models/      GeoPosition, WeatherCondition, RouteResult, KalmanFilter, etc.
├── providers/   Abstract interfaces + simulated/real implementations
├── services/    ConsentService (SQLite), HazardAggregator
├── widgets/     Z-layered UI (MapLayer, SafetyOverlay, WeatherStatusBar, etc.)
├── fluorite/    FluoriteView scaffold (3D renderer integration point)
├── main.dart    Minimal offline map demo
└── snow_scene.dart  Full application entrypoint
```

---

## Testing

```bash
flutter test
```

926 tests across 50 test files (868 app + 24 kalman_dr + 34 routing_engine):

| Category | Files | Tests | Coverage |
|----------|:-----:|:-----:|----------|
| BLoC | 9 | — | All 7 BLoCs, state transitions, event handling |
| Widget | 12 | — | Golden tests (8), safety overlay rules, weather bar staleness |
| Provider | 8 | — | Simulated + real provider contracts, dead reckoning accuracy |
| Model | 2 | — | Edge cases, Kalman filter convergence |
| Integration | 4 | — | Weather-to-safety bridge, fleet-to-safety bridge, negative safety |
| Service | 3 | — | SQLite consent, in-memory consent, hazard aggregation |
| Config | 4 | 29 | All 7 flags, 10 documented combos, mutual exclusion invariants |
| Entrypoint | 1 | 5 | main.dart widget pump, snow_scene.dart import graph |
| Probe | 3 | 6 | GeoClue2, OSRM, Open-Meteo (skipped without service) |
| kalman_dr | 2 | 24 | Standalone package: EKF convergence, DR state extrapolation |
| routing_engine | 2 | 34 | OSRM/Valhalla parsing, interface contract (21 tests), cross-engine consistency |

Probe tests (GeoClue2, OSRM, Open-Meteo) are excluded in CI via `--exclude-tags=probe`.
0 flaky tests (verified by 3 consecutive runs).

---

## Offline Tiles

The app falls back to online OSM tiles if no MBTiles file is found.
To generate your own offline tiles:

```bash
sudo apt install tilemaker
wget https://download.geofabrik.de/asia/japan/chubu-latest.osm.pbf
tilemaker --input chubu-latest.osm.pbf \
          --output data/offline_tiles.mbtiles \
          --config resources/config-openmaptiles.json \
          --process resources/process-openmaptiles.lua
```

Pre-built Chubu tiles: 28.3 MB, zoom 10-14.

## Safety

This is a **display-only navigation aid** classified ASIL-QM.
It does not control the vehicle. Dead reckoning positions are estimates.
Safety alerts are advisory. See [SAFETY.md](SAFETY.md) for the full safety model.

## Dependencies

11 packages, all permissive licenses (BSD-3, MIT, Apache-2.0).
See `pubspec.yaml` for the complete list.

## License

Code: Same license as the parent project.
Map data: OpenStreetMap contributors (ODbL-1.0).

---

*Validated on Machine D: Ubuntu 24.04, Flutter 3.41.1, kernel 6.19.3-1-t2-noble.*
*Build: `flutter build linux --release` succeeds. Tests: 926 total (868+24+34), 3 expected failures, 0 flaky.*
