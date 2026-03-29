# SNGNav — Agent Instructions

**Project**: sngnav_snow_scene v0.4.0
**What**: Offline-first Flutter navigation with dead reckoning, weather safety, fleet hazard aggregation, and configurable providers. Reference app for embedded Linux IVI.
**SDK**: Dart ^3.11.0, Flutter stable channel
**Platform**: Linux desktop (primary), embedded Linux IVI (target)
**Repo**: https://github.com/aki1770-del/sngnav

---

## Commands

```bash
# Resolve dependencies
flutter pub get

# Run all tests (excludes network-dependent probes)
flutter test --exclude-tags=probe

# Static analysis — zero issues required
flutter analyze --no-fatal-infos

# Build release binary
flutter build linux --release -t lib/snow_scene.dart

# Run a single package's tests
cd packages/<name> && dart test && cd ../..

# Pre-publish check for a package
cd packages/<name> && dart pub publish --dry-run && cd ../..

# Batch-check the Sprint 51 G3 publication set
./scripts/g3_batch_check.sh --pubdev-only

# Regenerate golden images after widget changes
flutter test --update-goldens
```

**Expected test counts**: 957 app tests, plus per-package: kalman_dr 64, routing_engine 114, driving_weather 35, driving_consent 34, fleet_hazard 39, navigation_safety 85, map_viewport_bloc 66, routing_bloc 52, offline_tiles 40, driving_conditions 105, voice_guidance 49.

---

## Architecture Rules

### Provider Pattern (non-negotiable)

Four abstract interfaces. BLoCs depend on interfaces, not implementations.

| Interface | Stream/Future | Implementations |
|-----------|---------------|-----------------|
| `LocationProvider` | `Stream<GeoPosition>` | SimulatedLocationProvider, GeoClueLocationProvider |
| `WeatherProvider` | `Stream<WeatherCondition>` | SimulatedWeatherProvider, OpenMeteoWeatherProvider |
| `RoutingEngine` | `Future<RouteResult>` | OsrmRoutingEngine, ValhallaRoutingEngine |
| `FleetProvider` | `Stream<FleetReport>` | SimulatedFleetProvider |

**Adding a provider** touches ONLY:
1. `lib/providers/your_provider.dart` — implementation
2. `lib/config/provider_config.dart` — registration

If you need to edit a BLoC or widget to add a provider, **STOP and ask the user**. The interface may need extending.

### Offline Rule

When the upstream data source is unreachable, **re-emit the last known value**. The driver sees stale-but-present data, not a blank widget. Stale > silent.

### Safety Overlay — 5 Non-Negotiable Rules

1. Always rendered (never removed from widget tree)
2. Always on top (highest z-order)
3. Passthrough when inactive (no input blocking)
4. Modal for critical alerts (blocks interaction until acknowledged)
5. Independent state (not coupled to any BLoC)

**Do NOT modify SafetyOverlay without explicit user approval.**

### Display-Only Boundary

ASIL-QM classification. This is a navigation **display aid**, not vehicle control. Dead reckoning positions are **estimates** — always show an accuracy indicator. Safety alerts are advisory — never suppress them.

### Compile-Time Flags (`--dart-define`)

| Flag | Values | Default |
|------|--------|---------|
| `WEATHER_PROVIDER` | `simulated`, `open_meteo` | `open_meteo` |
| `LOCATION_PROVIDER` | `simulated`, `geoclue` | `simulated` |
| `DEAD_RECKONING` | `true`, `false` | `true` |
| `DR_MODE` | `kalman`, `linear` | `kalman` |
| `ROUTING_ENGINE` | `mock`, `osrm`, `valhalla` | `mock` |
| `TILE_SOURCE` | `online`, `mbtiles` | `online` |
| `MBTILES_PATH` | file path | `data/offline_tiles.mbtiles` |
| `VALHALLA_BASE_URL` | URL | `http://valhalla1.openstreetmap.de` |

---

## File Structure

| Path | Purpose | Agent Rule |
|------|---------|-----------|
| `lib/bloc/` | BLoC state management (7 BLoCs) | **DON'T MODIFY** for new providers |
| `lib/config/` | ProviderConfig — flag parsing, factory | **EDIT** to register new providers |
| `lib/models/` | Barrel re-exports from packages | **EDIT** when migrating a package |
| `lib/providers/` | Provider implementations | **ADD** new providers here |
| `lib/services/` | Consent DB, hazard aggregation | Edit for service changes |
| `lib/widgets/` | UI widgets (12 widgets) | **DON'T MODIFY** for new providers |
| `lib/fluorite/` | Fluorite engine integration (stub) | Do not modify without user approval |
| `packages/` | 11 extracted packages in the monorepo | See G1→G2→G3 below |
| `test/` | Mirrors `lib/` structure | Mirror every new `lib/` file |

