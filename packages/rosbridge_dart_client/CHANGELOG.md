# Changelog

## 0.1.1

- Republish from the embedded-target Dart 3.10.1 SDK (Flutter 3.38.3) to correct a stale
  `^3.11.0` SDK floor in the previously-published artifact. No source or behavior change; the
  source already declared `sdk: ^3.10.0`. Restores `pub get` for embedded/automotive Dart
  consumers on Dart 3.10.x.

## 0.1.0 — 2026-05-10 — Initial subscribe-only client

- `RosbridgeClient`: WebSocket client + subscribe Stream multiplexer.
  Connects to a `rosbridge_server` ROS 2 node and surfaces topic-
  subscribe streams as `Stream<Map<String, dynamic>>`. Caller maps
  the maps to typed records (e.g. via
  `Nav2CollisionMonitorState.fromJson` from `nav2_safety_layer`).
- `RosbridgeProtocolException` / `RosbridgeTransportException`:
  caller-side discriminable error types for server-reported
  protocol errors vs WebSocket transport-layer failures.
- Four supported `op` types: `subscribe` (outbound), `unsubscribe`
  (outbound on Stream cancel), `publish` (inbound topic message
  payload), `status` (inbound protocol notifications).
- Tests run against a synthetic in-process WebSocket channel
  (`StreamChannelMixin` + dev-only `stream_channel` dep); CI does not
  require a ROS bridge server.

### Out of scope for 0.1.0

- `op:publish` outbound (publish-to-topic from Dart) — deferred
- `op:call_service` (service calls) — deferred
- `op:advertise` / `op:unadvertise` — deferred
- Action goals / action clients — deferred
- PNG-compressed messages — deferred
- Authentication helpers — deferred (integrator wraps auth into the
  WebSocket connect URI if needed)
