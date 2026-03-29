# EXTRACTING.md — How to Extract a Package from SNGNav

A developer document. Not governance. Based on three published extractions and three live Flutter-track extractions.

## The Pattern

Every extraction follows **G1 → G2 → G3**:

| Gate | What | Pass criteria |
|:----:|-------|---------------|
| **G1** | Package exists, tests pass, pub.dev dry-run clean | `dart pub publish --dry-run` → 0 warnings |
| **G2** | App migrated to use the package, inline copies deleted | `flutter test --exclude-tags=probe` → all pass |
| **G3** | Published to pub.dev | `dart pub publish` → success |

## Before You Start

**Extraction candidates** must be:
- Either pure Dart, or Flutter-track with a pure Dart `_core` surface for reusable models
- Self-contained — no imports from `package:sngnav_snow_scene/`
- Tested — existing tests cover the code being extracted
- Unique on pub.dev — check that no good package already exists for this domain

**Track selection rule**:
- Use **pure Dart** when the extracted value is a model, service contract, parser, or algorithm.
- Use **Flutter-track + `_core`** when the extracted value is fundamentally a BLoC or widget package. Keep reusable data models in `your_package_core.dart` with zero Flutter imports.

## G1: Create the Package

### 1. Scaffold

```
packages/
  your_package/
    lib/
      src/
        model.dart
        provider.dart
      your_package.dart    ← barrel export
    test/
    pubspec.yaml
    README.md
    CHANGELOG.md
    LICENSE
    analysis_options.yaml
```

### 2. pubspec.yaml

```yaml
name: your_package
description: >-
  One-line description with search keywords.
  Second line adds context. State the track honestly: pure Dart or Flutter package with pure Dart core.
version: 0.1.0
repository: https://github.com/aki1770-del/sngnav
issue_tracker: https://github.com/aki1770-del/sngnav/issues
topics:
  - topic1
  - topic2
  - topic3

environment:
  sdk: ^3.11.0

dependencies:
  equatable: ^2.0.7    # if using value objects

dev_dependencies:
  test: ^1.25.0
  lints: ^5.1.1
```

**Topics**: max 5. Choose search terms an edge developer would type.

### 3. Copy source files

Copy from `lib/models/` and `lib/providers/` into `lib/src/`. Adjust imports to be package-internal (`import 'model.dart'` not `package:sngnav_snow_scene/...`).

### 4. Barrel export

```dart
// lib/your_package.dart
export 'src/model.dart';
export 'src/provider.dart';
```

### 5. Copy and adapt tests

Copy relevant tests from `test/`. Change imports to `package:your_package/your_package.dart`.

### 6. README.md

Write for a stranger. Include:
- What it does (one paragraph)
- Install (`dart pub add your_package`)
- Quick example (< 20 lines)
- API summary table
- License

### 7. Validate G1

```bash
cd packages/your_package
dart pub get       # or flutter pub get for Flutter-track packages
dart test          # pure Dart package
flutter test       # Flutter-track package
dart analyze       # pure Dart package
flutter analyze    # Flutter-track package
dart pub publish --dry-run   # 0 warnings
```

**G1 passes when**: 0 warnings on dry-run, all tests green.

### Flutter-track pattern-setter notes

`navigation_safety` established the first approved Flutter-track extraction pattern:

- full package barrel for BLoC + widget API
- separate `navigation_safety_core.dart` barrel for pure Dart models
- package README includes explicit ASIL-QM, advisory-only language
- package tests verify OODA budget documentation and SafetyOverlay Rules 1-5 behavior indirectly through state/widget coverage

`map_viewport_bloc` extends that pattern for viewport coordination packages:

- full package barrel for `MapBloc`, events, and state
- separate `map_viewport_bloc_core.dart` barrel for pure Dart viewport models
- package README includes the canonical camera modes and Z0-Z5 layer contract
- package tests verify user-toggle restrictions (Z1-Z4 only), free-look timeout behavior, and safety-compatible return to `follow`

`routing_bloc` extends the same pattern for route lifecycle packages:

- full package barrel for `RoutingBloc`, events, state, and route progress widgets
- separate `routing_bloc_core.dart` barrel for pure Dart route lifecycle models
- package README includes explicit 4-state contract and route glanceability posture
- package tests verify route lifecycle transitions and maneuver/progress UI rendering

`offline_tiles` extends the same pattern for offline tile management packages:

- full package barrel for `OfflineTileManager`, `OfflineTileProvider`, and resolver
- separate `offline_tiles_core.dart` barrel for pure Dart tile source types, coverage tiers, and cache config
- package README includes explicit five-level runtime resolution order and four coverage tiers
- package tests generate temporary MBTiles fixtures at test time (no committed binary assets)
- integration tests verify archive creation, existing-archive writes, expiry cleanup, and RAM cache eviction

`driving_conditions` introduces the **pure Dart computation** pattern (Phase C):

- single barrel (no `_core` split needed — entire package is pure Dart)
- zero Flutter dependency — safe for CLI, server, and test harness use
- imports `SafetyScore` from `navigation_safety_core` (cross-package dependency, not duplication)
- README documents all formulas: decision tree, grip factors, opacity/blur, particle config, Monte Carlo
- 86 tests including boundary regression tests from in-flight review
- `publish_to: none` — internal monorepo package, not yet pub.dev-publishable

## G2: Migrate the App

### 1. Add path dependency

In the app's `pubspec.yaml`:

```yaml
dependencies:
  your_package:
    path: packages/your_package
```

