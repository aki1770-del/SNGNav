# Roadmap

SNGNav is developed in structured sprints with governance checks at every close.
This document shows what has been built, what is in progress, and what comes next.

## Completed

### Foundation (March 2026)

- **11-package monorepo** — BLoC architecture, every provider swappable via `--dart-define`
- **1005+ tests** passing across root and package suites
- **Dead reckoning** — 4D Extended Kalman Filter (`kalman_dr` 0.2.0, [pub.dev](https://pub.dev/packages/kalman_dr))
- **Weather-aware driving conditions** — deterministic road surface classification (`driving_conditions` 0.2.0, [pub.dev](https://pub.dev/packages/driving_conditions))
- **Offline map tiles** — MBTiles (SQLite) with no network dependency
- **Privacy-first consent** — Jidoka model: UNKNOWN = DENIED, per-purpose, per-jurisdiction
- **Safety architecture** — display-only, ASIL-QM documented (see [SAFETY.md](SAFETY.md))
- **Developer onboarding** — `git clone` → `flutter run` on any Linux machine, no server required for default config

### Consolidation (March 2026)

- **All 11 packages at 0.3.0 on pub.dev** — version-harmonized ecosystem with aligned internal constraints
- **1005 tests** passing across root and 11 package suites
- **Integrated example app** — `cd example && flutter run -d linux` demonstrates 5-package composition in one flow
- **Package integration patterns** — documented cross-package BLoC composition, provider override, and testing recipes
- **GeoClue hardening** — fault-tolerant location provider with graceful offline fallback

### Current State (April 2026)

- **15-package monorepo** — grew from 11 to 15 since March 2026 (added: `adaptive_reroute`, `route_condition_forecast`, `snow_rendering`, `navigation_safety_core`)
- **~1625 tests** passing across root and all 15 package suites (count drifts as the suite grows; per the 2026-04-25 review P2 finding, a future PR will replace the hardcoded number with a CI-generated badge)
- **Package versions** — independent per package, no longer harmonized at a single version:

  | Package | Version | Package | Version |
  |---|---|---|---|
  | `kalman_dr` | 0.3.0 | `routing_engine` | 0.3.0 |
  | `driving_conditions` | 0.5.0 | `routing_bloc` | 0.3.0 |
  | `driving_consent` | 0.3.0 | `map_viewport_bloc` | 0.3.0 |
  | `driving_weather` | 0.3.0 | `voice_guidance` | 0.3.0 |
  | `fleet_hazard` | 0.3.0 | `offline_tiles` | 0.4.0 |
  | `navigation_safety` | 0.6.0 | `navigation_safety_core` | 0.1.0 |
  | `adaptive_reroute` | 0.1.0 | `snow_rendering` | 0.1.0 |
  | `route_condition_forecast` | 0.1.0 | | |

- **App version**: 0.4.0
- **CI**: 3-job matrix (Analyze + Test + Build Linux), Flutter pinned to 3.41.4 (per OPS-RULE-042 governance)

### Documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) — package composition, provider chain, BLoC event flow
- [SAFETY.md](SAFETY.md) — regulatory awareness (EU AI Act, ISO 26262, SOTIF, R155/R156)
- [DEVELOPERS_GUIDE.md](DEVELOPERS_GUIDE.md) — developer onboarding and testing guide
- [BENCHMARKS.md](BENCHMARKS.md) — routing engine performance analysis
- Package READMEs with install instructions, API examples, and integration-pattern snippets on pub.dev
- [example/README.md](example/README.md) — 5-step demo flow for the integrated example app

## In Progress

- **Content distribution** — technical article and thread series on the architecture and regulatory positioning
- **Community building** — monitoring engagement, responding to feedback

## Near-Term

- [x] **Local routing deployment guide** — OSRM + Valhalla via Docker, Chūbu region, Raspberry Pi notes (see [docs/local_routing.md](docs/local_routing.md))
- [ ] **Conference submission** — submit abstract to embedded Linux or automotive open-source events (FOSDEM, ELC, AGL)
- [x] **Package usage examples** — richer examples in pub.dev READMEs showing integration patterns

## Strategic

- [x] **Voice guidance** — Flutter TTS integration for turn announcements and hazard warnings (`voice_guidance` 0.3.0)
- [ ] **Real-world validation** — field testing with actual GPS hardware and winter driving conditions
- [ ] **3D visualization** — elevation-aware rendering (current foundation is 2D)
- [ ] **Additional routing engines** — GraphHopper, custom OSRM profiles for winter conditions

## Non-Goals

These are intentional architectural boundaries, not missing features:

- **No AI/ML inference** — road surface classification is deterministic. This is a regulatory advantage, not a limitation.
- **No cloud dependency** — the architecture is offline-first by design. Connectivity is optional.
- **No vehicle actuation** — SNGNav is display-only. It informs the driver; it does not control the vehicle.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for development setup and testing guidelines.
BSD-3-Clause — contributions welcome.
