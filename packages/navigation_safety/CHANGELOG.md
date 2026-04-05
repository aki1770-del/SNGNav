# Changelog

## 0.5.0

### Breaking changes
- `NavigationStarted.route` is now `NavigationRoute` (was `RouteResult` from `routing_engine`)
- `RerouteCompleted.newRoute` is now `NavigationRoute` (was `RouteResult`)
- `NavigationState.route` is now `NavigationRoute?` (was `RouteResult?`)
- `NavigationState.currentManeuver` now returns `NavigationManeuver?` (was `RouteManeuver?`)
- `NavigationState.nextManeuver` now returns `NavigationManeuver?` (was `RouteManeuver?`)
- `routing_engine` is no longer a dependency of `navigation_safety`

### Added
- `NavigationRoute` — navigation layer route model (shape, maneuvers, totalDistanceKm, totalTimeSeconds, summary, eta)
- `NavigationManeuver` — navigation layer maneuver model (index, instruction, type, lengthKm, timeSeconds, position)

### Migration
Use `RouteResult.toNavigationRoute()` extension (in the main app's adapter) to convert at the boundary.

## 0.4.0

**BREAKING**: `NavigationSafetyConfig()` constructor is no longer `const`. Any `const NavigationSafetyConfig(...)` call site must remove the `const` keyword.

### Safety remediations (R4 review, April 2026)

- **G-01 (P0)**: `NavigationSafetyConfig` now throws `RangeError`/`ArgumentError` in all modes (including release) for out-of-range or inverted thresholds. Previously used `assert()` which is silently ignored in release builds.
- **G-02 (P0)**: `_canUpdateSeverity()` rewritten with explicit `const` priority map (`info:0, warning:1, critical:2`). No longer uses `AlertSeverity.index` — immune to enum reordering.
- **G-03 (P0)**: `RerouteCompleted` now passes `clearAlert: true`. Route-specific alerts no longer persist after the driver reroutes.
- **G-04 (P0)**: `SafetyOverlay` wraps non-dismissible alerts in `PopScope(canPop: false)`. Android back button and iOS swipe cannot bypass a critical non-dismissible alert.
- **G-05 (P1)**: Added `SafetyNavigationScaffold` — a convenience wrapper that places `SafetyOverlay` as the topmost `Stack` child, enforcing Z-order by construction rather than consumer contract.
- **G-06 (P1)**: `NavigationSafetyConfig` extends `Equatable`. Identical configs compare equal; eliminates unnecessary BLoC rebuilds on config change detection.
- **G-07 (P1)**: Debug-mode OODA latency logging — `_onSafetyAlert` records `Stopwatch` and prints a warning to console if BLoC processing exceeds 500 ms. No-op in release builds.
- **G-09 (P1)**: 27 new unit/bloc tests added (57 → 84 total). Covers: `AlertSeverity` ordinal invariants, `NavigationSafetyConfig` boundary validation, `SafetyScore` boundary (0.0 → critical, 1.0 → no alert), reroute alert clearing, non-dismissible alert persistence across navigation stop.

### Known deferred items (planned v0.5.0)

- **G-07**: OODA latency runtime enforcement (benchmark tests, hard limit) — deferred.
- **G-08**: `routing_engine` types (`RouteResult`, `RouteManeuver`) appear in `NavigationState`/`NavigationEvent` public API (D-SC22-4 known violation). Full fix (wrapper types) deferred to v0.5.0 pre-P2. Consumers must add `routing_engine` to their pubspec.

## 0.3.0

- Harmonize package version to 0.3.0 for Sprint 80 Direction F.
- Align internal ecosystem dependency constraints to ^0.3.0 where applicable.
- No breaking API changes in this package for this release.

