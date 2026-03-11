# Changelog

## 0.1.1

- Added `example/main.dart` showing the engine-agnostic `RoutingEngine` API with a minimal example engine.
- Improved discoverability: added offline routing, local Valhalla keywords.
- Added `offline` topic.
- Added cross-links to sibling packages in README.
- Expanded README sibling links to the full 10-package SNGNav ecosystem.
- Added `ValhallaRoutingEngine.local()` helper and configurable timeouts.
- Set `ValhallaRoutingEngine.local()` to the canonical Machine E `localhost:8005` runtime.
- Added gated local Valhalla integration test and README instructions.
- Added `tool/valhalla_benchmark.dart` for exact-payload local/public latency measurement.

## 0.1.0

- Initial release.
- Abstract `RoutingEngine` interface for engine-agnostic routing.
- OSRM implementation: sub-frame latency (4.9ms for 10km queries).
- Valhalla implementation: multi-modal routing with Japanese language support.
- `RouteResult` model with maneuvers, geometry, distance, time, and engine info.
- `RouteRequest` with origin, destination, and optional waypoints.
- Engine identity via `EngineInfo` (name, version, query latency).
