# rosbridge_dart_client

[![pub package](https://img.shields.io/pub/v/rosbridge_dart_client.svg)](https://pub.dev/packages/rosbridge_dart_client)
[![License: BSD-3-Clause](https://img.shields.io/badge/license-BSD--3--Clause-blue.svg)](https://github.com/aki1770-del/SNGNav/blob/main/LICENSE)

Subscribe-only Dart client for the
[`rosbridge_suite`](https://github.com/RobotWebTools/rosbridge_suite)
JSON-over-WebSocket protocol. Connects to a `rosbridge_server` ROS 2
node and surfaces topic-subscribe streams as
`Stream<Map<String, dynamic>>`. Pure Dart, no transport-layer lock-in.

## Why this package exists

A driver-assist app built on the ROS 2 Navigation Stack already has
nav2 nodes publishing safety state on ROS 2 topics. To consume those
streams from a Dart / Flutter app, the integrator needs a
`rosbridge_server` bridge node + a Dart-side WebSocket client. This
package fills the Dart-side client with a **subscribe-only minimum
scope**: enough to consume nav2 collision-state topics through
`nav2_safety_layer` without authoring the protocol layer.

### Driver impact chain (≤4 hops)

```
ROS 2 Navigation Stack node (e.g. nav2 Collision Monitor)
  -> rosbridge_server WebSocket bridge
    -> RosbridgeClient (this package; subscribe-only)
      -> integrator HMI (composing nav2_safety_layer for advisories)
        -> driver in unexpected snow
```

Four hops, with the driver as the terminal beneficiary.

## Quick start

### a. Install + import

```yaml
dependencies:
  rosbridge_dart_client: ^0.1.0
```

```dart
import 'package:rosbridge_dart_client/rosbridge_dart_client.dart';
```

### b. Connect + subscribe

```dart
final client = RosbridgeClient(uri: Uri.parse('ws://localhost:9090'));
await client.connect();

final sub = client.subscribe(
  topic: '/collision_monitor/state',
  type: 'nav2_msgs/msg/CollisionMonitorState',
).listen((json) {
  print('Got collision-monitor state: $json');
  // map json to typed record via Nav2CollisionMonitorState.fromJson
  // from the nav2_safety_layer package
});

// later — close the connection
await client.close();
```

### c. Compose with nav2_safety_layer

```dart
import 'package:nav2_safety_layer/nav2_safety_layer.dart';
import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:rosbridge_dart_client/rosbridge_dart_client.dart';

final ros = RosbridgeClient(uri: Uri.parse('ws://localhost:9090'));
await ros.connect();

final layer = Nav2SafetyLayer(
  profile: DriverProfile.snowZoneExperienced,
  throttle: AlertDensityThrottle(alertsPerMinuteCap: 60),
);
layer.advisories.listen((advisory) => print('Advisory: $advisory'));

ros.subscribe(
  topic: '/collision_monitor/state',
  type: 'nav2_msgs/msg/CollisionMonitorState',
).listen((json) {
  layer.onMonitorState(Nav2CollisionMonitorState.fromJson(json));
});
```

That's the 3-package full chain.

## Out of scope for 0.1.0

This package ships a **deliberately minimum scope** so the surface
stays auditable:

- `op:publish` outbound (publish-to-topic from Dart) — not supported
- `op:call_service` (service calls) — not supported
- `op:advertise` / `op:unadvertise` — not supported
- Action goals / action clients — not supported
- PNG-compressed messages — not supported
- Authentication helpers — not built-in; integrator wraps auth into
  the WebSocket connect URI if needed

When integrator demand for these surfaces materializes, they will be
added in subsequent minor versions without breaking the 0.1.0
subscribe surface.

## What this is NOT

- **Not a `roslibdart` replacement.** This package targets a specific
  consumer pattern (subscribe-only consumption of typed ROS 2 message
  streams) rather than the full `roslibdart` surface (publish, service,
  action). Integrators wanting publish or service surfaces wire a
  different bridge.
- **Not a `rosbridge_server`.** This is the Dart-side client only.
  The integrator runs `rosbridge_server` on their ROS 2 system.
- **Not an L2+ automation or control surface.** Subscribe-only — no
  outbound actuator messages.
- **Not a typed message decoder.** The Stream returns
  `Map<String, dynamic>` — caller maps to typed records (e.g. via
  `Nav2CollisionMonitorState.fromJson` from `nav2_safety_layer`).

## License

BSD-3-Clause. See [`LICENSE`](LICENSE).
