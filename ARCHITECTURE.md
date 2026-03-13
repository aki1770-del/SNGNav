# SNGNav Architecture Guide

Snow Guard Navigation — a reference navigation application for embedded Linux
IVI platforms. This guide explains how the system protects the driver when
conditions degrade: GPS lost in a tunnel, network down in a blizzard, routing
server unreachable. Every design decision traces back to one question:

> **How can we help the driver when conditions are worst?**

---

## The Five Guardians

SNGNav's name encodes its purpose: **S**now **G**uard **Nav**igation. The
"guard" comes from the Japanese concept of *kami* (神) — distributed natural
guardians (八百万の神). Five subsystems act as guardians, each protecting
against a specific failure mode. They compose — when one guardian activates,
the others continue working.

### Guardian 1: Dead Reckoning

**Protects against**: GPS signal loss (tunnels, urban canyons, blizzards).

When GPS is lost for 3 seconds, the dead reckoning provider begins predicting
position from the last known speed and heading. Two algorithms are available:

| Mode | Algorithm | Accuracy | Use case |
|------|-----------|----------|----------|
| `linear` | Constant velocity extrapolation | Degrades ~50m/min | Baseline, simple |
| `kalman` | 4D Extended Kalman Filter | Degrades ~20m/min | Advanced, covariance-aware |

The Kalman filter tracks `[latitude, longitude, speed, heading]` and maintains
a 4x4 covariance matrix. When GPS returns, the filter fuses the measurement
with the prediction — the driver sees a smooth transition, not a position jump.

**Safety cap**: if accuracy exceeds 500m, the stream stops emitting. The driver
sees "position unavailable" rather than a misleading estimate.

**How it composes**: dead reckoning wraps any `LocationProvider` using the
decorator pattern. The BLoC sees only `Stream<GeoPosition>` — it doesn't know
whether the position came from GPS or dead reckoning.

```dart
final gps = GeoClueLocationProvider();
final dr = DeadReckoningProvider(
  inner: gps,
  mode: DeadReckoningMode.kalman,
  gpsTimeout: Duration(seconds: 3),
);
// dr.positions emits GPS when available, DR predictions when not.
```

**Source**: [dead_reckoning_provider.dart](lib/providers/dead_reckoning_provider.dart),
[kalman_filter.dart](lib/models/kalman_filter.dart)

### Guardian 2: Offline Tiles

**Protects against**: network loss during navigation.

Map tiles are served from a local MBTiles file — a single SQLite database
containing pre-rendered tile images. When network is unavailable, the map
continues rendering from local data. The tile resolution strategy uses a
four-level fallback:

1. **RAM cache** (< 1ms) — recently viewed tiles
2. **Regional MBTiles** (< 5ms) — pre-loaded area tiles
3. **Overview MBTiles** (degraded zoom) — lower resolution fallback
4. **Placeholder tile** — grey tile with "offline" message

The map never goes blank.

**Configuration**: `--dart-define=TILE_SOURCE=mbtiles` with
`--dart-define=MBTILES_PATH=data/offline_tiles.mbtiles`.

### Guardian 3: Local Routing

**Protects against**: routing server unavailability.

Two routing engines are available — both can run locally via Docker containers,
eliminating cloud dependency:

| Engine | Strength | Latency | Memory |
|--------|----------|---------|--------|
| OSRM | Driving routes, fast recalculation | ~5ms | ~180MB |
| Valhalla | Multi-modal, Japanese kanji, isochrones | ~465ms | ~420MB |

Both implement the same `RoutingEngine` interface. The BLoC doesn't know which
engine is running.

```dart
abstract class RoutingEngine {
  Future<RouteResult> calculateRoute(RouteRequest request);
  Future<bool> isAvailable();
  Future<void> dispose();
}
```

**Decision tree**: OSRM for driving queries (95-133x faster). Valhalla for
bicycle/pedestrian, isochrones, or when Japanese turn-by-turn instructions
are needed. If OSRM is unavailable, Valhalla serves as fallback.

