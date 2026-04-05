import 'package:equatable/equatable.dart';

/// Thresholds that govern when [AdaptiveRerouteService] recommends rerouting.
///
/// All thresholds are advisory — they influence [RerouteDecision.shouldReroute]
/// but the driver always decides. The defaults are conservative for winter
/// driving in Japan.
class AdaptiveRerouteConfig extends Equatable {
  /// ETA window (seconds from current position) within which hazards trigger
  /// reroute evaluation. Hazards beyond this horizon are flagged but do not
  /// generate a reroute recommendation.
  ///
  /// Default: 1800 s (30 minutes at 60 km/h ≈ 30 km).
  final double hazardWindowSeconds;

  /// Detour distance limit as a fraction of the original route distance.
  /// A candidate route that exceeds `originalKm * (1 + maxDetourFraction)`
  /// is rejected.
  ///
  /// Default: 0.25 (25% longer route accepted).
  final double maxDetourFraction;

  /// Minimum forecast confidence required to act on a hazard signal.
  /// Below this threshold the hazard is logged but does not trigger a reroute.
  ///
  /// Default: 0.4 — roughly the confidence at 7h forecast horizon.
  final double minConfidenceToAct;

  /// Perpendicular offset (metres) for bypass waypoint generation.
  /// A larger value routes further around the hazard zone.
  ///
  /// Default: 2000 m (2 km lateral offset from hazard centre).
  final double detourOffsetMeters;

  const AdaptiveRerouteConfig({
    this.hazardWindowSeconds = 1800.0,
    this.maxDetourFraction = 0.25,
    this.minConfidenceToAct = 0.4,
    this.detourOffsetMeters = 2000.0,
  });

  @override
  List<Object?> get props => [
        hazardWindowSeconds,
        maxDetourFraction,
        minConfidenceToAct,
        detourOffsetMeters,
      ];
}
