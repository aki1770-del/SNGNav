/// Engine-agnostic route model — the edge developer never touches
/// Valhalla JSON or OSRM protobuf directly.
///
/// Works with any routing engine (OSRM, Valhalla, or mock).
library;

import 'package:equatable/equatable.dart';
import 'package:latlong2/latlong.dart';

/// A single maneuver step along a route.
class RouteManeuver extends Equatable {
  final int index;
  final String instruction;
  final String type; // engine-agnostic: 'depart', 'right', 'left', etc.
  final double lengthKm;
  final double timeSeconds;
  final LatLng position;

  /// Whether [position] was resolved from the routing response for THIS
  /// maneuver, or substituted.
  ///
  /// `true`  — [position] is this maneuver's own resolved coordinate.
  /// `false` — [position] is a **substituted** point (a nearby corridor point,
  ///            or the route origin) that this package clamped in because the
  ///            maneuver's own location could not be resolved (OSRM omitted
  ///            `maneuver.location`; Valhalla's `begin_shape_index` was missing
  ///            or ran past the decoded shape). It is somewhere on the route,
  ///            but it is NOT where this turn happens.
  ///
  /// Prior 0.3.x releases exposed no way to tell these apart, so a clamped,
  /// imprecise point was narrated and plotted with the same confidence as a
  /// real one. Guard reads with [hasPosition] before you narrate a place,
  /// drop a marker, or measure distance-to-next-maneuver.
  ///
  /// Defaults to `true` so that existing direct constructions are unchanged.
  final bool positionResolved;

  const RouteManeuver({
    required this.index,
    required this.instruction,
    required this.type,
    required this.lengthKm,
    required this.timeSeconds,
    required this.position,
    this.positionResolved = true,
  });

  /// `true` when [position] is this maneuver's own resolved coordinate;
  /// `false` when [position] is a substituted/approximated point that must not
  /// be trusted as the turn's location. See [positionResolved].
  ///
  /// Migration for a `^0.3.0` consumer (no signature changed — additive):
  /// ```dart
  /// if (m.hasPosition) {
  ///   // safe: announce the place, draw the marker, measure distance
  /// } else {
  ///   // announce the turn WITHOUT a place; skip the marker; no distance
  /// }
  /// ```
  bool get hasPosition => positionResolved;

  // NOTE: [positionResolved] is deliberately NOT in [props]. Equality on 0.3.x
  // stays byte-identical to 0.3.1 so this patch changes no observable equality
  // behavior — the resolved/substituted signal is exposed via [hasPosition] and
  // [toString] only.
  @override
  List<Object?> get props =>
      [index, instruction, type, lengthKm, timeSeconds, position];

  @override
  String toString() => positionResolved
      ? 'RouteManeuver($index: $type "$instruction" ${lengthKm}km)'
      : 'RouteManeuver($index: $type "$instruction" ${lengthKm}km, position unknown)';
}

/// Which routing engine produced this result.
class EngineInfo extends Equatable {
  final String name; // 'osrm', 'valhalla', 'mock'
  final String version;
  final Duration queryLatency;

  const EngineInfo({
    required this.name,
    this.version = 'unknown',
    this.queryLatency = Duration.zero,
  });

  @override
  List<Object?> get props => [name, version, queryLatency];

  @override
  String toString() => 'EngineInfo($name v$version, ${queryLatency.inMilliseconds}ms)';
}

/// A complete route result — engine-agnostic.
class RouteResult extends Equatable {
  /// Decoded polyline as list of [LatLng] points.
  final List<LatLng> shape;

  /// Maneuver instructions along the route.
  final List<RouteManeuver> maneuvers;

  /// Total route distance in km.
  final double totalDistanceKm;

  /// Total route time in seconds.
  final double totalTimeSeconds;

  /// Human-readable summary.
  final String summary;

  /// Which engine produced this route.
  final EngineInfo engineInfo;

  const RouteResult({
    required this.shape,
    required this.maneuvers,
    required this.totalDistanceKm,
    required this.totalTimeSeconds,
    required this.summary,
    required this.engineInfo,
  });

  /// Estimated time of arrival from now.
  Duration get eta => Duration(seconds: totalTimeSeconds.round());

  /// Whether this route has usable geometry.
  bool get hasGeometry => shape.length >= 2;

  @override
  List<Object?> get props => [
        shape,
        maneuvers,
        totalDistanceKm,
        totalTimeSeconds,
        summary,
        engineInfo,
      ];

  @override
  String toString() =>
      'RouteResult(${totalDistanceKm.toStringAsFixed(1)}km, '
      '${eta.inMinutes}min, ${shape.length} pts, '
      '${engineInfo.name})';
}

/// Parameters for a route request — engine-agnostic.
class RouteRequest extends Equatable {
  final LatLng origin;
  final LatLng destination;
  final String costing; // 'auto', 'bicycle', 'pedestrian', 'truck'
  final String language;

  const RouteRequest({
    required this.origin,
    required this.destination,
    this.costing = 'auto',
    this.language = 'ja-JP',
  });

  @override
  List<Object?> get props => [origin, destination, costing, language];
}
