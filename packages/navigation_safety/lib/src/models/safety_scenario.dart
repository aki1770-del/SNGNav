/// SafetyScenario — named, versioned coordinate for swarm composability.
///
/// A [SafetyScenario] identifies the type of road hazard an alert describes.
/// It is the shared coordinate system that lets independent packages contribute
/// to the same namespace without central coordination.
///
/// ## Naming convention
///
/// `sngnav.[category].[subcategory].[specific].v[N]`
///
/// Categories: `sensing`, `routing`, `signal`, `dynamics`, `hmi`
///
/// ## Examples
///
/// ```dart
/// const blackIce = SafetyScenario(
///   id: 'sngnav.dynamics.grip.critical.v1',
///   namespace: 'sngnav.dynamics',
///   version: 1,
/// );
///
/// const iceSignal = SafetyScenario(
///   id: 'sngnav.signal.vss.road_surface.ice.v1',
///   namespace: 'sngnav.signal.vss',
///   version: 1,
///   parameters: {'vss_value': 'ICE'},
/// );
/// ```
///
/// ## Third-party extension
///
/// Third-party packages use their own root namespace:
/// `myorg.road_conditions.tunnel_drip.v1`
///
/// Receivers that do not recognise a namespace fall back to [AlertSeverity.info]
/// (safe-fail default).
library;

import 'package:equatable/equatable.dart';

/// Identifies the type of road hazard associated with a [SafetyAlertReceived].
///
/// The [id] is a stable, versioned string used as a coordinate by all swarm
/// members. Multiple packages can emit the same scenario id — the aggregator
/// treats them as independent observations of the same condition.
class SafetyScenario extends Equatable {
  /// Fully-qualified scenario id.
  /// Format: `sngnav.[category].[subcategory].[specific].v[N]`
  final String id;

  /// Namespace prefix — used for pattern matching without parsing the full id.
  /// Example: `'sngnav.dynamics'` matches all dynamics scenarios.
  final String namespace;

  /// Semantic version. Increment only when the trigger condition definition
  /// changes such that existing handlers would need to behave differently.
  final int version;

  /// Optional evidence map — open key/value pairs for scenario-specific data.
  /// Example: `{'vss_value': 'ICE', 'confidence': '0.92'}`
  final Map<String, Object> parameters;

  const SafetyScenario({
    required this.id,
    required this.namespace,
    required this.version,
    this.parameters = const {},
  });

  @override
  List<Object?> get props => [id, version, parameters];
}

/// Well-known scenario ids — ready to use without constructing manually.
///
/// Third-party packages define their own constants in their own namespace.
abstract final class WellKnownScenarios {
  // ── Sensing ──────────────────────────────────────────────────────────────
  static const gpsDenied = SafetyScenario(
    id: 'sngnav.sensing.gps.denied.v1',
    namespace: 'sngnav.sensing.gps',
    version: 1,
  );
  static const tileMissing = SafetyScenario(
    id: 'sngnav.sensing.map.tile_missing.v1',
    namespace: 'sngnav.sensing.map',
    version: 1,
  );

  // ── Routing ───────────────────────────────────────────────────────────────
  static const tunnelApproach = SafetyScenario(
    id: 'sngnav.routing.tunnel.approach.v1',
    namespace: 'sngnav.routing.tunnel',
    version: 1,
  );
  static const bridgeIceRisk = SafetyScenario(
    id: 'sngnav.routing.bridge.ice_risk.v1',
    namespace: 'sngnav.routing.bridge',
    version: 1,
  );

  // ── Signal ────────────────────────────────────────────────────────────────
  static const vssRoadSurfaceIce = SafetyScenario(
    id: 'sngnav.signal.vss.road_surface.ice.v1',
    namespace: 'sngnav.signal.vss',
    version: 1,
    parameters: {'vss_signal': 'Vehicle.Exterior.RoadSurfaceCondition', 'vss_value': 'ICE'},
  );
  static const vssRoadSurfaceSnow = SafetyScenario(
    id: 'sngnav.signal.vss.road_surface.snow.v1',
    namespace: 'sngnav.signal.vss',
    version: 1,
    parameters: {'vss_signal': 'Vehicle.Exterior.RoadSurfaceCondition', 'vss_value': 'SNOW'},
  );
  static const vssRoadSurfaceWetIce = SafetyScenario(
    id: 'sngnav.signal.vss.road_surface.wet_ice.v1',
    namespace: 'sngnav.signal.vss',
    version: 1,
    parameters: {'vss_signal': 'Vehicle.Exterior.RoadSurfaceCondition', 'vss_value': 'WET_ICE'},
  );
  static const kuksaSubscriptionLost = SafetyScenario(
    id: 'sngnav.signal.kuksa.subscription_lost.v1',
    namespace: 'sngnav.signal.kuksa',
    version: 1,
  );

  // ── Dynamics ──────────────────────────────────────────────────────────────
  static const gripCritical = SafetyScenario(
    id: 'sngnav.dynamics.grip.critical.v1',
    namespace: 'sngnav.dynamics.grip',
    version: 1,
  );
  static const gripWarning = SafetyScenario(
    id: 'sngnav.dynamics.grip.warning.v1',
    namespace: 'sngnav.dynamics.grip',
    version: 1,
  );
  static const visibilityCritical = SafetyScenario(
    id: 'sngnav.dynamics.visibility.critical.v1',
    namespace: 'sngnav.dynamics.visibility',
    version: 1,
  );
  static const roadFreeze = SafetyScenario(
    id: 'sngnav.dynamics.temperature.road_freeze.v1',
    namespace: 'sngnav.dynamics.temperature',
    version: 1,
  );

  // ── HMI ──────────────────────────────────────────────────────────────────
  static const overlayRenderFailed = SafetyScenario(
    id: 'sngnav.hmi.overlay.render_failed.v1',
    namespace: 'sngnav.hmi.overlay',
    version: 1,
  );
  static const oodaExceeded = SafetyScenario(
    id: 'sngnav.hmi.latency.ooda_exceeded.v1',
    namespace: 'sngnav.hmi.latency',
    version: 1,
  );
}
