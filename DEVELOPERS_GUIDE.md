# SNGNav Developers Guide

**The hub for edge developers building driver-assisting navigation.**

---

## §1 What SNGNav Gives You

You build navigation experiences for embedded Linux. Your driver leaves
Nagoya at 6 AM. By 7:15 she's on a mountain pass and the sky turns white.
GPS dies in a tunnel. The network dropped two kilometers back.

You need packages that keep working when everything fails.

SNGNav is **10 Dart/Flutter packages** that solve navigation safety
computation — dead reckoning, route computation, driving conditions
assessment, safety score simulation, consent management, fleet hazard
scoring, weather integration, offline tiles, and viewport management.
Each package is independently testable, independently publishable, and
independently usable.

**What you get:**

- **Position continuity** when GPS fails — Kalman-filtered dead reckoning
- **Route computation** without cloud access — OSRM and Valhalla backends
- **Driving conditions assessment** — road surface, visibility, precipitation
- **Safety score simulation** — Monte Carlo engine with pluggable backends
- **Consent management** — deny-by-default, per-purpose, revocable
- **Fleet hazard scoring** — cluster reports into hazard zones
- **Weather integration** — condition models with offline fallback
- **Offline map tiles** — MBTiles with multi-level fallback
- **Viewport state management** — camera modes, layer control
- **Route lifecycle management** — progress tracking, maneuver display

All pure Dart where possible. No proprietary dependencies. BSD-compatible.

### Five Principles

Every package follows five rules:

1. **Offline-First** — works without network. The snowstorm kills connectivity;
   the system keeps running.
2. **Consent by Default** — data collection is deny-by-default, per-purpose,
   revocable. Privacy is architecture, not afterthought.
3. **Display-Only Safety** — ASIL-QM. Advisory only. Never controls the vehicle.
4. **Extractable Boundaries** — every domain boundary is a reusable package.
   Pure Dart packages stay pure Dart.
5. **Evidence over Aspiration** — every claim is backed by a passing test.

### Who This Guide Is For

You are an edge developer. You know Flutter. You know embedded Linux exists.
You need navigation safety computation for a driver-assisting application.
You found us on pub.dev.

This guide teaches you how to build with SNGNav packages. It does not
describe how we built them — it shows you how *you* build with them.

---

## §2 Architecture Overview

### The 10-Package Ecosystem

SNGNav's architecture is a set of independently usable packages organized
by domain. Six are pure Dart (no Flutter dependency). Four are Flutter
packages that expose pure Dart `_core` libraries for non-Flutter reuse.

#### Pure Dart Packages (use anywhere — CLI, server, test harness, Flutter)

| Package | Domain | What it computes |
|---------|--------|-----------------|
| `kalman_dr` | Position | 4D Extended Kalman Filter for dead reckoning |
| `routing_engine` | Routing | Abstract routing interface + OSRM/Valhalla |
| `driving_weather` | Weather | Weather condition model + provider interface |
| `driving_consent` | Consent | Consent lifecycle — record, revoke, query |
| `fleet_hazard` | Fleet | Fleet reports → hazard zone clustering |
| `driving_conditions` | Safety | Road surface, visibility, Monte Carlo simulation |

#### Flutter + `_core` Packages (Flutter BLoCs + pure Dart core)

| Package | Domain | What it manages |
|---------|--------|----------------|
| `navigation_safety` | Safety UI | Safety session BLoC + SafetyScore model |
| `map_viewport_bloc` | Viewport | Camera modes, layer visibility, fit-to-bounds |
| `routing_bloc` | Routing UI | Route lifecycle BLoC + progress display |
| `offline_tiles` | Tiles | Offline tile manager + runtime resolver |

### Dependency Graph

