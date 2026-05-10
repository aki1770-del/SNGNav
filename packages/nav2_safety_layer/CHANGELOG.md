# Changelog

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
