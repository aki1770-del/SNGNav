# SNGNav Architecture Guide

SNGNav is an offline-first navigation architecture for Flutter on embedded Linux.
It is designed for the moment most navigation systems handle badly: the tunnel,
the mountain pass, the rural dead zone, the unexpected snowstorm. When GPS,
network, or backend reachability degrades, the system should degrade one layer
at a time instead of abandoning the driver.

As of `v0.6.0`, the project has:

- 11 published packages on pub.dev
- 1,005 automated tests
- 91% line coverage in CI
- 6,904 lines of library code
- 122 source files
- 0 analyzer issues at the release gate

This document explains the architecture from two perspectives:

1. The driver-facing view: what failure modes the system is built to survive.
2. The edge-developer view: how the packages, BLoCs, and interfaces compose.

---

## Design Anchor

SNGNav starts from one question:

> **How can we help the driver when conditions are worst?**

The project is not organized around feature demos. It is organized around
failure boundaries. Each major package exists because something important can
disappear at the wrong time: GPS signal, network access, backend availability,
sensor quality, or deployment assumptions.

The customer is the edge developer building for the driver who still needs help
when those assumptions fail.

---

## The Five Guardians

SNGNav's name encodes its purpose: **S**now **G**uard **Nav**igation. The
architecture is shaped around five guardians, each protecting against a
different failure mode.

| Guardian | Protects against | Architectural response |
|----------|------------------|------------------------|
| Dead reckoning | GPS loss in tunnels, canyons, blizzards | Predict position from speed and heading when fixes drop |
| Offline tiles | Network loss | Serve map tiles from MBTiles instead of relying on the network |
| Local routing | Cloud or server unavailability | Use engine-agnostic routing with local Valhalla, OSRM, or mock fallback |
| Kalman filter | Noisy or degraded sensor input | Smooth GPS while available, grow uncertainty honestly when predicting |
| Config system | Deployment variation | Switch implementations with `--dart-define` instead of code forks |

The point is not that each guardian is impressive alone. The point is that no
single failure abandons the driver.

---

## Layered System

At a high level, the runtime stack looks like this:

```text
Provider / Engine Layer
  Valhalla | OSRM | Mock routing | MBTiles | TTS backend
            |
            v
Application State Layer
  RoutingBloc -> NavigationBloc -> VoiceGuidanceBloc
         |             |
         v             v
      MapBloc      SafetyOverlay
            |
            v
Presentation Layer
  Flutter widgets, route progress, map camera, alerts, controls
```

Three rules matter here:

1. The UI does not talk directly to infrastructure.
2. BLoCs own domain state, not backend details.
3. Concrete providers remain swappable behind interfaces.

That separation is what lets the project keep working when one implementation
changes or disappears.

---

## Package Portfolio

The codebase is a Flutter monorepo with 11 extracted packages. Seven are pure
Dart. Four provide Flutter BLoC integration while still exposing reusable core
libraries where appropriate.

| Package | Type | Responsibility |
|---------|------|----------------|
| `kalman_dr` | Pure Dart | 4D Extended Kalman Filter and dead reckoning primitives |
| `routing_engine` | Pure Dart | Engine-agnostic route interface for Valhalla, OSRM, or mock |
| `routing_bloc` | Flutter + BLoC | Route lifecycle state machine |
| `driving_weather` | Pure Dart | Weather condition model: precipitation, intensity, visibility, ice risk |
| `driving_conditions` | Pure Dart | Road surface classification, grip factors, simulation |
| `driving_consent` | Pure Dart | Per-purpose, per-jurisdiction consent model with deny-by-default semantics |
| `fleet_hazard` | Pure Dart | Hazard reports, clustering, temporal decay |
| `navigation_safety` | Flutter + BLoC | Safety boundaries, overlays, session-level alerts |
| `map_viewport_bloc` | Flutter + BLoC | Map camera and viewport state |
| `offline_tiles` | Pure Dart | MBTiles-backed offline tile management |
| `voice_guidance` | Flutter + Dart | Engine-agnostic turn-by-turn and hazard speech |

This split is deliberate. SNGNav pushes domain logic downward into packages that
can be tested without widgets and, in many cases, without Flutter at all.

---

## Composition Model

The example application demonstrates four-BLoC composition in one
`MultiBlocProvider`:

```dart
MultiBlocProvider(
  providers: [
    BlocProvider(
      create: (_) => MapBloc()
        ..add(const MapInitialized(center: _origin, zoom: 9.8)),
    ),
    BlocProvider(
      create: (_) => RoutingBloc(engine: _HybridRoutingEngine())
        ..add(const RoutingEngineCheckRequested()),
    ),
    BlocProvider(create: (_) => NavigationBloc()),
    BlocProvider(
      create: (context) => VoiceGuidanceBloc(
        ttsEngine: _ttsEngine,
        navigationStateStream: context.read<NavigationBloc>().stream,
        config: VoiceGuidanceConfig(
          enabled: _voiceGuidanceEnabled,
          languageTag: _voiceLanguageTag,
        ),
      ),
    ),
  ],
  child: const ExampleHomePage(),
)
```

