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

  const RouteManeuver({
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

  @override
  String toString() =>
      'RouteManeuver($index: $type "$instruction" ${lengthKm}km)';
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
  String toString() =>
      'EngineInfo($name v$version, ${queryLatency.inMilliseconds}ms)';
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

  /// BCP-47-ish language tag for the turn-by-turn instructions
  /// (default `'ja-JP'`).
  ///
  /// Per-engine localization contract:
  /// - **OSRM**: localized CLIENT-side. Japanese (`ja`/`ja-JP`/`ja_JP`) is
  ///   produced natively; any other tag degrades gracefully to the engine's
  ///   own English phrasing (never a wrong instruction, never a throw).
  /// - **Valhalla**: the tag is forwarded SERVER-side
  ///   (`directions_options.language`); supported locales are the Valhalla
  ///   server's.
  ///
  /// Consumers switching engines should expect this asymmetry: a tag like
  /// `'de-DE'` yields English on the OSRM path but German (if the server
  /// supports it) on the Valhalla path.
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