```
                    ┌──────────────────┐
                    │ driving_conditions│
                    │   (simulation)   │
                    └────┬────────┬────┘
                         │        │
                         ▼        ▼
              ┌──────────────┐  ┌─────────────────┐
              │driving_weather│  │navigation_safety │
              │  (weather)   │  │  (safety BLoC)   │
              └──────────────┘  └────────┬─────────┘
                                         │
                                         ▼
                                ┌────────────────┐
                                │ routing_engine  │
                                │ (route compute) │
                                └───────┬────────┘
                                        │
                                        ▼
                               ┌────────────────┐
                               │  routing_bloc   │
                               │ (route BLoC)    │
                               └────────────────┘

  Independent (no internal dependencies):
  ┌────────────┐  ┌─────────────────┐  ┌──────────────┐
  │  kalman_dr  │  │ driving_consent │  │ fleet_hazard  │
  └────────────┘  └─────────────────┘  └──────────────┘

  ┌───────────────────┐  ┌───────────────┐
  │ map_viewport_bloc  │  │ offline_tiles  │
  └───────────────────┘  └───────────────┘
```

**Key dependency rules:**
- `driving_conditions` depends on `driving_weather` (weather types) and
  `navigation_safety` (SafetyScore model)
- `navigation_safety` depends on `routing_engine` (route types)
- `routing_bloc` depends on `routing_engine` (route computation)
- All other packages are independent — no internal dependencies

### Pure Dart `_core` Libraries

Four Flutter packages expose a `_core` import for non-Flutter use:

```dart
// Flutter app — full BLoC + widgets
import 'package:navigation_safety/navigation_safety.dart';

// Pure Dart (CLI, server, test) — models only, no Flutter
import 'package:navigation_safety/navigation_safety_core.dart';
```

Same pattern for `map_viewport_bloc`, `routing_bloc`, and `offline_tiles`.

---

## §3 Quick Start — First Safety Score in 5 Minutes

This walkthrough gets you from zero to a computed safety score.
You need only Dart — no Flutter required.

### Step 1: Add the packages

```yaml
# pubspec.yaml
dependencies:
  driving_conditions: ^0.1.0
  kalman_dr: ^0.1.0
  navigation_safety: ^0.1.0
  driving_weather: ^0.1.0
  driving_consent: ^0.1.0
  fleet_hazard: ^0.1.0
  routing_engine: ^0.1.0
```

### Step 2: Compute a safety score

```dart
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:navigation_safety/navigation_safety_core.dart';

void main() {
  // 1. Classify the road surface from weather conditions
  final weather = WeatherCondition(
    precipType: PrecipitationType.snow,
    intensity: PrecipitationIntensity.heavy,
    temperatureCelsius: -2.0,
    visibilityMeters: 200,
    windSpeedKmh: 30.0,
    iceRisk: true,
    timestamp: DateTime.now(),
  );
  final surface = RoadSurfaceState.fromCondition(weather);

  print('Road surface: ${surface.name}');
  print('Grip factor: ${surface.gripFactor}');

  // 2. Run Monte Carlo safety simulation (1000 runs, seeded)
  const simulator = SafetyScoreSimulator();
  final score = simulator.simulate(
    speed: 60.0,
    gripFactor: surface.gripFactor,
    surface: surface,
    visibilityMeters: 200.0,
    seed: 42, // deterministic for testing
  );

  print('Overall safety: ${score.overall.toStringAsFixed(3)}');
  print('Grip score:     ${score.gripScore.toStringAsFixed(3)}');
  print('Visibility:     ${score.visibilityScore.toStringAsFixed(3)}');
  print('Fleet conf:     ${score.fleetConfidenceScore.toStringAsFixed(3)}');

  // 3. Check alert severity
  final severity = score.toAlertSeverity(const NavigationSafetyConfig());
  print('Alert: ${severity?.name ?? "none — conditions safe"}');
}
```

Run it:

```bash
dart run
```

That's it. You computed a probabilistic safety score from weather conditions
in pure Dart. No Flutter, no cloud, no API keys.

---

## §4 Package-by-Package Guide

### kalman_dr — Position Without GPS

**When to use**: your device may lose GPS (tunnels, canyons, blizzards) and
you need position continuity.

**What it gives you**: a 4D Extended Kalman Filter that predicts position
from speed and heading when GPS is unavailable. Two modes: `kalman` (covariance-
aware, ~20m/min drift) and `linear` (simple extrapolation, ~50m/min drift).