### 2. Swap imports

In every file that imports the old inline code, replace:

```dart
// Before
import 'package:sngnav_snow_scene/models/model.dart';
import 'package:sngnav_snow_scene/providers/provider.dart';

// After
import 'package:your_package/your_package.dart';
```

**Find all consumers**:
```bash
grep -rn 'package:sngnav_snow_scene/.*your_file' lib/ test/
```

### 3. Clean barrel files

Remove the old exports from `lib/models/models.dart` and `lib/providers/providers.dart`.

### 4. Delete inline copies

Delete the original files from `lib/models/` and `lib/providers/`.

### 5. Validate G2

```bash
flutter pub get
flutter analyze           # no new errors
flutter test --exclude-tags=probe   # all pass
```

**Also verify zero residue**:
```bash
grep -RInE 'package:sngnav_snow_scene/.*(your_old_file)' lib/ test/
# Must return 0 matches
```

**G2 passes when**: all app tests pass, zero remaining inline imports.

## G3: Publish

```bash
cd packages/your_package
dart pub publish
```

Publisher: aki1770@gmail.com. After publish, update pubspec.yaml to use version constraint instead of path (for CI):

```yaml
# For local development, keep path:
your_package:
  path: packages/your_package

# For pub.dev consumers:
# your_package: ^0.1.0
```

## Extraction History

| # | Package | Sprint | Lines removed | Files deleted | Tests after |
|:-:|---------|:------:|:------------:|:------------:|:-----------:|
| 1 | kalman_dr | 44 | 1,074 | 5 | 908 |
| 2 | routing_engine | 44 | 730 | 4 | 908 |
| 3 | driving_weather | 45 | 535 | 4 | 902 |

**Cumulative**: 2,339 lines of inline duplication removed. 13 files deleted. 3 packages on pub.dev.

### Phase C — Pure Dart Computation

| # | Package | Sprint | New lines | Tests | Track |
|:-:|---------|:------:|:---------:|:-----:|:-----:|
| 7 | driving_conditions | 50 | ~350 | 53 | Pure Dart |

## Live Pattern-Setter In Progress

| Package | Sprint | Track | Gate reached | Evidence |
|---------|:------:|:-----:|:------------:|----------|
| navigation_safety | 48 | Flutter + `_core` | G3 complete | 53 package tests, 898 app tests, analyze clean, pub.dev 0.1.0 published |
| map_viewport_bloc | 48 | Flutter + `_core` | G3 complete | 45 package tests, 898 app tests, analyze clean, pub.dev 0.1.0 published |
| routing_bloc | 49 | Flutter + `_core` | G3 complete | 29 package tests, 898 app tests, analyze clean, pub.dev 0.1.0 published |
| offline_tiles | 49 | Flutter + `_core` | G3 complete | 19 package tests, 898 app tests, analyze clean, pub.dev 0.1.0 published |
| driving_conditions | 52 | Pure Dart | G3 complete | 105 package tests, 957 app tests, analyze clean, pub.dev 0.3.0 published (0.5.0 G1 ready — FleetConfidenceProvider + SimulationResult) |

## Discovery Checklist (post-publish)

After G3, verify discoverability:

- [ ] Search pub.dev for 3 terms a stranger would use — does your package appear?
- [ ] Description includes search keywords (not just technical terms)
- [ ] Topics are max 5, chosen for search volume
- [ ] README has install command, quick example, API table
- [ ] Cross-link to sibling packages in README (*"See also: kalman_dr, routing_engine, driving_weather, driving_consent, fleet_hazard, navigation_safety, map_viewport_bloc, routing_bloc, offline_tiles, voice_guidance, driving_conditions"*)

## Integration Coverage Matrix (Sprint 60)

Package extraction proves reusable surfaces. Integration evidence proves the surfaces still behave as one driver-assisting navigation system when recomposed in the app.

| Gap / flow | Evidence files | Current proof |
|:-----------|:---------------|:--------------|
| Weather → Safety bridge | `test/integration/weather_safety_bridge_integration_test.dart` | Hazard triggers, non-hazard guard rails, and message correctness |
| Fleet → Safety bridge | `test/integration/fleet_safety_bridge_integration_test.dart` | Icy vs snowy severity mapping and no false alerts for dry-only reports |
| Multi-hazard priority | `test/integration/multi_hazard_priority_integration_test.dart` | Critical fleet hazard overrides weather warning and cannot be downgraded by later warning input |
| Consent lifecycle → fleet listening | `test/widgets/snow_scene_scaffold_test.dart` | Fleet listening starts on grant and stops on revoke through widget-mediated coupling |
| Viewport coherence (follow ↔ freeLook) | `packages/map_viewport_bloc/test/bloc/map_bloc_test.dart`, `test/widgets/snow_scene_scaffold_test.dart` | User pan enters freeLook, timer returns to follow, and live positions recenter only while following |
| Offline tiles → route coverage correspondence | `lib/snow_scene.dart`, `packages/offline_tiles/test/integration/offline_tile_manager_test.dart` | Route waypoints are checked for local coverage and uncovered points are surfaced explicitly |
| Full Snow Scene chain | `test/integration/s52_flow_full_chain_test.dart`, `test/integration/snow_scene_demo_flow_test.dart` | Route, weather, navigation, map, consent, fleet, and demo flow remain coherent end-to-end |

Use this matrix when evaluating whether an extracted package still serves D3 after recomposition. A package that is publishable but not integration-proven is not yet fully trustworthy in the Snow Scene.