### Eleven Extracted Packages

| Package | Track | Status | What it models |
|---------|:-----:|:------:|---------------|
| `kalman_dr` | Pure Dart | Published | 4D Extended Kalman Filter for dead reckoning |
| `routing_engine` | Pure Dart | Published | Abstract routing interface + OSRM/Valhalla |
| `driving_weather` | Pure Dart | Published | Weather conditions model + providers |
| `driving_consent` | Pure Dart | Published | Consent lifecycle (record, category, manager) |
| `fleet_hazard` | Pure Dart | Published | Fleet reports, hazard zones, Haversine clustering |
| `navigation_safety` | Flutter + `_core` | Published | Navigation BLoC, SafetyOverlay, and pure Dart safety models |
| `map_viewport_bloc` | Flutter + `_core` | Published | Map viewport BLoC, camera modes, layer visibility, and pure Dart viewport models |
| `routing_bloc` | Flutter + `_core` | Published | Route lifecycle BLoC, route progress UI, maneuver icons, and pure Dart routing lifecycle models |
| `offline_tiles` | Flutter + `_core` | Published | Offline tile manager, runtime tile resolver, coverage tiers, and pure Dart tile source models |
| `voice_guidance` | Flutter | Published | TTS engine abstraction, VoiceGuidanceBloc, platform-safe default engine selection |
| `driving_conditions` | Pure Dart | Extracted in repo (G1.5) | Road surface state, visibility degradation, precipitation config, assessment bridge, Monte Carlo safety score simulation |

### Routing Bloc Contract

`routing_bloc` defines the canonical route lifecycle contract for Phase B:

| Concept | Canonical contract |
|---------|--------------------|
| Lifecycle states | `idle`, `loading`, `routeActive`, `error` |
| Core events | `RouteRequested`, `RouteClearRequested`, `RoutingEngineCheckRequested` |
| Engine posture | Engine-agnostic via `routing_engine` injection |
| Route progress UI | Package-owned `RouteProgressBar`, data-driven (no dependency on `NavigationBloc`) |
| Glanceability rule | Primary instruction first, ETA/distance second, minimal control density |

### Offline Tiles Contract

`offline_tiles` defines the canonical offline tile management contract for Phase B:

| Concept | Canonical contract |
|---------|--------------------|  
| Runtime resolution order | RAM cache → MBTiles → lower-zoom fallback → online → placeholder |
| Coverage tiers | T1 corridor, T2 metro, T3 prefecture, T4 national |
| Design rule | Coverage tiers define caching policy; runtime resolution is a separate concern |
| Archive access | All MBTiles archives opened as editable to support later tile writes |
| Expiry behavior | Cleanup clears metadata and RAM cache; MBTiles-on-disk tiles persist until explicit eviction (G2 scope) |
| Pure Dart core | `offline_tiles_core.dart` exports tile source types, coverage tiers, and cache config with zero Flutter imports |

### Map Viewport Contract

`map_viewport_bloc` defines the canonical viewport state machine for SNGNav and
other edge-developer map apps:

| Concept | Canonical contract |
|---------|--------------------|
| Camera modes | `follow`, `freeLook`, `overview` |
| Layer Z-order | Z0 `baseTile`, Z1 `route`, Z2 `fleet`, Z3 `hazard`, Z4 `weather`, Z5 `safety` |
| User-toggleable layers | Z1 through Z4 only |
| Non-toggleable layers | Z0 base tile, Z5 safety |
| Free-look return | Auto-return to `follow` after 10 seconds idle by default |
| Safety override | Safety-critical recentering may force `CameraMode.follow` |

The safety layer remains topmost at Z=5 and must never become user-toggleable.

---

## Test Conventions

- **File naming**: `lib/providers/foo.dart` → `test/providers/foo_test.dart`
- **Doc header**: every test file starts with `///` doc block + `library;` directive
- **Group structure**: one top-level `group()` per class
- **setUp/tearDown**: create and dispose subject in every group
- **No test interdependence**: each test is self-contained
- **Mocking**: `mocktail` for D-Bus/HTTP clients. `MockClient` from `package:http/testing.dart` for routing engines. Prefer constructor injection.
- **BLoC tests**: use `bloc_test` package for event → state assertions
- **Golden tests**: widget goldens in `test/widgets/goldens/`
- **Probe tests**: tagged `probe` — require live network APIs. **Never run in CI.** Use `@Tags(['probe'])` annotation.