Each BLoC owns one domain:

- `RoutingBloc` manages route request, loading, success, and failure.
- `NavigationBloc` tracks progress through maneuvers and arrival state.
- `VoiceGuidanceBloc` watches navigation state and turns transitions into speech.
- `MapBloc` controls camera position, zoom, and follow/overview behavior.

What matters is what these BLoCs do **not** know:

- `RoutingBloc` does not know whether the route came from Valhalla, OSRM, or a mock engine.
- `VoiceGuidanceBloc` does not know whether audio came from Flutter TTS, Linux `spd-say`, or a no-op engine.
- `MapBloc` does not know whether tiles came from disk or the network.

That ignorance is the architecture working as intended.

---

## Key Flows

### 1. Route Request and Navigation

The route flow is intentionally layered:

```text
RouteRequest
  -> routing_engine
  -> RouteResult
  -> routing_bloc
  -> navigation state
  -> viewport updates + UI rendering
```

The route engine is a fallback chain. A deployment can prefer Valhalla, fall
back to OSRM, or use a deterministic mock engine for local demos and tests.

This separation matters because routing and navigation are different problems.
Losing the ability to calculate a fresh route is bad; losing the ability to
continue along the current route is worse. SNGNav keeps those concerns separate.

### 2. GPS Loss and Honest Uncertainty

The `kalman_dr` package tracks `[latitude, longitude, speed, heading]`.

When GPS is available:

- predict forward
- update with the new measurement
- emit a smoothed position estimate

When GPS disappears:

- continue predicting from filter state
- grow covariance over time
- expose larger accuracy radii instead of pretending confidence

The system does not hide degradation. It models it.

### 3. Offline Map Survival

`offline_tiles` treats local data as a first-class runtime path, not a backup.
The effective resolution order is:

```text
RAM cache -> MBTiles -> lower-zoom fallback -> online -> placeholder
```

This means the runtime tries to serve the best local tile first and only uses
the network when the local path is exhausted.

### 4. Privacy Gate

`driving_consent` is a hard architectural gate, not a policy flourish.

Core rule:

```dart
bool get isEffectivelyGranted => status == ConsentStatus.granted;
```

Operationally, `unknown` and `denied` both mean stop.

That gives the system four useful properties:

- consent is per-purpose
- consent is per-jurisdiction
- revocation is immediate
- startup defaults to no data flow

### 5. Voice as a Co-Driver

`voice_guidance` adds a narrow, explicit speech interface:

```dart
abstract class TtsEngine {
  Future<bool> isAvailable();
  Future<void> setLanguage(String languageTag);
  Future<void> setVolume(double volume);
  Future<void> speak(String text);
  Future<void> stop();
  Future<void> dispose();
}
```

This keeps platform-specific speech details out of the UI and BLoCs. On Linux,
the engine can route through Speech Dispatcher. In tests, it can fall back to a
no-op implementation while still exercising state transitions and formatting.

Voice guidance is advisory. It helps reduce glance load. It does not control the
vehicle.

---

## Runtime Configuration

SNGNav uses compile-time flags to select implementations without forking the
application.

Typical examples:

| Concern | Example values |
|---------|----------------|
| Weather source | `simulated`, `open_meteo` |
| Location source | `simulated`, `geoclue` |
| Dead reckoning mode | `kalman`, `linear` |
| Routing backend | `mock`, `osrm`, `valhalla` |
| Tile source | `online`, `mbtiles` |

This keeps one codebase usable across desktop demos, development rigs, CI, and
future embedded deployments.

---

## Monorepo Structure

The repo is organized around reusable packages plus an example application that
demonstrates composition:

```text
packages/
  driving_conditions/
  driving_consent/
  driving_weather/
  fleet_hazard/
  kalman_dr/
  map_viewport_bloc/
  navigation_safety/
  offline_tiles/
  routing_bloc/
  routing_engine/
  voice_guidance/

example/
  lib/
  test/

tool/
  CI and release support
```

The architectural rule is simple: if a capability can be extracted into a clean
boundary, it should become a package instead of being buried in widget code.

---

## Safety Boundary

SNGNav stays within an ASIL-QM advisory boundary.

- Display and audio only
- No actuator path
- No vehicle control
- No attempt to replace driver judgment

This matters because the project is built to assist the driver under degraded
conditions, not to automate the vehicle.

---

## Present Limitations

The architecture is real, published, and tested, but its limits should stay
explicit:

- The current UI is 2D, not 3D.
- Linux desktop is the primary supported runtime today.
- Real routing still depends on a routing engine such as Valhalla or OSRM.
- The project is still effectively maintained by one primary contributor.
- The hardest snow-driving scenarios are still validated mostly through software evidence, not field deployment.

Those limits do not weaken the architecture. They define it honestly.

---

## Further Reading

- [README.md](README.md)
- [SAFETY.md](SAFETY.md)
- [CONTRIBUTING.md](CONTRIBUTING.md)
- [SNGNAV_WAY.md](SNGNAV_WAY.md)
- [packages](packages)
- [example](example)

The architecture should make one promise clear: when the preferred path
disappears, the system should still tell the truth and keep helping.
