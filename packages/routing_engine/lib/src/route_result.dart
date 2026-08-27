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
  final double? _lengthKm;
  final double? _timeSeconds;

  /// Distance of this maneuver in km, or `0` when the engine did not send one.
  ///
  /// **Read [lengthKmOrNull] if you need to tell an absent value from a real
  /// zero.** Up to and including 0.6.2 both engines applied `?? 0` to a missing
  /// `distance`/`length`, so an unmeasured maneuver was indistinguishable from
  /// one the driver is standing on — the shape of *"in 0.0 km, turn left"*.
  double get lengthKm => _lengthKm ?? 0;

  /// Duration of this maneuver in seconds, or `0` when the engine did not send
  /// one. See [timeSecondsOrNull].
  double get timeSeconds => _timeSeconds ?? 0;

  /// Distance in km, or **`null` when the engine did not measure it.**
  double? get lengthKmOrNull => _lengthKm;

  /// Duration in seconds, or **`null` when the engine did not measure it.**
  double? get timeSecondsOrNull => _timeSeconds;

  /// Whether the engine actually sent a distance for this maneuver.
  bool get hasMeasuredLength => _lengthKm != null;

  /// Whether the engine actually sent a duration for this maneuver.
  bool get hasMeasuredTime => _timeSeconds != null;

  /// Where the maneuver happens — **`null` means the position is UNKNOWN.**
  ///
  /// `null` is never "the origin" and never `LatLng(0, 0)`. It means the
  /// engine's response did not carry a usable coordinate for this maneuver
  /// (a missing/short `location` array on OSRM; a `begin_shape_index` that
  /// falls outside the decoded polyline on Valhalla).
  ///
  /// Up to and including 0.5.0 both engines silently substituted
  /// `const LatLng(0, 0)` — Null Island, a real coordinate in the Gulf of
  /// Guinea — which consumers then narrated and mapped as a genuine position.
  /// Absence of a measurement is not a measurement. Read it through
  /// [hasPosition], and do not narrate or plot a maneuver that has none.
  ///
  /// [instruction] is still true when the position is absent — one unparseable
  /// coordinate does not invalidate the route.
  ///
  /// **This comment used to vouch for [lengthKm] and [timeSeconds] as well.
  /// That was wrong.** Through 0.6.2 both were produced with `?? 0`, so the
  /// same "absence of a measurement is not a measurement" defect this field was
  /// fixed for was live one layer down, certified as "still true" by the very
  /// doc comment that states the rule. Use [lengthKmOrNull]/[timeSecondsOrNull].
  final LatLng? position;

  const RouteManeuver({
    required this.index,
    required this.instruction,
    required this.type,
    required double? lengthKm,
    required double? timeSeconds,
    required this.position,
  }) : _lengthKm = lengthKm,
       _timeSeconds = timeSeconds;

  /// Whether this maneuver carries a known position.
  ///
  /// `false` means the engine gave us no usable coordinate — not that the
  /// maneuver is at 0,0.
  bool get hasPosition => position != null;

  @override
  List<Object?> get props => [
    index,
    instruction,
    type,
    _lengthKm,
    _timeSeconds,
    position,
  ];

  @override
  String toString() =>
      'RouteManeuver($index: $type "$instruction" '
      '${hasMeasuredLength ? '${lengthKm}km' : 'length unknown'}'
      '${hasPosition ? '' : ', position unknown'})';
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