**Source**: [routing_engine.dart](lib/providers/routing_engine.dart),
[osrm_routing_engine.dart](lib/providers/osrm_routing_engine.dart),
[valhalla_routing_engine.dart](lib/providers/valhalla_routing_engine.dart)

**Deployment**: See [docs/local_routing.md](docs/local_routing.md) for Docker
setup on desktop or Raspberry Pi.

### Guardian 4: Kalman Filter

**Protects against**: noisy GPS measurements and position jumps.

Even with GPS available, raw measurements are noisy — accuracy varies from 3m
to 50m depending on satellite geometry, atmospheric conditions, and multipath.
The Kalman filter smooths these measurements:

- **Predict step**: projects state forward using constant-velocity model (~15 microseconds)
- **Update step**: fuses prediction with GPS measurement using Kalman gain
- **Covariance**: honestly tracks uncertainty — `accuracyMetres` grows during
  prediction, shrinks on GPS update

The filter converges within ~10 GPS fixes to sub-4m accuracy.

This guardian works in tandem with Guardian 1 (dead reckoning). During GPS
availability, it smooths. During GPS loss, it predicts. Same filter, same
state vector, continuous operation.

**Source**: [kalman_filter.dart](lib/models/kalman_filter.dart)

### Guardian 5: Configuration System

**Protects against**: deployment rigidity — one binary must work in demo rooms,
development labs, test tracks, and production vehicles.

Seven compile-time flags select which implementations to use. No code changes
needed — the same codebase serves all environments:

| Flag | Values | Default | Purpose |
|------|--------|---------|---------|
| `WEATHER_PROVIDER` | `simulated`, `open_meteo` | `open_meteo` | Weather data source |
| `LOCATION_PROVIDER` | `simulated`, `geoclue` | `simulated` | GPS data source |
| `DEAD_RECKONING` | `true`, `false` | `true` | Enable/disable DR wrapper |
| `DR_MODE` | `kalman`, `linear` | `kalman` | Dead reckoning algorithm |
| `ROUTING_ENGINE` | `mock`, `osrm`, `valhalla` | `mock` | Routing backend |
| `TILE_SOURCE` | `online`, `mbtiles` | `online` | Map tile source |
| `MBTILES_PATH` | file path | `data/offline_tiles.mbtiles` | Offline tile location |

Example — fully offline demo (no network, no GPS):

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=simulated \
  --dart-define=TILE_SOURCE=mbtiles \
  --dart-define=MBTILES_PATH=data/offline_tiles.mbtiles
```

Example — real weather with Kalman dead reckoning:

```bash
flutter run -d linux -t lib/snow_scene.dart \
  --dart-define=WEATHER_PROVIDER=open_meteo \
  --dart-define=LOCATION_PROVIDER=simulated \
  --dart-define=DR_MODE=kalman \
  --dart-define=ROUTING_ENGINE=osrm
