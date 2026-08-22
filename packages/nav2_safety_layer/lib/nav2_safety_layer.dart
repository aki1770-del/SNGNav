/// nav2_safety_layer — Pure-Dart bridge layering
/// `navigation_safety_core` driver-cognition primitives over the
/// ROS 2 Navigation Stack (nav2) Collision Monitor and Collision
/// Detector state messages.
///
/// **No transport lock-in.** This package does NOT depend on a
/// specific ROS-Dart bridge (`roslibdart`, rosbridge over WebSocket,
/// MQTT bridge, custom Dart wrapper). The integrator wires their
/// bridge of choice and pushes typed [Nav2CollisionMonitorState] /
/// [Nav2CollisionDetectorState] events into [Nav2SafetyLayer].
///
/// HER-trace (≤4-hop) end-to-end:
///   nav2 Collision Monitor / Detector node (ROS 2)
///     -> integrator's ROS-Dart bridge (roslibdart, etc.)
///       -> Nav2SafetyLayer (this package; mapping + density throttle)
///         -> driver in unexpected snow on a nav2-stack-served vehicle.
/// 4 hops, with the driver as the terminal beneficiary.
///
/// Why this package exists. nav2's Collision Monitor and Collision
/// Detector publish action-class state every cycle; an integrator
/// building a nav2-based ROS 2 + Flutter dashboard for a driving-
/// support vehicle ends up handcoding the polygon-name + action-type
/// → driver-cognition mapping every time. This package centralizes
/// that mapping with a caution-add-only invariant and a profile-
/// tuned density throttle so the driver in unexpected snow does not
/// face alert-fatigue from a chatty monitor.
///
/// Surface published in this package:
/// - [Nav2CollisionMonitorState] — Dart record mirroring
///   `nav2_msgs/msg/CollisionMonitorState`.
/// - [Nav2CollisionDetectorState] — Dart record mirroring
///   `nav2_msgs/msg/CollisionDetectorState`.
/// - [Nav2CollisionAction] — enum mirroring the upstream `uint8`
///   action-type constants (DO_NOTHING, STOP, SLOWDOWN, APPROACH,
///   LIMIT) verbatim.
/// - [Nav2SafetyMapper] — static mapping from nav2 state events to
///   `navigation_safety_core` driver-cognition advisories.
/// - [Nav2SafetyLayer] — composition layer that maps + density-
///   throttles the advisory stream the integrator's HMI surfaces.
library;

// DriverProfile is not an implementation detail: it is a REQUIRED constructor
// parameter of Nav2SafetyLayer (src/nav2_safety_layer.dart:26) and an argument
// of Nav2SafetyMapper.toAdvisory. Up to 0.1.4 this library exported everything
// except the type a reader needs to call it — so the first example in our own
// README did not compile for anyone who copied it (L35 snippet oracle,
// 2026-08-23). AlertSeverity travels with it: severityOf returns one.
export 'package:navigation_safety_core/navigation_safety_core.dart'
    show DriverProfile, AlertSeverity, AlertDensityThrottle, AlertExplainer;
export 'src/nav2_collision_msgs.dart';
export 'src/nav2_safety_layer.dart';
export 'src/nav2_safety_mapper.dart';
