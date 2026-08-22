/// Dart records mirroring the `nav2_msgs/msg/CollisionMonitorState`
/// and `nav2_msgs/msg/CollisionDetectorState` ROS 2 message shapes
/// published by the ROS 2 Navigation Stack (nav2) Collision Monitor
/// and Collision Detector nodes.
///
/// Field-name mapping is verbatim from the upstream `.msg` files at
/// `github.com/ros-navigation/navigation2/tree/main/nav2_msgs/msg`
/// (snake_case in ROS → camelCase in Dart, semantics unchanged).
///
/// This package does NOT depend on a specific ROS-Dart bridge
/// (`roslibdart`, `rosbridge`, MQTT bridge, etc.). The integrator
/// wires their bridge of choice to construct these records and pass
/// them to [Nav2SafetyMapper].
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';
import 'package:equatable/equatable.dart';

/// Action codes published by the nav2 Collision Monitor on the
/// `CollisionMonitorState` message — verbatim from the upstream
/// `.msg` constant block.
enum Nav2CollisionAction {
  /// `DO_NOTHING=0` — no action; monitor sees no triggered polygon.
  doNothing,

  /// `STOP=1` — stop the robot; closest collision-class polygon
  /// triggered.
  stop,

  /// `SLOWDOWN=2` — slow down to a percentage of current operating
  /// speed.
  slowdown,

  /// `APPROACH=3` — keep a constant time-to-collision interval.
  approach,

  /// `LIMIT=4` — set a velocity limit when points are in range.
  limit,

  /// **Not a nav2 value.** The publisher's `action_type` was absent, or
  /// carried a code this package does not know.
  ///
  /// `unreadable` means NOT KNOWN. It never means "no action". Up to 0.1.4
  /// both cases mapped to [doNothing] — so a truncated frame, or a nav2
  /// release adding a sixth action code, read as "the monitor wants nothing
  /// done" while the monitor may have been publishing STOP. Absence resolving
  /// to the benign branch is the one error a collision channel must not make;
  /// the contract already existed in our own catalog, in `driving_weather`'s
  /// WeatherCondition ("Nothing was measured... It is NOT 'the road is
  /// clear'"), and was never applied here.
  unreadable;

  /// Maps the publisher's `uint8` value to the enum. Returns
  /// [unreadable] for any code this package does not know — never
  /// [doNothing], which is a value nav2 actively publishes and must not be
  /// synthesised on our side.
  static Nav2CollisionAction fromInt(int v) {
    switch (v) {
      case 0:
        return Nav2CollisionAction.doNothing;
      case 1:
        return Nav2CollisionAction.stop;
      case 2:
        return Nav2CollisionAction.slowdown;
      case 3:
        return Nav2CollisionAction.approach;
      case 4:
        return Nav2CollisionAction.limit;
      default:
        return Nav2CollisionAction.unreadable;
    }
  }
}

/// `nav2_msgs/msg/CollisionMonitorState` — Collision Monitor state
/// snapshot.
class Nav2CollisionMonitorState extends Equatable {
  /// `action_type` — the action the monitor is requesting.
  final Nav2CollisionAction actionType;

  /// `polygon_name` — name of the triggered polygon (empty when
  /// `actionType` is [Nav2CollisionAction.doNothing]).
  final String polygonName;

  const Nav2CollisionMonitorState({
    required this.actionType,
    required this.polygonName,
  });

  /// Construct from the publisher's JSON shape (rosbridge / roslibdart
  /// dispatch typically delivers messages as JSON-encoded maps).
  factory Nav2CollisionMonitorState.fromJson(Map<String, dynamic> json) {
    return Nav2CollisionMonitorState(
      // An ABSENT action_type is unreadable, not DO_NOTHING. `?? 0` here
      // manufactured a nav2 value the publisher never sent.
      actionType: json['action_type'] is int
          ? Nav2CollisionAction.fromInt(json['action_type'] as int)
          : Nav2CollisionAction.unreadable,
      polygonName: (json['polygon_name'] as String?) ?? '',
    );
  }

  @override
  List<Object?> get props => [actionType, polygonName];
}

/// `nav2_msgs/msg/CollisionDetectorState` — Collision Detector state
/// snapshot. Per polygon, whether a detection is active.
class Nav2CollisionDetectorState extends Equatable {
  /// `polygons` — names of the configured polygons.
  final List<String> polygons;

  /// `detections` — parallel-indexed detection booleans.
  final List<bool> detections;

  /// False when the publisher's message could not be read as a coherent
  /// polygon/detection pairing — `detections` absent, or its length not
  /// matching `polygons`. An unreadable state holds NO pairs; it does not
  /// hold a shorter, confident-looking subset of them.
  final bool isReadable;

  const Nav2CollisionDetectorState({
    required this.polygons,
    required this.detections,
    this.isReadable = true,
  });

  /// Construct from the publisher's JSON shape.
  factory Nav2CollisionDetectorState.fromJson(Map<String, dynamic> json) {
    final rawPolys = json['polygons'];
    final rawDets = json['detections'];
    // ABSENT detections is unreadable, not "nothing detected"; and a
    // polygons/detections length mismatch is proof the message is corrupt.
    // Up to 0.1.4 the first case became an empty list (so `anyDetection`
    // returned a confident `false`) and the second was absorbed by
    // `triggeredPolygons` iterating min(len) — reporting on the shorter run
    // and silently dropping the rest. Both resolve absence to the benign
    // branch on a collision channel.
    if (rawPolys is! List || rawDets is! List || rawPolys.length != rawDets.length) {
      return const Nav2CollisionDetectorState(
        polygons: [],
        detections: [],
        isReadable: false,
      );
    }
    return Nav2CollisionDetectorState(
      polygons: rawPolys.map((e) => e.toString()).toList(growable: false),
      detections: rawDets.map((e) => e == true).toList(growable: false),
    );
  }

  /// True if any configured polygon currently reports a detection;
  /// **`null` when the message was unreadable** ([isReadable] false).
  ///
  /// `null` means NOT KNOWN. It never means "nothing detected" — the value
  /// this returned up to 0.1.4 for a message carrying no detections at all.
  bool? get anyDetection => isReadable ? detections.any((d) => d) : null;

  /// Returns the names of polygons currently reporting a detection.
  List<String> get triggeredPolygons {
    final out = <String>[];
    for (var i = 0; i < polygons.length && i < detections.length; i++) {
      if (detections[i]) out.add(polygons[i]);
    }
    return out;
  }

  @override
  List<Object?> get props => [polygons, detections, isReadable];
}

/// An advisory this layer declined to emit, and why.
///
/// ⚑ Exists because until 2026-08-21 a suppressed alert produced nothing an
/// integrator could observe. A dropped stop-warning and a quiet robot were the
/// same event: silence.
class Nav2SuppressedAdvisory {
  const Nav2SuppressedAdvisory({
    required this.severity,
    required this.action,
    required this.where,
    required this.at,
    required this.outcome,
  });

  /// The tier the suppressed event carried.
  final AlertSeverity severity;

  /// The nav2 action name, or `'detection'` for the detector path.
  final String action;

  /// Polygon name, or the joined triggered-polygon list.
  final String where;

  final DateTime at;

  /// Always [LoomFitOutcome.droppedByThrottle] today; the field exists so a
  /// future outcome does not require a breaking change.
  final LoomFitOutcome outcome;

  @override
  String toString() =>
      'Nav2SuppressedAdvisory(${severity.name}, $action, $where, ${outcome.name})';
}