```

**Source**: [provider_config.dart](lib/config/provider_config.dart)

---

## Provider System

The provider system is SNGNav's core architectural pattern. BLoCs depend on
abstract interfaces, not implementations. Adding a new data source requires
no BLoC or widget changes.

### Data Flow

```
--dart-define flag  →  ProviderConfig  →  creates provider  →  injected into BLoC
```

### The Four Interfaces

| Interface | Stream type | Implementations |
|-----------|-------------|-----------------|
| `LocationProvider` | `Stream<GeoPosition>` | `SimulatedLocationProvider`, `GeoClueLocationProvider` |
| `WeatherProvider` | `Stream<WeatherCondition>` | `SimulatedWeatherProvider`, `OpenMeteoWeatherProvider` |
| `RoutingEngine` | `Future<RouteResult>` | `OsrmRoutingEngine`, `ValhallaRoutingEngine` |
| `FleetProvider` | `Stream<FleetReport>` | `SimulatedFleetProvider` |

Each interface defines `start`/`stop`/`dispose` lifecycle methods and a data
stream (or future for routing). Implementations handle their own error recovery.

### Offline Rule

When the upstream data source is unreachable, implementations re-emit the last
known value rather than letting the stream go silent. The driver sees
stale-but-present data, not a blank widget. See `OpenMeteoWeatherProvider` for
the reference implementation.

### Adding a New Provider

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete step-by-step guide.
The short version:

1. Implement the abstract interface in `lib/providers/`
2. Add an enum value and factory case in `lib/config/provider_config.dart`
3. Your provider is now selectable via `--dart-define`
4. Write tests in `test/providers/`

**Key principle**: if you find yourself editing a BLoC or widget to add a
provider, the interface needs extending — open an issue first.

---

## Decision Flow

### How the System Chooses: GPS vs Dead Reckoning

```
GPS position arrives
    │
    ├── Mode = linear
    │   └── Forward to stream, update last-known state, reset watchdog
    │
    └── Mode = kalman
        └── Feed into Kalman filter, emit filtered position, reset watchdog

GPS watchdog fires (3s timeout)
    │
    ├── Mode = linear
    │   └── Extrapolate from last speed + heading, accuracy degrades ~50m/min
    │
    └── Mode = kalman
        └── Predict from filter state, covariance grows, accuracy degrades ~20m/min

GPS returns
    └── Stop DR, resume GPS (Kalman: fuse measurement, smooth transition)

Accuracy exceeds 500m safety cap
    └── Stop DR, stream goes silent, driver sees "position unavailable"
```

The BLoC sees this as a quality state machine with five states:

| Quality | Meaning | Trigger |
|---------|---------|---------|
| `uninitialized` | Not started | Initial state |
| `acquiring` | Waiting for first fix | After `start()` |
| `fix` | GPS available, accuracy ≤ 50m | Position with `isNavigationGrade` |
| `stale` | No update for 10s | Stale timer fires |
| `error` | Provider error | Stream error |

### How the System Chooses: OSRM vs Valhalla

The choice is made at build time via `--dart-define=ROUTING_ENGINE=osrm` or
`valhalla`. The BLoC receives whichever engine was injected — it issues
`RouteRequested` events and receives `RouteResult` states identically
regardless of engine.

**When to use OSRM**: driving routes where speed matters. OSRM uses
Contraction Hierarchies for ~5ms response time.

**When to use Valhalla**: multi-modal routing (bicycle, pedestrian, truck),
Japanese turn-by-turn instructions with kanji, isochrone analysis, or when
OSRM is unavailable.

---

## Project Structure

```
lib/
├── bloc/        BLoCs (state machines — do NOT modify for new providers)
├── config/      ProviderConfig (edit here to register new providers)
├── models/      Data classes (GeoPosition, RouteResult, WeatherCondition)
├── providers/   Provider interfaces + implementations (add here)
├── services/    Consent, hazard aggregation
└── widgets/     UI layer (do NOT modify for new providers)

test/
├── bloc/        BLoC state transition tests
├── config/      Flag parsing, factory method tests
├── integration/ Cross-BLoC safety flow tests
├── models/      Data class edge case tests
├── providers/   Provider contract tests
├── benchmark/   Performance benchmarks
└── widgets/     Widget rendering + golden tests

