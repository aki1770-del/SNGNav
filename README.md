# sngnav

[![CI](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml/badge.svg)](https://github.com/aki1770-del/SNGNav/actions/workflows/ci.yml)

**Snow Guard Navigation** — offline-first navigation for Flutter on embedded Linux.

Navigation that doesn't abandon you when conditions fail unexpectedly.

```
Status:   v0.4.0
Tests:    App suite + extracted package suites
Platform: Linux desktop (Flutter 3.41.4)
Safety:   ASIL-QM (display-only, no vehicle control) — see SAFETY.md
Ecosystem: 10 SNGNav packages
```

## Why "Snow Guard"?

SNG stands for **Snow Guard** — navigation that guards the driver when conditions fail unexpectedly.

> **[The SNGNav Way](SNGNAV_WAY.md)** — what we build, the five principles,
> and where it goes next.

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

## Why This Architecture?

The navigation industry is converging on cloud-powered 3D visualization — AI
models rendering vivid driving scenes from server-side imagery. The results are
impressive in good conditions. In degraded conditions — tunnels, rural dead
zones, unexpected weather that kills connectivity — cloud-dependent navigation
disappears at the moment the driver needs it most.

SNGNav takes the opposite approach:

| Aspect | Cloud-first navigation | SNGNav |
|--------|----------------------|--------|
| Processing | Server-side AI rendering | On-device, embedded Linux |
| Connectivity | Required for full experience | Works fully offline |
| Data model | Proprietary, platform-locked | Open-source, BSD-3-Clause |
| Driver data | Platform-controlled collection | Consent-first, deny-by-default |
| Extensibility | Closed API, vendor decides features | 4 provider interfaces, 10 packages, pub.dev |
| Weather awareness | Not a design concern | Origin story — built for unexpected snow |
| Safety boundary | Rich visuals during driving | Display-only, ASIL-QM, advisory alerts |

This is not a competition with commercial navigation services. It is architecture
for the conditions they do not serve: **offline, degraded, extreme.** The driver
in a snowstorm with no cell signal is our customer's customer. The edge developer
building for that driver is our customer.

---

## Quick Start

```bash
# Prerequisites
sudo apt install clang cmake ninja-build libgtk-3-dev libsqlite3-dev pkg-config

# Build and run
flutter pub get
flutter run -d linux -t lib/snow_scene.dart
```

For the automated path, run `./scripts/setup.sh`. It installs the same Linux
packages and requires interactive `sudo` access for Step 1.

First run shows a simulated drive from Sakae Station to Higashiokazaki Station
with real weather from Open-Meteo. No API keys required.

**Clone-to-render target**: < 15 minutes on fresh Ubuntu 24.04.

## Running The Demo

Use this launch profile for the full Sprint 56 snow-scene demo:

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

This profile uses the scripted weather progression, the simulated vehicle trace,
the mock route, and MBTiles-first rendering with online fallback when coverage
is incomplete.

### Demo Flow

1. Launch the app and wait for the route to auto-fit after startup.
2. Confirm the app bar status chip moves from `IDLE` to `NAVIGATING`.
3. Watch the top bars progress from `Clear — City Departure` into the snow
   phases as the simulated drive approaches the mountain pass.
4. Let the maneuver timer advance automatically every 8 seconds, or pause it
   when you want to hold on a specific state.
5. Observe the weather polygon tighten around the active route corridor instead
   of drawing a static rectangle.
6. When heavy snow or ice risk appears, confirm the safety overlay fires above
   the map instead of being hidden behind navigation UI.

### UI Controls And Signals

| Surface | What to watch |
|---------|---------------|
| App bar `Fit route` button | Re-applies overview framing for the active route |
| App bar pause/play button | Pauses or resumes the 8-second maneuver auto-advance loop |
| App bar navigation chip | Shows `IDLE`, `NAVIGATING`, `DEVIATED`, or `ARRIVED` |
| Weather status bar | Shows precipitation, temperature, visibility, staleness, and `HAZARD` or `ICE` badges |
| Scenario phase indicator | Names the scripted phase, such as `Heavy Snow — Pass Summit` |
| Route progress card | Shows current maneuver instruction, leg distance, ETA, total distance, and progress bar |
| Speed display | Shows km/h with a GPS-quality dot underneath |
| Consent gate | `Fleet: OFF` by default; tap to switch to `Fleet: ON` and reveal fleet-fed hazards |

### Expected Demo Outcomes

- The route line stays visible with maneuver markers across the full trip.
- The snow-zone polygon follows the route geometry and concentrates on the
  mountain-pass portion when snow is active.
- If the MBTiles file does not fully cover the route corridor, the app logs a
  startup warning and continues with hybrid online fallback instead of failing.
- Hazardous weather raises the safety overlay above the map and route progress
  UI.
- Granting fleet consent enables fleet markers and fleet-derived hazard zones;
  leaving consent denied keeps those surfaces hidden.

### Screenshot Capture

Screenshot targets and filenames are tracked in
[`docs/screenshots/README.md`](docs/screenshots/README.md).

### Demo Evidence

Captured demo evidence files:

- `docs/screenshots/route-overview.png`
- `docs/screenshots/snow-zone-active.png`
- `docs/screenshots/safety-alert.png`

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

The root app suite validates the integrated desktop experience. Extracted
packages also carry their own package-local test suites under `packages/` and
should be run from the package directory when you change those domains.

Typical workflow:

```bash
# App-level widgets, blocs, integration
flutter test

# Example package-level validation
cd packages/offline_tiles && flutter test
cd packages/routing_engine && dart test
```

Coverage areas in the workspace include:

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
| Package suites | — | — | Extracted package validation for routing, tiles, weather, consent, safety, viewport, fleet hazard, and driving conditions |

Probe tests (GeoClue2, OSRM, Open-Meteo) are excluded in CI via `--exclude-tags=probe`.
When README statistics drift, treat the live test run as authoritative.

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

This is a **display-only navigation aid** classified ASIL-QM under ISO 26262.

- **No vehicle control**: no steering, braking, throttle, or ADAS commands.
- **Advisory alerts only**: weather warnings and hazard zones inform the
  driver — they do not override driver judgment.
- **No AI-generated imagery**: all visual output is deterministic (tile
  rendering, route geometry, declared weather data). No generative model
  produces or modifies what the driver sees.
- **Consent by default**: fleet data sharing is deny-by-default,
  per-purpose, and revocable.
- **Graceful degradation**: loss of any single data source never produces a
  blank screen or misleading output.

The architecture aligns with emerging transport safety regulations
(EU AI Act, UNECE WP.29) through design, not retrofit. See
[SAFETY.md](SAFETY.md) for the full safety model, regulatory awareness
context, and compliance-by-design mapping.

## API Documentation

Generate dartdoc for the full API reference:

```bash
dart doc
```

Output: `doc/api/index.html`. Key entry points:

- **`ProviderConfig`** — configuration system (7 `--dart-define` flags)
- **`KalmanFilter`** — 4D EKF for tunnel dead reckoning
- **`DeadReckoningProvider`** — decorator wrapping any `LocationProvider`
- **`OsrmRoutingEngine`** / **`ValhallaRoutingEngine`** — routing engines
- **`LocationBloc`**, **`WeatherBloc`**, **`RoutingBloc`** — BLoC state machines

## Dependencies

The app depends on the 10-package SNGNav ecosystem plus a small set of Flutter
and runtime libraries with permissive licenses. See `pubspec.yaml` for the
complete list.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for how to add new providers and submit changes.

For AI coding agents, see [.github/copilot-instructions.md](.github/copilot-instructions.md).

## License

Code: Same license as the parent project.
Map data: OpenStreetMap contributors (ODbL-1.0).

---

*Validated on Machine D: Ubuntu 24.04, Flutter 3.41.4, kernel 6.19.3-1-t2-noble.*
*Build: `flutter build linux --release` succeeds. Run `flutter test` from the repo root plus affected package suites under `packages/` for current validation.*
