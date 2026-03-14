# Roadmap

SNGNav is developed in structured sprints with governance checks at every close.
This document shows what has been built, what is in progress, and what comes next.

## Completed

### Foundation (March 2026)

- **10-package monorepo** — BLoC architecture, every provider swappable via `--dart-define`
- **963+ tests** passing across root and package suites (restructured from 1073 during package extraction)
- **Dead reckoning** — 4D Extended Kalman Filter (`kalman_dr` 0.2.0, [pub.dev](https://pub.dev/packages/kalman_dr))
- **Weather-aware driving conditions** — deterministic road surface classification (`driving_conditions` 0.2.0, [pub.dev](https://pub.dev/packages/driving_conditions))
- **Offline map tiles** — MBTiles (SQLite) with no network dependency
- **Privacy-first consent** — Jidoka model: UNKNOWN = DENIED, per-purpose, per-jurisdiction
- **Safety architecture** — display-only, ASIL-QM documented (see [SAFETY.md](SAFETY.md))
- **Developer onboarding** — `git clone` → `flutter run` on any Linux machine, no server required for default config

### Consolidation (March 2026)

- **All 10 packages at 0.2.0 on pub.dev** — version-harmonized ecosystem with aligned internal constraints
- **963 tests** passing across root and package suites (+243 in targeted density expansion)
- **Integrated example app** — `cd example && flutter run -d linux` demonstrates 5-package composition in one flow
- **Package integration patterns** — documented cross-package BLoC composition, provider override, and testing recipes
- **GeoClue hardening** — fault-tolerant location provider with graceful offline fallback

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

- [ ] **Voice guidance** — Flutter TTS integration for turn announcements and hazard warnings
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