packages/
├── driving_conditions/  Pure Dart road-surface + safety score models
├── driving_consent/     Privacy consent gate with Jidoka semantics
├── driving_weather/     Weather models + provider abstraction
├── fleet_hazard/        Fleet telemetry models + hazard aggregation
├── kalman_dr/           Dead reckoning + location provider contracts
├── map_viewport_bloc/   Declarative camera and viewport state
├── navigation_safety/   Safety-focused navigation session + overlay
├── offline_tiles/       MBTiles-backed offline tile management
├── routing_bloc/        Engine-agnostic route lifecycle BLoC
└── routing_engine/      OSRM + Valhalla routing interface
```

---

## Package Composition

The sections above explain the app from the driver's point of view. This
section explains it from the edge developer's point of view: which packages
exist, which ones depend on each other, and how they compose into one
navigation system.

### Package-At-A-Glance

| Package | Role | Depends on | pub.dev |
|---------|------|------------|---------|
| `driving_conditions` | Pure Dart road-surface assessment, precipitation tuning, visibility degradation, safety score simulation | `driving_weather`, `navigation_safety` | <https://pub.dev/packages/driving_conditions> |
| `driving_consent` | Three-state consent gate (`unknown`, `granted`, `denied`) with per-purpose records | — | <https://pub.dev/packages/driving_consent> |
| `driving_weather` | Weather models and provider interface | — | <https://pub.dev/packages/driving_weather> |
| `fleet_hazard` | Fleet reports, hazard zones, clustering, provider interface | — | <https://pub.dev/packages/fleet_hazard> |
| `kalman_dr` | Dead reckoning, `LocationProvider`, 4D Kalman filter | — | <https://pub.dev/packages/kalman_dr> |
| `map_viewport_bloc` | Map camera mode, center, zoom, fit-to-bounds state | — | <https://pub.dev/packages/map_viewport_bloc> |
| `navigation_safety` | Navigation session state, alert severity, safety overlay | `routing_engine` | <https://pub.dev/packages/navigation_safety> |
| `offline_tiles` | MBTiles manager, tile coverage queries, runtime resolver | — | <https://pub.dev/packages/offline_tiles> |
| `routing_bloc` | Route request lifecycle, progress, UI widgets | `routing_engine` | <https://pub.dev/packages/routing_bloc> |
| `routing_engine` | Engine-agnostic route API with OSRM and Valhalla adapters | — | <https://pub.dev/packages/routing_engine> |

### Dependency Graph

Compile-time package dependencies are intentionally shallow. Most composition
happens in the app layer through BLoCs and widget listeners, not by making
packages import each other indiscriminately.

```
driving_conditions
├── driving_weather
└── navigation_safety_core

navigation_safety
└── routing_engine

routing_bloc
└── routing_engine

Standalone packages:
- driving_consent
- fleet_hazard
- kalman_dr
- map_viewport_bloc
- offline_tiles
```

This is deliberate. The packages form a toolkit, and the app decides how to
compose them. That keeps each package reusable while letting the full SNGNav
experience combine them tightly.

### Composition Rules

1. Keep domain packages narrow. A package should own one responsibility and
   expose plain Dart models or a small BLoC surface.
2. Compose at the boundary. The app layer wires packages together with
   `MultiBlocProvider`, `BlocListener`, and provider injection.
3. Use integration tests as the truth source. Cross-package behavior is proven
   in `test/integration/` and package integration suites, not inferred from
   README claims.

### Pattern 1: Navigation Chain

Purpose: calculate a route once, then let navigation state and viewport state
react to that route consistently.

```
RouteRequest
  -> routing_engine
  -> RouteResult
  -> routing_bloc
  -> SnowSceneScaffold listener
  -> navigation_safety
  -> map_viewport_bloc
  -> widgets
```

Key types:
- `RouteRequest` / `RouteResult` from `routing_engine`
- `RoutingState` from `routing_bloc`
- `NavigationState` from `navigation_safety`
- `MapState` from `map_viewport_bloc`

Reference wiring:

```dart
BlocProvider(
  create: (_) => RoutingBloc(engine: routingEngine),
),
BlocProvider(
  create: (_) => NavigationBloc(),
),
BlocProvider(
  create: (_) => MapBloc(),
),

