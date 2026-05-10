# SAFETY_BOUNDARY — rosbridge_dart_client

## What this package does

`rosbridge_dart_client` is a **subscribe-only** WebSocket client for
the rosbridge_suite JSON protocol. It connects to a `rosbridge_server`
ROS 2 node, subscribes to topics the integrator names, and surfaces
the topic message stream as `Stream<Map<String, dynamic>>`.

## What this package does NOT do

- **Does not publish to ROS 2 topics from Dart.** No `op:publish`
  outbound; no `op:advertise`. The integrator wires actuator-class
  message authoring (if needed) through a different surface.
- **Does not call ROS 2 services.** No `op:call_service`. Service
  calls are deferred to a future minor version when integrator demand
  surfaces.
- **Does not send action goals.** No action client surface.
- **Does not author or relay any control input** to the vehicle —
  steering, braking, accelerator, transmission, or any other actuator.
  The package returns inbound topic message payloads as decoded JSON
  maps; what the consumer does with those maps is integrator-class.
- **Does not take over the dynamic driving task.** Per SAE J3016, the
  package operates at L0 / L1 supportive scope only — and only via the
  consumer's downstream HMI surface, not at the package boundary.
- **Does not assert a functional-safety case.** No ISO 26262 ASIL
  classification is claimed at the package boundary. The integrator
  performs the hazard analysis at the closed-loop boundary.
- **Does not vouch for ROS 2 message accuracy.** The package preserves
  the publisher's JSON `msg` payload verbatim. Whether the publisher's
  message is accurate, fresh, or complete is the publisher's question,
  not this client's.
- **Does not handle authentication.** The integrator wraps any auth
  needed (Authorization header, TLS client cert) into the WebSocket
  connect URI or its underlying transport.
- **Does not buffer messages across reconnects.** Topics that lose
  their subscription via transport-error must be re-subscribed.

## Caution-add-only invariant

The client is read-only at the ROS 2 layer — it issues no actuator
commands. Subscribe-only is the discipline; expanding to publish /
service / action is deferred until an explicit caller need surfaces
and the SAFETY_BOUNDARY for that surface is documented at version
bump time.

## Compound-failure surface

If the WebSocket transport fails (server unreachable, connection
closed by server, frame decode failure), the per-topic subscribe
Stream emits a `RosbridgeTransportException` and closes. The
integrator decides reconnect / cache / fallback policy at the
application layer; the client does not auto-reconnect because
subscribe-time semantics differ between integrators.

In a §12 worst-case scenario where the rosbridge_server itself is
unreachable (e.g., ROS 2 system has crashed), this package will
surface the failure rather than mask it. Drivers downstream of an
integrator using this client must rely on integrator-side fallback
policy (cached state, alternate sensor source, etc.).

## Driver retains authority

Every output of this package is informational. The driver (downstream
of the consuming app's HMI) retains full authority over braking,
steering, lane choice, and routing. The client does not encode any
handover, take-over-request, or minimum-risk-manoeuvre fallback
because none of those are within its scope.
