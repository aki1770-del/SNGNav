# Changelog

## 0.1.3 — 2026-07-11 — navigation_safety_core 0.11 compatibility (constraint widen)

- **Constraint widen (no source change):** `navigation_safety_core:
  ">=0.10.0 <0.12.0"` (was `^0.10.0`). The published `^0.10.0` constraint
  made this package a version-conflict blocker for any consumer taking the
  core 0.11 line (graded ja announcements, finite-position safety); the
  full test suite passes unchanged at BOTH bounds of the range — 12/12
  against 0.11.1 and 12/12 against the 0.10.0 floor (each resolved and run,
  not argued from source reading); the `AlertExplainer` / `DriverProfile` /
  `RoadSurfaceCondition` surface this package consumes is source-compatible
  across 0.10 → 0.11.
- **Mapping unchanged:** obstacle-class monitor events still map to the
  conservative `RoadSurfaceCondition.ice` advisory shape (caution-add-only).
  Core 0.11 introduces no obstacle-class vocabulary (`RoadSurfaceCondition`
  is VSS road-surface state by design), so the documented shim remains the
  closest available semantic; a dedicated obstacle-class advisory vocabulary
  in core remains the tracked future work that would retire the shim.

## 0.1.2

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.1 — 2026-05-10 — Pana score recovery (Theme α P3)

- Trim pubspec `description` to within the pana 60–180 character target.
- Add minimal `example/main.dart` for pana documentation scoring.
- Apply `dart format` to clear any formatter findings.
- No SDK source changes; metadata + format pass only.


## 0.1.0 — 2026-05-10 — Initial nav2 safety-layer composition

- `Nav2CollisionMonitorState` / `Nav2CollisionDetectorState` — Dart
  records mirroring `nav2_msgs/msg/CollisionMonitorState` and
  `nav2_msgs/msg/CollisionDetectorState` ROS 2 messages verbatim.
- `Nav2CollisionAction` — enum mirroring the upstream `uint8`
  action-type constants (DO_NOTHING / STOP / SLOWDOWN / APPROACH /
  LIMIT) with caution-add-only fallback for unknown values.
- `Nav2SafetyMapper` — static mapper from collision-monitor state
  events to `navigation_safety_core` `AlertExplainer` advisories.
- `Nav2SafetyLayer` — composition class with internal
  `AlertDensityThrottle` rate-limiting and a broadcast advisory
  stream the integrator's HMI can subscribe to.
- No transport lock-in: package depends only on
  `navigation_safety_core` + `equatable`. Integrators wire any
  ROS-Dart bridge (`roslibdart`, rosbridge over WebSocket, MQTT
  bridge, custom) to feed typed records into the layer.
- Tests construct typed records directly; no live bridge required.
