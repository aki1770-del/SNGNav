/// Mapper from nav2 Collision Monitor / Detector state events to the
/// `navigation_safety_core` driver-cognition vocabulary.
///
/// Mapping discipline: caution-add-only — when the publisher's
/// `action_type` is ambiguous or non-canonical, the mapping degrades
/// to the more conservative driver-facing advisory shape rather than
/// asserting a less-conservative one. Verbatim Article 17 (β) discipline
/// applies to `polygon_name` strings — they are surfaced verbatim into
/// the advisory `areaDescription` so downstream renderers can inspect
/// the publisher's exact polygon naming.
library;

import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'nav2_collision_msgs.dart';

/// Static mapping primitives.
class Nav2SafetyMapper {
  /// Maps a Collision Monitor action_type to a driver-facing advisory
  /// shape using the [AlertExplainer] / [DriverProfile] vocabulary.
  /// Returns null for [Nav2CollisionAction.doNothing] (no advisory to
  /// surface).
  static AlertExplainer? toAdvisory(
    Nav2CollisionMonitorState state,
    DriverProfile profile,
  ) {
    switch (state.actionType) {
      case Nav2CollisionAction.doNothing:
        return null;
      case Nav2CollisionAction.unreadable:
        // NOT null. Returning null here would reproduce the defect this case
        // exists to close: an unreadable frame producing silence, which the
        // driver cannot distinguish from "the monitor wants nothing done".
        // `.unknown` claims nothing about the surface — correct, because an
        // unreadable message says nothing about anything — while still
        // surfacing that the channel spoke and we could not read it.
        return AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.unknown,
          profile,
        );
      case Nav2CollisionAction.stop:
      case Nav2CollisionAction.approach:
      case Nav2CollisionAction.limit:
      case Nav2CollisionAction.slowdown:
        // All four non-doNothing actions denote that the monitor has
        // detected an obstacle inside a configured polygon. The
        // surface vocabulary `navigation_safety_core` ships maps this
        // ⚑ CORRECTED 2026-08-21. This previously mapped to
        // `RoadSurfaceCondition.ice`, on a comment claiming it was "the
        // closest existing semantic". That claim was refuted by the enum
        // this file imports: `RoadSurfaceCondition.unknown` exists at
        // road_surface_condition.dart:34 — "Sensor cannot determine
        // current road-surface state" — and is nearer in every respect.
        //
        // What `.ice` produced, measured on a well-formed STOP:
        //   「凍結路面です。気温0°C以下で薄氷ができています。
        //     時速30km以下に減速し、急ブレーキは避けてください」
        // nav2 said an OBJECT is inside a configured polygon. That text
        // fabricates a temperature reading from a message carrying no
        // temperature, and tells the driver to AVOID BRAKING HARD while
        // the monitor is commanding a stop. It is false about a road she
        // is on, and it inverts the instruction.
        //
        // `.unknown` yields 「路面状況不明。慎重に運転してください」 —
        // it claims nothing about the surface, because this message says
        // nothing about the surface.
        //
        // ⚑ RESIDUAL, stated not hidden: `.unknown` is honest and still
        // wrong in DOMAIN. nav2 reported an obstacle; RoadSurfaceCondition
        // has no obstacle member, so no value in this enum can say what
        // actually happened. That vocabulary gap is recorded, not closed.
        // dedicated to obstacle-class advisories.
        return AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.unknown,
          profile,
        );
    }
  }

  /// Translates a Collision Detector state into a verbatim list of the
  /// polygon names currently reporting detections. Returns the same
  /// list as [Nav2CollisionDetectorState.triggeredPolygons]; surfaced
  /// here for symmetry with the Monitor mapper and for forward
  /// compatibility when richer detector-class advisories are added.
  static List<String> triggeredPolygonNames(Nav2CollisionDetectorState state) {
    return state.triggeredPolygons;
  }
}
