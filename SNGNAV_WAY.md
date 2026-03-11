# The SNGNav Way

**What we build. Why it qualifies. Where it goes next.**

---

## §1 What is SNGNav?

SNGNav is a **driver-assisting navigation architecture** and working reference
product that combines real-world fleet data with simulation to generate
high-density driver safety scores — and shows edge developers how to build
low-latency, map-aware, weather-relevant, consent-respecting navigation
assistance on-device.

Real-world data becomes a game-changer only when combined with simulation
data. A thousand simulated variants of a mountain-pass incident — varying
speed, tyre condition, road surface, visibility — identify which safety
metrics actually predict danger. This is why Fluorite's game engine heritage
is our strength: we harness simulation power to make driving safer.

**It is about safety scores that help every driver's daily life. It is NOT
about harvesting real crash data from every driver.**

**Who this is for**: edge developers — engineers who build real-time experiences
on embedded hardware at the boundary between the vehicle and the world. You
process on-device, not in the cloud. You collect data with consent, not by
default. You render at 60fps on ARM, not on a gaming GPU.

**Why we build this**: see [Why We Build](https://github.com/aki1770-del/sngnav/blob/main/docs/why_we_build.md)
(PHIL-001) — the philosophy document that traces from Sakichi Toyoda's loom
to the driver in an unexpected snowstorm.

---

## §2 The Five Principles

Every feature, package, and line of code in SNGNav must satisfy these five
principles. If it doesn't, it doesn't ship.

### 1. Offline-First

The system works when the network fails. GPS dies in a tunnel. The routing
server is unreachable. The weather API times out. SNGNav continues — with
dead reckoning, local tiles, cached routes, and stale-but-present weather
data. The driver never sees a blank screen.

**What this rules out**: any feature that requires a cloud connection to
function. If it can't degrade gracefully offline, it doesn't belong here.

### 2. Consent by Default

Data collection is deny-by-default, per-purpose, and revocable. The driver
explicitly allows each category of data sharing. Fleet telemetry, location
history, weather reports — none of these flow until the driver says yes.
And the driver can revoke at any time.

**What this rules out**: implicit data collection, opt-out consent models,
or any feature that assumes permission rather than requesting it.

### 3. Display-Only Safety Boundary

SNGNav is a navigation **display aid** classified ASIL-QM. It does not
control the vehicle. Dead reckoning positions are estimates — always shown
with an accuracy indicator. Safety alerts are advisory — never suppressed,
never hidden, never overridden by application logic.

**What this rules out**: steering, braking, ADAS integration, or any feature
that sends commands to vehicle systems.

### 4. Extractable Package Boundaries

Every domain boundary in SNGNav must be extractable into a reusable package.
Pure Dart packages stay pure Dart. Flutter-track packages are allowed when the
value is fundamentally a BLoC or widget surface, but their reusable models
must remain available through a pure Dart `_core` library with no Flutter
imports. No platform-specific code belongs in the data layer.

This means an edge developer can use `kalman_dr` in a Raspberry Pi CLI tool,
`driving_weather` in a server-side fleet manager, `navigation_safety_core`
or `map_viewport_bloc_core` without pulling in Flutter, or `offline_tiles_core`
for tile source models in a non-Flutter tile server — while still allowing a
Flutter app to reuse the full navigation safety, viewport BLoC, and offline
tile management packages.

**What this rules out**: core models that depend on Flutter widgets,
platform channels, or app-specific state management, and any Flutter-track
package that fails to preserve a pure Dart core where the domain needs one.

### 5. Evidence over Aspiration

We ship only what the test suite proves. Test counts evolve as the repo and
package portfolio evolve, so sprint-close validation is the authoritative
source. Every claim in every README is backed by a passing test, a benchmark
result, or a verified build. The chain is:
**Evidence → Contribution → Architecture → Edge Developer → Driver**.

**What this rules out**: speculative features, unverified performance claims,
or documentation that describes intent rather than reality.

---

## §3 What's In Scope

SNGNav covers five domains, each protected by a guardian subsystem:

| Domain | Guardian | What it does |
|--------|----------|-------------|
| **Position** | Dead Reckoning (Kalman filter) | Predicts location when GPS is lost |
| **Routing** | Local Routing (OSRM / Valhalla) | Calculates routes without cloud access |
| **Weather** | Weather Awareness | Monitors driving conditions (snow, ice, visibility) |
| **Consent** | Consent Lifecycle | Manages per-purpose, revocable data permissions |
| **Fleet** | Hazard Aggregation | Clusters fleet reports into hazard zones |
| **Simulation** | Safety Score Engine | Combines real-world data with simulated scenarios to generate high-density safety scores |

### Out of Scope

| Category | Reason |
|----------|--------|
| Vehicle control (steering, braking, ADAS) | ASIL-QM boundary — display only |
| Cloud-required features | Violates Principle 1 (Offline-First) |
| Proprietary SDK dependencies in core package logic | Violates Principle 4 (Extractable Package Boundaries) |
| Non-consensual data collection | Violates Principle 2 (Consent by Default) |

### The 3D and Simulation Frontier

SNGNav's foundation is 2D. The aspiration is a 3D scene layer and simulation
engine — weather conditions, road state, and vehicle telemetry rendered as a
real-time 3D experience, driven by thousands of simulated driving scenarios
that strengthen safety score density.

This depends on [Fluorite](https://fluorite.game), Toyota's Flutter-integrated
game engine. Fluorite capabilities — tyre pressure physics, road surface
simulation, real-time 3D rendering — are not decorative. They are the mechanism
by which simulation produces richer safety metrics than real incident data alone.

Three integration points are explicitly in scope:

- **filament_scene contributions**: dormancy is not death. When filament_scene
  opens for contributions, SNGNav's safety visualization use case provides
  concrete upstream value for edge developers. We cannot predict when it
  launches — we prepare so we are ready.
- **Embedded / ARM deployment**: the development machine (i7-12700H, 32 GB RAM,
  Linux) is Phase 2+ capable. Cross-compilation for RPi 5 and ARM targets is
  the upcoming deployment frontier.
- **3D scene layer**: when Fluorite's C++ repos become publicly available,
  `lib/fluorite/` becomes the integration point for rendering safety scores as
  glanceable 3D scenes.

Until then, SNGNav proves the data layer, the consent model, and the provider
architecture in 2D — so that the 3D transition is a rendering upgrade, not an
architectural rewrite.

---

## §4 The Package Portfolio

Ten extracted packages currently live in the SNGNav monorepo. Nine packages are
already published to [pub.dev](https://pub.dev). The four Flutter-track +
`_core` packages completed G3 publication in Sprint 51: `navigation_safety`,
`map_viewport_bloc`, `routing_bloc`, and `offline_tiles`. `driving_conditions`
remains internal-only by human decision because it currently depends on local
path-based package relationships.

| Package | Track | Status | What it models | Edge developer value |
|---------|:-----:|:------:|---------------|---------------------|
| [**kalman_dr**](https://pub.dev/packages/kalman_dr) | Pure Dart | Published | 4D Extended Kalman Filter for dead reckoning | Position continuity when GPS fails — tunnels, canyons, blizzards |
| [**routing_engine**](https://pub.dev/packages/routing_engine) | Pure Dart | Published | Abstract routing interface + OSRM/Valhalla implementations | Swap routing backends without touching app logic |
| [**driving_weather**](https://pub.dev/packages/driving_weather) | Pure Dart | Published | Weather conditions model (precipitation, visibility, ice risk) | No equivalent exists on pub.dev — unique positioning |
| [**driving_consent**](https://pub.dev/packages/driving_consent) | Pure Dart | Published | Consent lifecycle (record, category, manager) | No equivalent exists on pub.dev — privacy-first architecture |
| [**fleet_hazard**](https://pub.dev/packages/fleet_hazard) | Pure Dart | Published | Fleet reports, hazard zones, Haversine clustering | No equivalent exists on pub.dev — automotive fleet hazard API |
| [**navigation_safety**](https://pub.dev/packages/navigation_safety) | Flutter + `_core` | Published | Navigation BLoC, SafetyOverlay, and safety score models | Reusable safety session logic for Flutter navigation apps without giving up pure Dart model reuse |
| [**map_viewport_bloc**](https://pub.dev/packages/map_viewport_bloc) | Flutter + `_core` | Published | Map viewport BLoC, camera modes, layer visibility, and fit-to-bounds models | Reusable viewport state machine with canonical layer rules for Flutter navigation maps |
| [**routing_bloc**](https://pub.dev/packages/routing_bloc) | Flutter + `_core` | Published | Route lifecycle BLoC, route progress UI, and maneuver icon mapping | Reusable route-guidance state machine and glanceable route UI for Flutter navigation apps |
| [**offline_tiles**](https://pub.dev/packages/offline_tiles) | Flutter + `_core` | Published | Offline tile manager, runtime tile resolver, coverage tiers | Reusable offline tile management for any Flutter map app needing MBTiles + fallback |
| `driving_conditions` | Pure Dart | Extracted in repo (G1.5) | Road surface state, visibility degradation, precipitation config, driving condition assessment, Monte Carlo safety score simulation | Pure Dart computation models for weather-based driving safety — usable in CLI, server, or test harness without Flutter |

### Canonical Viewport Contract

`map_viewport_bloc` defines the current viewport contract for Phase A:

- Camera modes are `follow`, `freeLook`, and `overview`.
- Layer Z-order is fixed: Z0 base tile, Z1 route, Z2 fleet, Z3 hazard, Z4 weather, Z5 safety.
- Only Z1 through Z4 are user-toggleable.
- Z0 is foundational and Z5 is safety-critical, so neither is user-toggleable.
- `freeLook` returns to `follow` after 10 seconds idle by default.
- Safety-critical events may force a return to `follow`.

### Canonical Offline Tiles Contract

`offline_tiles` defines the canonical offline tile management contract for Phase B:

- Runtime resolution order: RAM cache → MBTiles → lower-zoom fallback → online → placeholder.
- Coverage tiers: T1 corridor, T2 metro, T3 prefecture, T4 national.
- Coverage tiers define caching policy; runtime resolution is a separate concern.
- Archives are opened as editable to support later writes.
- Expiry cleanup clears metadata and RAM cache; MBTiles-on-disk persistence is kept until explicit eviction.
- Pure Dart `_core` exports tile source types, coverage tiers, and cache config.

### Canonical Routing Contract

`routing_bloc` defines the current route lifecycle contract for Phase B:

- Lifecycle states are `idle`, `loading`, `routeActive`, and `error`.
- Route requests and engine checks are engine-agnostic through `routing_engine`.
- Route progress presentation is package-owned and data-driven.
- Route UI remains glanceable: instruction first, ETA/distance second.

`routing_bloc` has completed G2 app migration. `offline_tiles` has completed
G2 app migration. All four Flutter-track + `_core` packages have reached G2.

### Canonical Driving Conditions Contract

`driving_conditions` defines the canonical computation model contract for Phase C:

| Concept | Canonical contract |
|---------|--------------------|  
| Road surface states | `dry`, `wet`, `slush`, `compactedSnow`, `blackIce`, `standingWater` — each with grip factor |
| Decision tree | `RoadSurfaceState.fromCondition(WeatherCondition)` — iceRisk, temperature, precipitation type |
| Hysteresis filter | `HysteresisFilter<T>` — window=3, threshold=2, prevents rapid state oscillation |
| Visibility degradation | `opacity = 1.0 - clamp(v/1000, 0.1, 1.0)`, `blurSigma = clamp((500-v)/50, 0, 10)` |
| Precipitation config | `particleCount = (intensityFactor * 500).round()`, velocity/size/lifetime by type |
| Safety score simulation | Monte Carlo N-run with ±10% jitter, grip 0.4 + visibility 0.4 + fleet 0.2 weighted mean |
| SafetyScore origin | Imported from `navigation_safety_core`, not duplicated |
| Performance gate | 1,000 Monte Carlo runs < 200ms (measured: 5ms) |

### Extraction Method

Every package follows the **G1 → G2 → G3** pipeline:
- **G1**: Create package, write tests, `dart pub publish --dry-run` → 0 warnings
- **G2**: Migrate app to use package, delete inline copies, all tests pass
- **G3**: Publish to pub.dev

See [EXTRACTING.md](EXTRACTING.md) for the full method and history.

---

## §5 Roadmap — Candidate Areas

These are **candidates**, not commitments. The next extraction or feature
is selected by the project maintainer based on edge developer need and
architectural readiness.

### Candidate 1: Phase C Computation Models

`driving_conditions` has completed Phase C — the pure Dart computation model
extraction. Five algorithms and a Monte Carlo scaffold are packaged with 53 tests.
This completes L1 (all five extraction clusters packaged). Next is G3 publication
(human-controlled) or L2 Safety Score Simulation Framework advancement.

**Readiness**: Complete — G1.5 reached. All computation models extracted and
tested. Performance gate verified (5ms for 1,000 Monte Carlo runs). Cross-package
dependency on `navigation_safety_core` for `SafetyScore` verified clean.

### Candidate 2: Offline Tile Management

Guardian 2 (Offline Tiles) uses MBTiles with a five-level fallback (RAM cache
→ MBTiles → lower-zoom fallback → online → placeholder). This pattern is reusable
for any Flutter map app that needs offline capability.

**Readiness**: Complete — `offline_tiles` has reached G2 with 16 package tests,
872 app tests, clean analysis, and 0 publish warnings. Runtime resolution and
coverage tiers are separated. G3 publication remains human-controlled.

### Candidate 3: 3D Scene Layer (post-Fluorite)

When Fluorite's C++ repos become publicly available, the `lib/fluorite/`
scaffold becomes the integration point for 3D rendering of weather conditions,
road state, and vehicle telemetry. This is the architectural aspiration
described in §3.

**Readiness**: Blocked — waiting for Fluorite source publication. The Dart-side
scaffold (`FluoriteView`, `FluoriteApi`) exists and is tested.

---

## §6 How Decisions Are Made

Every proposed feature must trace to a single question:

> **"How can we help the driver when conditions are worst?"**

This traces through five invariants:

| # | Invariant | Filter question |
|:-:|-----------|----------------|
| D3 | **Purpose** (anchor) | Does this help a driver in unexpected snow? |
| D4 | **Sakichi** | Does this make the edge developer's life easier? |
| D1 | **Customer** | Is the edge developer the one we're serving? |
| D5 | **Chain** | Can we trace Evidence → Contribution → Architecture → Edge Developer → Driver? |
| D2 | **Product** | Does this fit a driver-assisting navigation architecture? |

If a proposed feature can't answer all five, it doesn't ship.

### Upstream Philosophy

SNGNav is a product expression of a broader philosophy:

- **WHY**: [Why We Build](https://github.com/aki1770-del/sngnav/blob/main/docs/why_we_build.md) (PHIL-001) — from Sakichi's loom to the driver in the snow
- **WHO**: The governance hierarchy traces from the human decision anchor through strategic intelligence to build execution
- **HOW**: [ARCHITECTURE.md](ARCHITECTURE.md) — Five Guardians, the provider system, offline-first design

The SNGNav Way is the **WHAT** — the product-level answer to "what qualifies as SNGNav."
