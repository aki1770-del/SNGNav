/// rosbridge_dart_client — subscribe-only Dart client for the
/// rosbridge_suite JSON-over-WebSocket protocol.
///
/// Connects to a `rosbridge_server` ROS 2 node and surfaces topic-
/// subscribe streams as `Stream<Map<String, dynamic>>`. Caller maps
/// the maps to typed records — for example, via
/// `Nav2CollisionMonitorState.fromJson` from the `nav2_safety_layer`
/// package.
///
/// HER-trace (≤4-hop) end-to-end:
///   ROS 2 Navigation Stack node (e.g. nav2 Collision Monitor)
///     -> rosbridge_server WebSocket bridge
///       -> RosbridgeClient (this package; subscribe-only)
///         -> integrator HMI (composing nav2_safety_layer for
///            navigation_safety_core driver-cognition advisories)
///           -> driver in unexpected snow
/// 4 hops, with the driver as the terminal beneficiary.
///
/// **Status: 0.1.0 ships subscribe-only minimum scope.** Out of
/// scope this version: publish-to-topic (`op:publish` outbound),
/// service calls (`op:call_service`), advertise / unadvertise, action
/// goals, PNG-compressed messages, authentication helpers. The four
/// in-scope ops are `subscribe` (outbound), `unsubscribe` (outbound on
/// Stream cancel), `publish` (inbound topic message payload), and
/// `status` (inbound protocol notifications).
///
/// Surface published in this package:
/// - [RosbridgeClient] — WebSocket client + subscribe Stream
///   multiplexer.
/// - [RosbridgeProtocolException] — server-reported `op:status` with
///   `level:error`.
/// - [RosbridgeTransportException] — WebSocket transport-layer error.
library;

export 'src/rosbridge_client.dart';
export 'src/rosbridge_exceptions.dart';
