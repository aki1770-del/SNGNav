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
      case Nav2CollisionAction.stop:
      case Nav2CollisionAction.approach:
      case Nav2CollisionAction.limit:
      case Nav2CollisionAction.slowdown:
        // All four non-doNothing actions denote that the monitor has
        // detected an obstacle inside a configured polygon. The
        // surface vocabulary `navigation_safety_core` ships maps this
        // to `RoadSurfaceCondition.ice` — the closest existing
        // semantic for "surface ahead requires caution-add-only
        // attention from the driver." Future minor versions of this
        // package may introduce a richer driver-cognition vocabulary
        // dedicated to obstacle-class advisories.
        return AlertExplainer.forConditionAndProfile(
          RoadSurfaceCondition.ice,
          profile,
        );
    }
  }

  /// Translates a Collision Detector state into a verbatim list of the
  /// polygon names currently reporting detections. Returns the same
  /// list as [Nav2CollisionDetectorState.triggeredPolygons]; surfaced
  /// here for symmetry with the Monitor mapper and for forward
  /// compatibility when richer detector-class advisories are added.
  static List<String> triggeredPolygonNames(
    Nav2CollisionDetectorState state,
  ) {
    return state.triggeredPolygons;
  }
}
