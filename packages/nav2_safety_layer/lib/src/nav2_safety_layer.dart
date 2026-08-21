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

  Nav2SafetyLayer({required this.profile, required this.throttle});

  /// Stream of advisory action strings the integrator's HMI can
  /// surface. Strings are pre-throttled and pre-localized for the
  /// active [profile].
  Stream<String> get advisories => _advisoryController.stream;

  /// Feed one Collision Monitor state event. If the monitor action is
  /// non-doNothing AND the throttle permits, an advisory is emitted.
  /// The severity tier each nav2 action carries.
  ///
  /// ⚑ Until 2026-08-21 every event was passed as [AlertSeverity.warning],
  /// hardcoded. `AlertSeverity.critical` was never constructed anywhere in this
  /// package, so `AlertDensityThrottle`'s non-negotiable critical-bypass — the
  /// one its own source says exists "to keep them credible, not to mask them" —
  /// was never reached. Measured: a 2/min cap, five `LIMIT` events, then a
  /// `STOP` on `IMMINENT_FRONT` → the STOP was NOT delivered, while the same
  /// throttle returned true for `critical`. Worse in the field: the Collision
  /// *Detector* publishes on a 10 Hz timer by default (600 msg/min) and shares
  /// this throttle, so on every shipped driver profile the STOP was suppressed
  /// after ONE SECOND. There is no cap that survives a fixed-rate publisher.
  ///
  /// The tiering is not invented. Three independent sources agree: nav2's own
  /// colour map (`collision_monitor_node.cpp:698-706` — STOP red, SLOWDOWN and
  /// LIMIT amber, APPROACH blue), 14 CFR 25.1322(b)'s Warning/Caution/Advisory
  /// hierarchy keyed on awareness-timing × response-timing, and the three tiers
  /// `AlertSeverity` already ships.
  ///
  /// `APPROACH` is deliberately [AlertSeverity.critical] and this is a bound,
  /// not a judgement: its urgency depends on the configured
  /// `time_before_collision`, and `CollisionMonitorState` carries only
  /// `action_type` and `polygon_name`. A faithful relay CANNOT tier it, so it
  /// fails toward the severe reading.
  static AlertSeverity severityOf(Nav2CollisionAction a) {
    switch (a) {
      case Nav2CollisionAction.stop:
      case Nav2CollisionAction.approach:
        return AlertSeverity.critical;
      case Nav2CollisionAction.slowdown:
      case Nav2CollisionAction.limit:
        return AlertSeverity.warning;
      case Nav2CollisionAction.doNothing:
        return AlertSeverity.info;
    }
  }

  void onMonitorState(Nav2CollisionMonitorState state) {
    final explainer = Nav2SafetyMapper.toAdvisory(state, profile);
    if (explainer == null) return;
    final severity = severityOf(state.actionType);
    if (!throttle.shouldFire(DateTime.now(), severity)) {
      _announceDrop(severity, state.actionType.name, state.polygonName);
      return;
    }
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
    // Upstream declares the Detector informational: it reports "without
    // affecting the robot's velocity" and its action_type "should always be
    // set to none". It must not spend the budget the Monitor's STOP needs.
    if (!throttle.shouldFire(DateTime.now(), AlertSeverity.info)) {
      _announceDrop(AlertSeverity.info, 'detection', triggered.join(', '));
      return;
    }
    final explainer = AlertExplainer.forConditionAndProfile(
      // ⚑ CORRECTED 2026-08-21, second site. The mapper (monitor path) was
      // corrected earlier the same day and THIS call site was missed, so the
      // detector path went on emitting the fabricated frozen-road warning.
      // Found by AAA. A detection means an object is inside a polygon; it
      // says nothing whatever about the road surface.
      RoadSurfaceCondition.unknown,
      profile,
    );
    final polys = triggered.join(', ');
    _advisoryController.add('${explainer.action} [$polys]');
  }

  /// Every advisory this layer declined to emit, and why.
  ///
  /// ⚑ Added 2026-08-21. Previously a suppressed alert produced nothing at all
  /// — not a signal, not telemetry, not a log line — so an integrator could not
  /// distinguish "the monitor is quiet" from "we dropped it". Every alerting
  /// regime that permits suppression requires it be annunciated; the sibling
  /// package `navigation_safety` already emits [LoomFitOutcome.droppedByThrottle]
  /// and this one discarded. Listening is optional; the trace now exists.
  Stream<Nav2SuppressedAdvisory> get suppressed => _suppressedController.stream;

  final _suppressedController =
      StreamController<Nav2SuppressedAdvisory>.broadcast();

  void _announceDrop(AlertSeverity severity, String action, String where) {
    if (_suppressedController.isClosed) return;
    _suppressedController.add(Nav2SuppressedAdvisory(
      severity: severity,
      action: action,
      where: where,
      at: DateTime.now(),
      outcome: LoomFitOutcome.droppedByThrottle,
    ));
  }

  /// Dispose the layer and close the advisory stream. Idempotent.
  Future<void> dispose() async {
    if (!_suppressedController.isClosed) {
      await _suppressedController.close();
    }
    if (!_advisoryController.isClosed) {
      await _advisoryController.close();
    }
  }
}