BlocListener<RoutingBloc, RoutingState>(
  listenWhen: (prev, curr) => !prev.hasRoute && curr.hasRoute,
  listener: (context, state) {
    final route = state.route!;
    context.read<NavigationBloc>().add(NavigationStarted(
      route: route,
      destinationLabel: state.destinationLabel,
    ));
    // The app also fits the viewport to the route shape here.
  },
  child: const SnowSceneScaffold(),
)
```

Sprint 60 evidence:
- `test/integration/snow_scene_demo_flow_test.dart` proves `RouteRequested`
  leads to route calculation, `NavigationStarted`, fit-to-route behavior, and
  maneuver advancement in one composed flow.

### Pattern 2: Hazard Pipeline

Purpose: turn weather and fleet signals into one coherent driver-facing alert
instead of competing warnings.

```
WeatherProvider -> driving_weather -> WeatherBloc ---
                                                   \ 
                                                    -> navigation_safety
                                                   / 
FleetProvider   -> fleet_hazard  -> FleetBloc  ----

Optional analysis layer:
driving_conditions -> reusable road-surface and safety score models
```

Key types:
- `WeatherCondition` from `driving_weather`
- `FleetReport` / `HazardZone` from `fleet_hazard`
- `AlertSeverity` / `NavigationState` from `navigation_safety`

`driving_conditions` stays pure Dart on purpose. It is the analysis layer an
edge developer can reuse to model road surface, visibility, and safety score
logic without pulling in Flutter widgets.

Reference wiring:

```dart
BlocListener<FleetBloc, FleetState>(
  listenWhen: (prev, curr) => !prev.hasHazards && curr.hasHazards,
  listener: (context, state) {
    final hasIcy = state.hazardReports.any(
      (report) => report.condition == RoadCondition.icy,
    );
    context.read<NavigationBloc>().add(SafetyAlertReceived(
      message: hasIcy
          ? 'Fleet reports: icy road conditions detected'
          : 'Fleet reports: snowy road conditions ahead',
      severity: hasIcy ? AlertSeverity.critical : AlertSeverity.warning,
    ));
  },
  child: const SnowSceneScaffold(),
)
```

Sprint 60 evidence:
- `test/integration/multi_hazard_priority_integration_test.dart` proves fleet
  critical alerts override weaker weather warnings and that later weather input
  does not downgrade an already-critical fleet alert.

### Pattern 3: Consent Gate

Purpose: stop fleet telemetry flow unless the driver has explicitly granted the
relevant consent purpose.

```
driving_consent
  -> ConsentRecord / ConsentService
  -> ConsentBloc
  -> SnowSceneScaffold listener
  -> FleetListenStarted / FleetListenStopped
  -> fleet_hazard provider lifecycle