```dart
import 'package:kalman_dr/kalman_dr.dart';

final filter = KalmanFilter();

// Feed GPS measurements
filter.update(lat: 35.17, lon: 136.91,
              speed: 15.0, heading: 45.0, accuracy: 5.0,
              timestamp: DateTime.now());

// GPS lost — predict forward
final predicted = filter.predict(const Duration(seconds: 1));
print('Predicted: ${predicted.lat}, ${predicted.lon}');
print('Accuracy: ${predicted.accuracy}m');
```

**Safety cap**: prediction stops at 500m accuracy. Better to show "position
unavailable" than a misleading estimate.

**pub.dev**: [kalman_dr](https://pub.dev/packages/kalman_dr)

---

### routing_engine — Routes Without Cloud

**When to use**: you need driving routes and can't depend on cloud APIs.

**What it gives you**: an abstract `RoutingEngine` interface with OSRM and
Valhalla implementations. Both run locally via Docker. Swap backends without
touching app logic.

```dart
import 'package:routing_engine/routing_engine.dart';

final engine = OsrmRoutingEngine(baseUrl: 'http://localhost:5000');

final result = await engine.calculateRoute(
  RouteRequest(
    origin: LatLng(35.17, 136.91),
    destination: LatLng(34.95, 137.16),
  ),
);

print('Distance: ${result.distanceMeters}m');
print('Duration: ${result.durationSeconds}s');
print('Maneuvers: ${result.maneuvers.length}');
```

**When to choose OSRM vs Valhalla**: OSRM for speed (~5ms). Valhalla for
multi-modal routing, Japanese kanji instructions, or isochrone analysis.

**pub.dev**: [routing_engine](https://pub.dev/packages/routing_engine)

---

### driving_weather — Weather Conditions Model

**When to use**: you need structured weather data for driving safety assessment.

**What it gives you**: `WeatherCondition` — an Equatable model with
precipitation type/intensity, temperature, visibility, wind speed, and ice
risk. Plus `WeatherProvider` — an abstract interface for plugging any weather
data source.

```dart
import 'package:driving_weather/driving_weather.dart';

final condition = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -3.0,
  visibilityMeters: 150,
  windSpeedKmh: 40.0,
  iceRisk: true,
  timestamp: DateTime.now(),
);

print('Precipitation: ${condition.precipType.name}');
print('Ice risk: ${condition.iceRisk}');
print('Visibility: ${condition.visibilityMeters}m');
```

Includes `OpenMeteoWeatherProvider` (live data, offline fallback) and
`SimulatedWeatherProvider` (demo mountain-pass snow scenario).

**pub.dev**: [driving_weather](https://pub.dev/packages/driving_weather)

---

### driving_consent — Privacy as Architecture

**When to use**: you collect any driver data — location, fleet reports,
weather telemetry — and need consent management.

**What it gives you**: deny-by-default, per-purpose, revocable consent
lifecycle. The driver explicitly grants each data category. Revocation
is immediate and retroactive.

```dart
import 'package:driving_consent/driving_consent.dart';

final service = InMemoryConsentService();

// Grant consent for fleet location sharing
final record = await service.grant(
  ConsentPurpose.fleetLocation,
  Jurisdiction.gdpr,
);
print('Granted: ${record.isEffectivelyGranted}');

// Check before collecting — Jidoka: UNKNOWN = DENIED
final consent = await service.getConsent(ConsentPurpose.fleetLocation);
if (consent.isEffectivelyGranted) {
  // Safe to collect fleet telemetry
}

// Driver revokes — immediate, retroactive
await service.revoke(ConsentPurpose.fleetLocation);
```

**pub.dev**: [driving_consent](https://pub.dev/packages/driving_consent)

---

### fleet_hazard — Collective Safety Intelligence

**When to use**: you aggregate reports from multiple drivers (with consent)
to identify hazard zones.

**What it gives you**: fleet report ingestion, Haversine-based spatial
clustering, and hazard zone generation. Anonymous, aggregated, consent-gated.

```dart
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';

// Collect fleet reports (each from a consenting driver)
final reports = [
  FleetReport(
    vehicleId: 'v-001',
    position: const LatLng(35.17, 136.91),
    condition: RoadCondition.icy,
    timestamp: DateTime.now(),
  ),
  FleetReport(
    vehicleId: 'v-002',
    position: const LatLng(35.172, 136.912),
    condition: RoadCondition.snowy,
    timestamp: DateTime.now(),
  ),
];

// Cluster into hazard zones (static method)
final zones = HazardAggregator.aggregate(reports);
print('Hazard zones: ${zones.length}');
```

**pub.dev**: [fleet_hazard](https://pub.dev/packages/fleet_hazard)

---

### driving_conditions — Safety Score Computation

**When to use**: you need to assess driving safety from weather, road surface,
and visibility data.

**What it gives you**: road surface classification (6 states from dry to
black ice), visibility degradation computation, precipitation parameter
generation, combined driving condition assessment, and Monte Carlo safety
score simulation with pluggable backends.

```dart
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';

// Classify road surface from weather
final surface = RoadSurfaceState.fromCondition(condition);

// Compute visibility degradation
final viz = VisibilityDegradation.compute(150);
print('Opacity: ${viz.opacity}');
print('Blur sigma: ${viz.blurSigma}');

// Full driving condition assessment
final assessment = DrivingConditionAssessment.fromCondition(condition);
print('Advisory: ${assessment.advisoryMessage}');
```

**Backend selection** (see §6 for details):

```dart
// Default — CPU backend (pure Dart)
const simulator = SafetyScoreSimulator();

// Explicit CPU engine
const cpuSim = SafetyScoreSimulator(
  engine: CpuSafetyScoreSimulationEngine(),
);

// Both produce identical results for the same seed
```

**pub.dev**: [driving_conditions](https://pub.dev/packages/driving_conditions)

---

### navigation_safety — Safety Session BLoC

**When to use**: you're building a Flutter navigation app and need safety
session management with alert display.

**What it gives you**: `NavigationBloc` (safety session state machine),
`SafetyScore` (composite score model), `SafetyOverlay` (always-on alert
widget), and alert severity classification.

```dart
import 'package:navigation_safety/navigation_safety.dart';

// In your Flutter app
final bloc = NavigationBloc(
  routingEngine: yourRoutingEngine,
);

// SafetyScore from driving_conditions feeds into the bloc
// SafetyOverlay renders alerts based on severity thresholds
```

**Pure Dart reuse** (no Flutter):

```dart
import 'package:navigation_safety/navigation_safety_core.dart';

// SafetyScore, AlertSeverity, NavigationSafetyConfig
// available without Flutter dependency
```

**pub.dev**: [navigation_safety](https://pub.dev/packages/navigation_safety)

---

### map_viewport_bloc — Viewport State Machine

**When to use**: you're managing a Flutter map with camera modes and layers.

**What it gives you**: `MapViewportBloc` — a BLoC that manages camera modes
(`follow`, `freeLook`, `overview`), layer visibility (Z0–Z5), and
fit-to-bounds transitions.

**Key rules**:
- Z0 (base tile) and Z5 (safety) are not user-toggleable
- `freeLook` auto-returns to `follow` after 10 seconds idle
- Safety events may force `follow` mode

**pub.dev**: [map_viewport_bloc](https://pub.dev/packages/map_viewport_bloc)

---

### routing_bloc — Route Lifecycle State Machine

**When to use**: you're managing route guidance in a Flutter navigation app.

**What it gives you**: `RoutingBloc` — lifecycle states (`idle`, `loading`,
`routeActive`, `error`), route progress tracking, maneuver icon mapping,
engine-agnostic route requests.

**pub.dev**: [routing_bloc](https://pub.dev/packages/routing_bloc)

---

### offline_tiles — Maps Without Network

**When to use**: your map must work when the network fails.

**What it gives you**: MBTiles tile management with four-level fallback
(RAM cache → MBTiles → lower-zoom → placeholder). Coverage tiers
(corridor, metro, prefecture, national) define caching policy.

**pub.dev**: [offline_tiles](https://pub.dev/packages/offline_tiles)

---

## §5 Cross-Package Flows

These five flows show how SNGNav packages compose for real driving scenarios.
Each flow was validated with automated integration tests in Sprint 52.

### Flow 1: Weather → Driving Conditions → Safety Score

The most common flow. Weather data becomes a safety score.

```
WeatherCondition (driving_weather)
    │
    ▼
RoadSurfaceState.fromCondition() (driving_conditions)
    │
    ▼
SafetyScoreSimulator.simulate() (driving_conditions)
    │
    ▼
SafetyScore (navigation_safety_core)
    │
    ▼
AlertSeverity (navigation_safety_core)
```

**In code:**

```dart
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:navigation_safety/navigation_safety_core.dart';

// Weather arrives (from provider, sensor, or API)
final weather = WeatherCondition(
  precipType: PrecipitationType.snow,
  intensity: PrecipitationIntensity.heavy,
  temperatureCelsius: -2.0,
  visibilityMeters: 200,
  windSpeedKmh: 30.0,
  iceRisk: true,
  timestamp: DateTime.now(),
);

// Classify road surface
final surface = RoadSurfaceState.fromCondition(weather);

// Simulate safety score
const simulator = SafetyScoreSimulator();
final score = simulator.simulate(
  speed: 60.0,
  gripFactor: surface.gripFactor,
  surface: surface,
  visibilityMeters: weather.visibilityMeters.toDouble(),
  seed: 42,
);

// Determine alert level
final severity = score.toAlertSeverity(const NavigationSafetyConfig());
// severity: AlertSeverity.warning, .critical, or null (safe)
```

### Flow 2: Route Request → Routing Engine → Routing BLoC

Route computation feeds the UI state machine.

```
RouteRequest (routing_engine)
    │
    ▼
RoutingEngine.calculateRoute() (routing_engine)
    │
    ▼
RouteResult (routing_engine)
    │
    ▼
RoutingBloc (routing_bloc)
    │
    ▼
Route UI: maneuvers, ETA, distance
```

The BLoC receives a `RouteResult` and manages the lifecycle from `idle`
through `loading` to `routeActive`. The engine is injected — switching
from OSRM to Valhalla changes nothing in the BLoC or widget layer.

### Flow 3: GPS Loss → Dead Reckoning → Position Continuity

When GPS disappears, dead reckoning maintains position.

```
GPS stream (any LocationProvider)
    │
    ├── GPS available: emit filtered position
    │
    └── GPS lost (3s timeout):
        │
        ▼
    KalmanFilter.predict() (kalman_dr)
        │
        ▼
    Predicted GeoPosition with growing accuracy radius
        │
        ▼
    LocationBloc sees a continuous stream — no gaps
```

The dead reckoning provider wraps any `LocationProvider` using the decorator
pattern. The BLoC never knows whether the position came from GPS or prediction.

### Flow 4: Fleet Reports → Hazard Zones → Safety Overlay

Consent-gated fleet data becomes spatial hazard intelligence.

```
FleetReport (fleet_hazard) ← requires ConsentPurpose.fleetLocation grant
    │
    ▼
HazardAggregator.aggregate() (fleet_hazard)
    │
    ▼
HazardZone[] (fleet_hazard)
    │
    ▼
SafetyOverlay renders hazard markers (navigation_safety)
```

Fleet reports are only ingested if the driver has granted `fleetLocation`
consent. The aggregator clusters reports using Haversine distance. The hazard
zones feed into the safety overlay at Z-layer 3.

### Flow 5: Full Chain — Unexpected Snow

The complete scenario. A driver hits unexpected snow on a mountain pass.

```
GPS Position (kalman_dr — DR active if tunnel)
    │
Weather changes: clear → snow (driving_weather)
    │
    ├── Road surface reclassified: dry → compactedSnow → blackIce
    │   (driving_conditions)
    │
    ├── Safety score drops: 0.85 → 0.45 → 0.25
    │   (driving_conditions → navigation_safety_core)
    │
    ├── Alert escalates: none → warning → critical
    │   (navigation_safety)
    │
    ├── Fleet reports: 47 drivers reported conditions in last hour
    │   (fleet_hazard, consent-gated)
    │
    ├── Route guidance continues (routing_bloc + routing_engine)
    │
    └── Map renders: offline tiles + route + fleet markers + hazard zones
        (offline_tiles + map_viewport_bloc)
```

Every package participates. No single package's failure breaks the chain.
This is the scenario SNGNav exists for.

---

## §6 L2 Engine Abstraction — Pluggable Simulation Backends

Sprint 53 introduced a backend abstraction layer for safety score simulation.
This lets you swap the compute engine without changing your application code.

### The Interface

```dart
abstract interface class SafetyScoreSimulationEngine {
  SafetyScore simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  });
}
```

### Available Backends

| Backend | Implementation | When to use |
|---------|---------------|-------------|
| `auto` | Selects best available | Default — use this |
| `cpu` | `CpuSafetyScoreSimulationEngine` | Pure Dart, works everywhere |
| `gpu` | Not yet implemented | Future — GPU compute acceleration |

### Backend Selection

```dart
import 'package:driving_conditions/driving_conditions.dart';

// Auto backend (default) — uses CPU today, will use GPU when available
const simulator = SafetyScoreSimulator();

// Explicit CPU
const cpuSimulator = SafetyScoreSimulator(
  engine: CpuSafetyScoreSimulationEngine(),
);

// SimulationOptions for fine control
const engine = CpuSafetyScoreSimulationEngine();
final score = engine.simulate(
  speed: 60.0,
  gripFactor: 0.3,
  surface: RoadSurfaceState.compactedSnow,
  visibilityMeters: 200.0,
  options: SimulationOptions(
    backend: SimulationBackend.cpu,
    runs: 1000,
    seed: 42,
  ),
);
```

### Implementing Your Own Backend

To create a custom simulation backend:

```dart
import 'package:driving_conditions/driving_conditions.dart';
import 'package:navigation_safety/navigation_safety_core.dart';

class MyGpuEngine implements SafetyScoreSimulationEngine {
  @override
  SafetyScore simulate({
    required double speed,
    required double gripFactor,
    required RoadSurfaceState surface,
    required double visibilityMeters,
    required SimulationOptions options,
  }) {
    if (options.backend == SimulationBackend.cpu) {
      throw UnsupportedError('This engine is GPU-only');
    }

    // Your GPU compute implementation here
    // Must return a SafetyScore with values clamped to [0, 1]
    return SafetyScore(
      overall: computeOverall(),
      gripScore: computeGrip(),
      visibilityScore: computeVisibility(),
      fleetConfidenceScore: computeFleet(),
    );
  }
}

// Use it
final simulator = SafetyScoreSimulator(engine: MyGpuEngine());
```

### CPU vs Native Performance

The CPU engine (pure Dart) computes 1,000 Monte Carlo runs in ~5ms.
A native C engine (via `dart:ffi`) has been proven to produce equivalent
results within ε = 0.005 tolerance. See
[BENCHMARKS.md](BENCHMARKS.md) for full performance data.

---

## §7 Testing Your Integration

### Deterministic Simulation

Safety scores are deterministic when seeded. Use this for reliable tests:

```dart
import 'package:test/test.dart';
import 'package:driving_conditions/driving_conditions.dart';
import 'package:driving_weather/driving_weather.dart';
import 'package:navigation_safety/navigation_safety_core.dart';

test('safety score is deterministic with seed', () {
  const simulator = SafetyScoreSimulator();

  final score1 = simulator.simulate(
    speed: 60.0,
    gripFactor: 0.3,
    surface: RoadSurfaceState.compactedSnow,
    visibilityMeters: 200.0,
    seed: 42,
  );

  final score2 = simulator.simulate(
    speed: 60.0,
    gripFactor: 0.3,
    surface: RoadSurfaceState.compactedSnow,
    visibilityMeters: 200.0,
    seed: 42,
  );

  expect(score1.overall, equals(score2.overall));
  expect(score1.gripScore, equals(score2.gripScore));
});
```

### Engine Equivalence

If you implement a custom backend, verify it matches the CPU engine:

```dart
test('custom engine matches CPU within tolerance', () {
  const cpu = CpuSafetyScoreSimulationEngine();
  final custom = MyCustomEngine();

  const options = SimulationOptions(
    backend: SimulationBackend.auto,
    runs: 1000,
    seed: 42,
  );

  final cpuScore = cpu.simulate(
    speed: 60.0, gripFactor: 0.3,
    surface: RoadSurfaceState.blackIce,
    visibilityMeters: 100.0, options: options,
  );

  final customScore = custom.simulate(
    speed: 60.0, gripFactor: 0.3,
    surface: RoadSurfaceState.blackIce,
    visibilityMeters: 100.0, options: options,
  );

  expect(customScore.overall, closeTo(cpuScore.overall, 0.005));
  expect(customScore.gripScore, closeTo(cpuScore.gripScore, 0.005));
  expect(customScore.visibilityScore,
         closeTo(cpuScore.visibilityScore, 0.005));
});
```

The tolerance ε = 0.005 accounts for floating-point differences between
Dart doubles and native float32. This is the project standard.

### Road Surface Classification

Test that weather conditions map to expected surface states:

```dart
test('heavy snow with freezing temp produces compactedSnow', () {
  final surface = RoadSurfaceState.fromCondition(
    WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -5.0,
      visibilityMeters: 100,
      windSpeedKmh: 35.0,
      iceRisk: true,
      timestamp: DateTime.now(),
    ),
  );

  expect(surface, equals(RoadSurfaceState.compactedSnow));
  expect(surface.gripFactor, lessThan(0.5));
});
```

### Package Test Suites

Each package has its own test suite. Run them independently:

```bash
# Single pure Dart package
cd packages/driving_conditions && dart test

# Single Flutter package
cd packages/navigation_safety && flutter test

# All packages (choose the runner by package type)
for pkg in packages/*/; do
  echo "Testing $pkg..."
  if grep -q 'sdk: flutter' "$pkg/pubspec.yaml"; then
    (cd "$pkg" && flutter test) || exit 1
  else
    (cd "$pkg" && dart test) || exit 1
  fi
done

# Full app (Flutter required)
flutter test --exclude-tags=probe
```

---

## §8 The 3D Aspiration

SNGNav's foundation is 2D computation. The aspiration is 3D.

Today, when the safety score drops to 0.25, the driver sees a text overlay:
"Critical: ice risk ahead." Tomorrow, the driver sees a **3D scene** — ice
patches rendered on the road surface, tire pressure gauges showing grip loss,
fleet markers clustered around the hazard zone — all at 60fps on embedded ARM.

This is the difference between informing the driver and *showing* the driver.

### What This Means for You

The 3D layer depends on [Fluorite](https://fluorite.game) — Toyota's
Flutter-integrated game engine built on Google Filament PBR. When Fluorite's
contribution surface opens, the packages you're already using become the
data source for 3D rendering:

- `driving_conditions` → road surface and weather render state
- `fleet_hazard` → 3D hazard zone visualization
- `navigation_safety` → alert-driven scene transitions
- `kalman_dr` → camera position tracking through GPS gaps

**Your code doesn't change.** The computation packages produce the same
data. The 3D layer consumes it. This is why extractable boundaries matter —
the packages you adopt today are the packages the 3D layer uses tomorrow.

### Where We Are

| Layer | Status |
|-------|--------|
| Computation (L1) | Complete — 10 packages, 1,368+ tests |
| Backend abstraction (L2) | Foundation complete — pluggable engines, FFI proven |
| GPU acceleration (L2-D) | Designed, not yet implemented |
| 3D rendering (L3) | Aspiration — awaiting Fluorite |

The computation architecture is the cost we've already paid. The 3D
architecture is the investment we're making. Both exist so that *you* can
build the experiences that help drivers stay safe.

---

## Further Reading

- [The SNGNav Way](SNGNAV_WAY.md) — product vision, principles, package portfolio
- [Architecture Guide](ARCHITECTURE.md) — Five Guardians, provider system, decision flows
- [Safety Model](SAFETY.md) — ASIL-QM classification, alert design, boundaries
- [Benchmarks](BENCHMARKS.md) — performance reference numbers
- [Contributing](CONTRIBUTING.md) — how to add providers, submit changes
- [Extraction Method](EXTRACTING.md) — how packages are extracted from the monolith

---

*Built for edge developers. Tested with 1,368+ green tests. No cloud required.*
