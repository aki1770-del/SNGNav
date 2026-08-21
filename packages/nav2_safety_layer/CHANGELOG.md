# Changelog

## 0.1.4 — 2026-08-21 — an obstacle is no longer announced as road ice

**What 0.1.3 did, in plain words.** When the nav2 Collision Monitor reported that an
**object** was inside a configured polygon, this package told the driver the **road was
frozen**. Measured output on a well-formed `STOP`:

> 「凍結路面です。気温0°C以下で薄氷ができています。時速30km以下に減速し、急ブレーキは避けてください」
> *(Frozen road surface. Ice is forming below 0°C. Reduce to under 30 km/h and avoid braking hard.)*

The message carried **no temperature**, and the text fabricated one. Worse, it told the
driver to **avoid braking hard** while the monitor was commanding a **stop**. It was false
about a road she was on, and it inverted the instruction.

**⚑ 0.1.3's changelog told you this was correct.** It said the mapping *"remains the closest
available semantic."* **That sentence is withdrawn.** It was not the closest available
semantic: `RoadSurfaceCondition.unknown` already existed in the enum this package imports
(`road_surface_condition.dart:34` — *"Sensor cannot determine current road-surface state"*)
and was nearer in every respect. An assurance is worse than silence, because silence can be
discovered and an assurance is believed.

**What changed.** All four non-`DO_NOTHING` actions now map to `RoadSurfaceCondition.unknown`,
yielding 「路面状況不明。慎重に運転してください」 — which claims nothing about the surface,
because the message says nothing about the surface. Guarded by `BI-7`.

**Non-breaking.** No API changed. Anyone on `^0.1.3` receives this without editing a line.

**Also repaired in this line:** a nav2 `STOP` arriving after an advisory burst had consumed
the throttle cap was previously **dropped**. `severityOf` now maps `stop`/`approach` to
`AlertSeverity.critical`, which takes the throttle's non-negotiable critical-bypass. Guarded
by `BI-9`. `SAFETY_BOUNDARY.md` AoU-5 and AoU-6 both asserted the pre-repair behaviour and
are amended, with their previous text preserved in place.

### ⚑ What this release does NOT fix — read this before you rely on it

Four defects remain **live and proven**, each with a test that fails on purpose in the
`pinned-live` suite (run `dart test -t pinned-live`; they are reported in CI, never skipped):

| | still true of 0.1.4 |
|---|---|
| **PI-01** | a message **missing `action_type`** is read as `DO_NOTHING` — absence renders as "no action" |
| **PI-02** | an **unknown action code** is read as `DO_NOTHING` |
| **PI-03** | a message **missing `detections`** reports `anyDetection == false` |
| **PI-04** | `polygons` and `detections` of **different length** are absorbed as a shorter loop |
| **PI-05** | `STOP` and `LIMIT` remain **byte-identical in the advisory text**; read `state.actionType` yourself |
| **D-08** | the source comment claims `polygon_name` is relayed on the monitor path; **it is not** |

**Residual on the fix itself, stated not hidden:** `.unknown` is honest and still wrong in
**domain**. nav2 reported an *obstacle*; `RoadSurfaceCondition` has no obstacle member, so no
value in that enum can say what actually happened. The vocabulary gap is recorded, not closed.

**This package is QM. No ASIL is claimed and none can be inherited from here.** It has no
timeout, no staleness clock and no heartbeat (AoU-3), so it should not be the sole path for a
reflexive-stop architecture — the reason is liveness and QM scope, **not** a dropped STOP.

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
