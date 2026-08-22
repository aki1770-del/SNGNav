# nav2_safety_layer

> ## ⚠️ READ THIS FIRST — what this package could not tell you, until 0.2.0
>
> Up to **0.1.4**, when the nav2 Collision Monitor sent this package a message it could not
> read, it told you **nothing** — byte-identical to what a quiet, healthy monitor produces.
> An absent `action_type`, an action code newer than this package, an absent `detections`
> array, or a `polygons`/`detections` length mismatch each resolved to the benign answer.
> **You could not distinguish "all clear" from "I could not read the message."**
>
> ⚑ **`0.1.0`, `0.1.2` and `0.1.3` shipped with no `SAFETY_BOUNDARY.md` and no defect-proof
> test at all.** The disclosure landed in `0.1.4`, on 2026-08-21 — months after the defect.
> If you installed before that, nothing in the package told you. That is on us, and it is
> why this banner is on the README rather than in a file pub.dev does not render.
>
> **0.2.0 repairs all four** (PI-01..PI-04). Migrating:
>
> * `Nav2CollisionAction` gains `unreadable`. **A `switch` with `default:` still compiles**
>   and will silently route it into that branch — check every one.
> * `anyDetection` is now `bool?`. Use **`anyDetection == true`**, never `?? false`; `?? false`
>   re-creates the defect in your code.
>
> **This package is still an advisory formatter, not a safety component.** It has no failure
> channel of its own, and silence on `advisories` is still not an all-clear — the detector
> path emits no advisory by construction (`SAFETY_BOUNDARY.md`, BI-8 / AoU-1).

[![pub package](https://img.shields.io/pub/v/nav2_safety_layer.svg)](https://pub.dev/packages/nav2_safety_layer)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

Pure-Dart bridge layering
[`navigation_safety_core`](https://pub.dev/packages/navigation_safety_core)
driver-cognition primitives over the ROS 2 Navigation Stack
([`nav2`](https://github.com/ros-navigation/navigation2)) Collision
Monitor and Collision Detector state messages. **No transport lock-in.**
The integrator wires any ROS-Dart bridge of choice (`roslibdart`,
rosbridge over WebSocket, MQTT bridge, custom Dart wrapper) and pushes
typed records into the layer.

## Why this package exists

A driver-assist app built on the ROS 2 Navigation Stack already has
nav2's Collision Monitor and Collision Detector publishing action-class
state every cycle. An integrator building a nav2-based ROS 2 + Flutter
dashboard ends up handcoding the same polygon-name + action-type →
driver-cognition mapping every time. This package centralizes that
mapping with a caution-add-only invariant and a profile-tuned density
throttle so the driver in unexpected snow does not face alert-fatigue
from a chatty monitor.

### Driver impact chain (≤4 hops)

```
nav2 Collision Monitor / Detector node (ROS 2)
  -> integrator's ROS-Dart bridge (roslibdart, rosbridge, etc.)
    -> Nav2SafetyLayer (this package)
      -> driver in unexpected snow on a nav2-stack-served vehicle
```

Four hops, with the driver as the terminal beneficiary.

## Quick start

### a. Install + import

```yaml
dependencies:
  nav2_safety_layer: ^0.2.0
  navigation_safety_core: ^0.11.0  # 0.10.x also supported (>=0.10.0 <0.12.0)
  # plus the ROS-Dart bridge of your choice
```

```dart
import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
```

### b. Wire the layer to your bridge's stream

```dart
final layer = Nav2SafetyLayer(
  profile: DriverProfile.snowZoneExperienced,
  throttle: AlertDensityThrottle.forProfile(DriverProfile.snowZoneExperienced),
);

// Subscribe to advisory strings the HMI surfaces:
layer.advisories.listen((advisory) {
  // surface to driver via your HMI
});

// Wire nav2's CollisionMonitorState topic via your ROS-Dart bridge:
//   bridge.subscribe('/collision_monitor/state', (rawJson) {
//     layer.onMonitorState(Nav2CollisionMonitorState.fromJson(rawJson));
//   });
//   bridge.subscribe('/collision_detector/state', (rawJson) {
//     layer.onDetectorState(Nav2CollisionDetectorState.fromJson(rawJson));
//   });
```

### c. Map without rate-limiting

If the integrator already has its own throttle / dedup pipeline, the
mapper can be used statically without a layer:

```dart
// oracle:placeholders state
// `state` is the Nav2CollisionMonitorState you decoded from your own rosbridge
// / roslibdart subscription — the transport this package deliberately does not
// own (SAFETY_BOUNDARY BI-1).
final advisory = Nav2SafetyMapper.toAdvisory(
  state,
  DriverProfile.snowZoneExperienced,
); // null when state.actionType == doNothing
```

## Mapping discipline

- **Caution-add-only invariant.** Unknown `action_type` integers
  degrade to `Nav2CollisionAction.doNothing` rather than asserting a
  specific behavior the publisher did not intend.
- **Verbatim relay (Article 17 β), on the DETECTOR path only.** Polygon
  names from the publisher are surfaced verbatim in the advisory body by
  `onDetectorState`. ⚑ `onMonitorState` does **not** relay
  `polygon_name`; corrected 2026-08-21, where this bullet had claimed
  both paths without qualification.
- **Profile-tuned density throttle.** The integrator chooses the
  throttle's cap class via `AlertDensityThrottle.forProfile(...)`; the
  default literature-anchored caps in `navigation_safety_core` apply.

## Standards mapping

| Standard | Mapping |
|---|---|
| **SAE J3016** | L0 / L1 supportive. **No L2+ claim.** Advisories inform; the driver decides. |
| **ISO 26262** | Product-quality scope at the package boundary. The integrator performs the hazard analysis at the closed-loop boundary. |
| **JIS / JASO** | Not mapped at this scope. |

## What this is NOT

- **Not a ROS-Dart bridge.** This package does not implement
  rosbridge, MQTT, or any other transport. The integrator supplies
  the bridge.
- **Not a control surface.** Advisory strings are driver-facing
  language; the package does not actuate the vehicle.
- **Not an L2+ automation or handover-class supervision package.**
- **Not a polygon authoring tool.** Polygon names come from the
  upstream nav2 Collision Monitor / Collision Detector configuration;
  this package preserves them verbatim, it does not author them.

## License

BSD-3-Clause. See [`LICENSE`](LICENSE).
