/// Layer that composes a stream of nav2 collision-state events into a
/// rate-limited driver-facing advisory stream using
/// `navigation_safety_core`'s `AlertDensityThrottle` + `AlertExplainer`.
///
/// The integrator owns the transport — `roslibdart`, rosbridge over
/// WebSocket, MQTT bridge, or a custom Dart wrapper — and feeds typed
/// [Nav2CollisionMonitorState] / [Nav2CollisionDetectorState] events
/// into [Nav2SafetyLayer.onMonitorState] /
/// [Nav2SafetyLayer.onDetectorState]. The layer maps each event to an
/// advisory action string and emits it through the throttle so a
/// driver in unexpected snow does not face alert-fatigue from a chatty
/// monitor.
library;

import 'dart:async';

import 'package:navigation_safety_core/navigation_safety_core.dart';

import 'nav2_collision_msgs.dart';
import 'nav2_safety_mapper.dart';

/// Composition layer between nav2 collision-state messages and
/// `navigation_safety_core` driver-cognition advisories.
class Nav2SafetyLayer {
  /// Driver profile used to pick advisory verbosity / locale.
  final DriverProfile profile;

  /// Throttle rate-limiting advisories so the driver is not flooded.
  /// Pass any `AlertDensityThrottle` instance — the integrator chooses
  /// the cap class.
  final AlertDensityThrottle throttle;

  final _advisoryController = StreamController<String>.broadcast();

  Nav2SafetyLayer({
    required this.profile,
    required this.throttle,
  });

  /// Stream of advisory action strings the integrator's HMI can
  /// surface. Strings are pre-throttled and pre-localized for the
  /// active [profile].
  Stream<String> get advisories => _advisoryController.stream;

  /// Feed one Collision Monitor state event. If the monitor action is
  /// non-doNothing AND the throttle permits, an advisory is emitted.
  void onMonitorState(Nav2CollisionMonitorState state) {
    final explainer = Nav2SafetyMapper.toAdvisory(state, profile);
    if (explainer == null) return;
    if (!throttle.shouldFire(DateTime.now(), AlertSeverity.warning)) return;
    _advisoryController.add(explainer.action);
  }

  /// Feed one Collision Detector state event. When any polygon
  /// reports a detection AND the throttle permits, an advisory is
  /// emitted naming the triggered polygons verbatim from the
  /// publisher in the advisory body. Caution-add-only — empty
  /// detection lists are silently ignored.
  void onDetectorState(Nav2CollisionDetectorState state) {
    final triggered = Nav2SafetyMapper.triggeredPolygonNames(state);
    if (triggered.isEmpty) return;
    if (!throttle.shouldFire(DateTime.now(), AlertSeverity.warning)) return;
    final explainer = AlertExplainer.forConditionAndProfile(
      RoadSurfaceCondition.ice,
      profile,
    );
    final polys = triggered.join(', ');
    _advisoryController.add('${explainer.action} [$polys]');
  }

  /// Dispose the layer and close the advisory stream. Idempotent.
  Future<void> dispose() async {
    if (!_advisoryController.isClosed) {
      await _advisoryController.close();
    }
  }
}