### Test doc header template

```dart
/// ClassName unit tests — one-line summary.
///
/// Tests:
///   - Group: test name, test name, ...
///   - Group: test name, test name, ...
library;

import 'package:flutter_test/flutter_test.dart';
```

---

## Package Extraction (G1 → G2 → G3)

When extracting a domain model from the app into a reusable package:

### G1 — Create Package
1. Scaffold under `packages/your_package/` (lib/src/, test/, pubspec.yaml, README, CHANGELOG, LICENSE, analysis_options.yaml)
2. Choose the correct package track up front:
	- **Pure Dart**: no Flutter dependencies, maximizes platform reach.
	- **Flutter-track + `_core`**: allowed when the extracted surface is a BLoC or widget. Keep all pure Dart models in a separate `_core` barrel with zero Flutter imports.
3. Copy source into `lib/src/`. Fix imports to be package-internal.
4. Match the test stack to the package track: `package:test` for pure Dart, `flutter_test` and `bloc_test` when the package exports Flutter code.
5. For `navigation_safety`-style packages, preserve the domain contract in docs and tests: OODA budget `<200/<500/<300 ms`, SafetyOverlay Rules 1-5, Z=5 topmost overlay, and configurable severity thresholds.
6. For `map_viewport_bloc`-style packages, preserve the viewport contract in docs and tests: camera modes `follow/freeLook/overview`, canonical six-layer Z-order, user toggles restricted to Z1-Z4, default 10 second free-look auto-return, and safety-compatible return to `follow`.
7. For `routing_bloc`-style packages, preserve the route contract in docs and tests: 4-state lifecycle (`idle/loading/routeActive/error`), engine-agnostic injection via `routing_engine`, and glanceable route progress rendering without coupling to `navigation_safety` internals.
8. For `offline_tiles`-style packages, preserve the offline contract in docs and tests: five-level runtime resolution order (`RAM → MBTiles → lower-zoom fallback → online → placeholder`), four coverage tiers (`T1–T4`), separation between coverage policy and runtime resolution, editable archive access for later writes, and self-sufficient integration tests that generate temporary MBTiles fixtures.
9. Gate: analyze clean and `dart pub publish --dry-run` → **0 warnings**

### G2 — Migrate App
1. Add `your_package: path: packages/your_package` to root `pubspec.yaml`
2. Update barrel files (`lib/models/models.dart`, `lib/services/services.dart`, `lib/providers/providers.dart`) — replace inline exports with `export 'package:your_package/your_package.dart' show SpecificType;`
3. Update all `lib/` source files: change `import '../models/foo.dart'` → `import 'package:your_package/your_package.dart'`
4. Update all `test/` files: change `import 'package:sngnav_snow_scene/models/foo.dart'` → `import 'package:your_package/your_package.dart'`
5. Delete the original inline files from `lib/`
6. Gate: `flutter test --exclude-tags=probe` → **all pass**

### G3 — Publish
`dart pub publish`

**⚠️ REQUIRES EXPLICIT USER APPROVAL. Never auto-publish. Never run this command without the user saying "publish" or "go ahead with G3."**

---

## Agent Safety Boundaries

**You MUST NOT:**
- Run `dart pub publish` without explicit user approval
- Modify `SafetyOverlay` without user approval
- Modify BLoCs or widgets when adding a provider (stop and ask)
- Commit directly to `main` — use feature branches
- Skip `flutter analyze` before any commit
- Suppress or hide safety alerts
- Run probe tests (`--tags=probe`) without confirming network access with user
- Modify `lib/fluorite/` without user approval

**You SHOULD:**
- Run `flutter test --exclude-tags=probe` after every code change
- Run `flutter analyze --no-fatal-infos` before declaring work complete
- Report test count before and after your changes
- Reference [ARCHITECTURE.md](../ARCHITECTURE.md) for Five Guardians design details
- Reference [CONTRIBUTING.md](../CONTRIBUTING.md) for human-readable contribution guide
- Reference [EXTRACTING.md](../EXTRACTING.md) for full extraction history and examples
- Reference [SAFETY.md](../SAFETY.md) for ASIL-QM classification and safety rules