```

Key types:
- `ConsentRecord`, `ConsentPurpose`, `ConsentStatus` from `driving_consent`
- `ConsentState` from the app layer
- `FleetState` from the app layer over `fleet_hazard`

Reference wiring:

```dart
BlocListener<ConsentBloc, ConsentState>(
  listenWhen: (prev, curr) => prev.isFleetGranted != curr.isFleetGranted,
  listener: (context, state) {
    context.read<FleetBloc>().add(
      state.isFleetGranted ? FleetListenStarted() : FleetListenStopped(),
    );
  },
  child: const SnowSceneScaffold(),
)
```

Sprint 60 evidence:
- `test/integration/snow_scene_demo_flow_test.dart` proves fleet reports before
  consent grant are ignored end to end, then begin affecting alerts only after
  consent is granted.
- `test/widgets/snow_scene_scaffold_test.dart` proves the widget-mediated
  bridge dispatches `FleetListenStarted` on grant and `FleetListenStopped` on
  revoke.

### Offline Coverage Support

`offline_tiles` is deliberately orthogonal to the three pipelines above. It is
the map-survivability package: route shape and viewport logic still work, but
the developer can ask a second question before the drive begins: "do I have
local tile coverage for this route?"

Sprint 60 evidence:
- `packages/offline_tiles/test/integration/offline_tile_manager_test.dart`
  proves exact tile resolution, lower-zoom fallback, per-point coverage, and
  uncovered waypoint reporting across a route shape.

### Full Composition at the App Boundary

The app layer is where the toolkit becomes a product. In the Snow Scene app,
the package surface is composed with app-owned BLoCs for location, weather,
fleet, and consent, then rendered through `SnowSceneScaffold`.

```
kalman_dr            -> LocationBloc ---
routing_engine       -> RoutingBloc ----\
navigation_safety    -> NavigationBloc --\
map_viewport_bloc    -> MapBloc -----------+-> SnowSceneScaffold
driving_weather      -> WeatherBloc -----/
driving_consent      -> ConsentBloc -----/
fleet_hazard         -> FleetBloc -------/
offline_tiles        -> MapLayer tile provider
```

This split is intentional:
- Packages own reusable domain behavior
- The app owns scenario choreography and UI timing
- Integration tests prove the whole tree behaves coherently

### Where To Start

If you are adopting SNGNav selectively, start from the smallest package set
that matches your use case.

| Goal | Start here |
|------|------------|
| Add routing to an existing Flutter app | `routing_engine` + `routing_bloc` |
| Keep position flowing when GPS drops | `kalman_dr` |
| Add consent-aware fleet telemetry | `driving_consent` + `fleet_hazard` |
| Turn weather and fleet input into safety alerts | `driving_weather` + `fleet_hazard` + `navigation_safety` + optionally `driving_conditions` |
| Keep maps useful offline | `offline_tiles` + `map_viewport_bloc` |
| Reproduce the full Snow Scene reference flow | all 10 packages + the app-layer BLoCs in `lib/bloc/` |

Use this rule of thumb:
- Start with one package when you need one capability.
- Add a second package when you need lifecycle or UI state.
- Move to the full app composition only when you need the whole
  driver-assisting chain.

---

## Widget Architecture

The UI is a 4-layer stack with strict Z-ordering:

| Z | Layer | Purpose |
|:-:|-------|---------|
| 0 | MapLayer | Map tiles (online or MBTiles) |
| 1 | NavigationOverlay | Route line, turn instructions, speed |
| 2 | SafetyOverlay | Weather alerts, hazard zones |
| 3 | BottomNavBar | Navigation controls |

**Z-order is non-negotiable.** The SafetyOverlay is always rendered and always
above navigation content. Critical alerts are modal — they block map
interaction until the driver acknowledges. See [SAFETY.md](SAFETY.md).

---

## Safety Boundary

SNGNav is classified **ASIL-QM** (Quality Management) under ISO 26262. It is a
display-only navigation aid — no steering, braking, throttle, or ADAS control.
This boundary is verified every sprint: zero actuator calls in the codebase.

Key safety rules:
- Dead reckoning estimates are marked with increasing accuracy radius
- Safety alerts are advisory — they never suppress driver judgment
- Fleet telemetry requires explicit consent (deny by default)
- No data leaves the device without explicit grant

See [SAFETY.md](SAFETY.md) for the complete safety statement.

---

## Performance Reference

Benchmarks on Machine D (MacBook Pro 2017, i5-7267U, 8GB RAM):

| Operation | p50 | p95 |
|-----------|-----|-----|
| Kalman predict (1 step) | ~15 microseconds | ~20 microseconds |
| 60-second tunnel DR (60 predictions) | ~300 microseconds total | — |
| Kalman convergence | ~10 GPS fixes to sub-4m | — |
| Polyline decode (500 points) | < 1ms | — |
| OSRM route parse (25 maneuvers) | ~400 microseconds | — |
| Valhalla route parse (25 maneuvers) | ~400 microseconds | — |

See [BENCHMARKS.md](BENCHMARKS.md) for full results.

---

## Further Reading

- [CONTRIBUTING.md](CONTRIBUTING.md) — how to add providers, test conventions
- [SAFETY.md](SAFETY.md) — safety classification, alert design, consent model
- [BENCHMARKS.md](BENCHMARKS.md) — performance reference numbers
- [README.md](README.md) — quick start, build instructions, API documentation
