/// Navigation layer route model — decoupled from routing engine internals.
///
/// [NavigationRoute] and [NavigationManeuver] mirror the shape of
/// `RouteResult` and `RouteManeuver` from `routing_engine`, but live entirely
/// inside `navigation_safety`. This keeps the public API of `navigation_safety`
/// free of any `routing_engine` dependency (D-SC22-4).
///
/// Consumers convert at the application boundary using an adapter or extension
/// (e.g. `RouteResult.toNavigationRoute()`). The navigation session state
/// machine works exclusively with these types.
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// A single turn or waypoint instruction within a [NavigationRoute].
///
/// Mirrors `RouteManeuver` from `routing_engine` with identical fields,
/// but belongs to the navigation layer and carries no engine-specific state.
class NavigationManeuver extends Equatable {
  /// Zero-based position of this maneuver in the maneuver list.
  final int index;

  /// Human-readable instruction text (e.g. "Turn left onto Main St").
  final String instruction;

  /// Maneuver type token as returned by the routing engine
  /// (e.g. `"turn"`, `"arrive"`, `"depart"`).
  final String type;

  /// Distance from this maneuver to the next, in kilometres.
  final double lengthKm;

  /// Estimated travel time from this maneuver to the next, in seconds.
  final double timeSeconds;

  /// Geographic coordinate at which this maneuver occurs.
  final LatLng position;

  const NavigationManeuver({
    required this.index,
    required this.instruction,
    required this.type,
    required this.lengthKm,
    required this.timeSeconds,
    required this.position,
  });

  @override
  List<Object?> get props => [
        index,
        instruction,
        type,
        lengthKm,
        timeSeconds,
        position,
      ];
}

/// A complete route as presented to the navigation session.
///
/// Mirrors `RouteResult` from `routing_engine` minus engine-internal fields
/// (e.g. `engineInfo`). Use [eta] and [hasGeometry] for display logic.
class NavigationRoute extends Equatable {
  /// Ordered list of coordinates that form the route polyline.
  final List<LatLng> shape;

  /// Ordered list of turn instructions along the route.
  final List<NavigationManeuver> maneuvers;

  /// Total route distance in kilometres.
  final double totalDistanceKm;

  /// Total estimated travel time in seconds.
  final double totalTimeSeconds;

  /// Short human-readable summary (e.g. origin → destination via highway).
  final String summary;

  const NavigationRoute({
    required this.shape,
    required this.maneuvers,
    required this.totalDistanceKm,
    required this.totalTimeSeconds,
    required this.summary,
  });

  /// Estimated time of arrival as a [Duration].
  Duration get eta => Duration(seconds: totalTimeSeconds.round());

  /// Returns `true` when [shape] contains at least two points and can be
  /// rendered as a polyline.
  bool get hasGeometry => shape.length >= 2;

  @override
  List<Object?> get props => [
        shape,
        maneuvers,
        totalDistanceKm,
        totalTimeSeconds,
        summary,
      ];
}
