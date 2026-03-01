# Changelog

## 0.1.0

- Initial release.
- Abstract `RoutingEngine` interface for engine-agnostic routing.
- OSRM implementation: sub-frame latency (4.9ms for 10km queries).
- Valhalla implementation: multi-modal routing with Japanese language support.
- `RouteResult` model with maneuvers, geometry, distance, time, and engine info.
- `RouteRequest` with origin, destination, and optional waypoints.
- Engine identity via `EngineInfo` (name, version, query latency).
