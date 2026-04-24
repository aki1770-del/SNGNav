/// Valhalla routing engine — multi-modal routing with isochrone support.
///
/// Supports auto, bicycle, pedestrian, and truck costing models.
/// Japanese language support for maneuver instructions.
/// Polyline precision: 6 (1e6) — differs from OSRM's precision 5.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'exceptions.dart';
import 'route_result.dart';
import 'routing_engine.dart';

const _defaultValhallaUrl = 'http://localhost:8002';

class ValhallaRoutingEngine implements RoutingEngine {
  final String baseUrl;
  final Duration availabilityTimeout;
  final Duration routeTimeout;
  final http.Client _client;

  ValhallaRoutingEngine({
    String? baseUrl,
    this.availabilityTimeout = const Duration(seconds: 3),
    this.routeTimeout = const Duration(seconds: 15),
    http.Client? client,
  })  : baseUrl = baseUrl ?? _defaultValhallaUrl,
        _client = client ?? http.Client();

  ValhallaRoutingEngine.local({
    String host = 'localhost',
    int port = 8005,
    Duration availabilityTimeout = const Duration(seconds: 3),
    Duration routeTimeout = const Duration(seconds: 15),
    http.Client? client,
  }) : this(
         baseUrl: 'http://$host:$port',
         availabilityTimeout: availabilityTimeout,
         routeTimeout: routeTimeout,
         client: client,
       );

  @override
  EngineInfo get info => const EngineInfo(name: 'valhalla');

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/status');
      final response = await _client.get(uri).timeout(availabilityTimeout);
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    final stopwatch = Stopwatch()..start();

    final requestBody = jsonEncode({
      'locations': [
        {'lat': request.origin.latitude, 'lon': request.origin.longitude},
        {
          'lat': request.destination.latitude,
          'lon': request.destination.longitude,
        },
      ],
      'costing': request.costing,
      'directions_options': {
        'language': request.language,
        'units': 'kilometers',
      },
      'costing_options': {
        request.costing: {
          'use_highways': 0.8,
          'use_tolls': 0.5,
        },
      },
    });

    final uri = Uri.parse('$baseUrl/route');

    try {
      final response = await _client
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: requestBody,
          )
          .timeout(routeTimeout);

      stopwatch.stop();

      if (response.statusCode != 200) {
        final errorBody = _tryParseJson(response.body);
        final errorMsg = errorBody?['error'] ?? response.body;
        throw RoutingException(
          'Valhalla route failed (${response.statusCode}): $errorMsg',
        );
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      return _parseRouteResponse(json, stopwatch.elapsed);
    } on RoutingException {
      rethrow;
    } on Exception catch (e) {
      throw RoutingException('Valhalla network error: $e');
    }
  }

  RouteResult _parseRouteResponse(
    Map<String, dynamic> json,
    Duration latency,
  ) {
    final trip = json['trip'] as Map<String, dynamic>?;
    if (trip == null) {
      throw RoutingException('Invalid response: missing "trip" field');
    }

    final legs = trip['legs'] as List<dynamic>?;
    if (legs == null || legs.isEmpty) {
      throw RoutingException('Invalid response: no route legs');
    }

    final summaryData = trip['summary'] as Map<String, dynamic>? ?? {};
    final totalDistanceKm = (summaryData['length'] as num?)?.toDouble() ?? 0;
    final totalTimeSeconds = (summaryData['time'] as num?)?.toDouble() ?? 0;

    final allPoints = <LatLng>[];
    final allManeuvers = <RouteManeuver>[];
    var maneuverIndex = 0;

    for (final leg in legs) {
      final legMap = leg as Map<String, dynamic>;

      final shapeStr = legMap['shape'] as String? ?? '';
      if (shapeStr.isNotEmpty) {
        allPoints.addAll(_decodePolyline6(shapeStr));
      }

      final maneuvers = legMap['maneuvers'] as List<dynamic>? ?? [];
      for (final m in maneuvers) {
        final mMap = m as Map<String, dynamic>;
        final shapeIdx = mMap['begin_shape_index'] as int? ?? 0;
        allManeuvers.add(RouteManeuver(
          index: maneuverIndex++,
          instruction: mMap['instruction'] as String? ?? '',
          type: _maneuverTypeString(mMap['type'] as int? ?? 0),
          lengthKm: (mMap['length'] as num?)?.toDouble() ?? 0,
          timeSeconds: (mMap['time'] as num?)?.toDouble() ?? 0,
          position: shapeIdx < allPoints.length
              ? allPoints[shapeIdx]
              : const LatLng(0, 0),
        ));
      }
    }

    return RouteResult(
      shape: allPoints,
      maneuvers: allManeuvers,
      totalDistanceKm: totalDistanceKm,
      totalTimeSeconds: totalTimeSeconds,
      summary: '${totalDistanceKm.toStringAsFixed(1)} km, '
          '${(totalTimeSeconds / 60).toStringAsFixed(0)} min',
      engineInfo: EngineInfo(
        name: 'valhalla',
        queryLatency: latency,
      ),
    );
  }

  List<LatLng> _decodePolyline6(String encoded) {
    final points = <LatLng>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < encoded.length) {
      lat += _decodeChunk(encoded, index, (i) => index = i);
      lng += _decodeChunk(encoded, index, (i) => index = i);

      final decodedLat = lat / 1e6;
      final decodedLng = lng / 1e6;

      if (decodedLat < -90.0 ||
          decodedLat > 90.0 ||
          decodedLng < -180.0 ||
          decodedLng > 180.0) {
        throw RoutingException(
          'Decoded coordinate out of range: ($decodedLat, $decodedLng). '
          'Possible corrupt polyline or wrong precision.',
        );
      }

      points.add(LatLng(decodedLat, decodedLng));
    }

    return points;
  }

  /// Decode one polyline chunk (lat or lng delta) and advance [indexSetter].
  ///
  /// Guards against:
  /// - Truncated strings (bounds check before every byte read)
  /// - Runaway continuation bytes on corrupt data (14-iteration cap)
  /// - 32-bit shift overflow on Dart web JS targets (shift capped at 30)
  int _decodeChunk(
    String encoded,
    int startIndex,
    void Function(int) indexSetter,
  ) {
    const maxIter = 14; // 14 × 5 = 70 bits — exceeds any valid geo delta
    var b = 0;
    var shift = 0;
    var result = 0;
    var index = startIndex;
    var iter = 0;

    do {
      if (index >= encoded.length) {
        throw RoutingException('Truncated polyline at index $index');
      }
      if (iter++ >= maxIter) {
        throw RoutingException(
          'Polyline chunk exceeds $maxIter continuation bytes at index $index — '
          'possible corrupt data.',
        );
      }
      b = encoded.codeUnitAt(index++) - 63;
      if (shift < 30) {
        // Safe to shift on both VM (63-bit int) and web (32-bit bitwise).
        result |= (b & 0x1F) << shift;
      }
      // shift >= 30: high bits are beyond the geographic coordinate range for
      // precision-6 encoding (max |delta| ~180e6 ≈ 28 bits); discard safely.
      shift += 5;
    } while (b >= 0x20);

    indexSetter(index);
    return (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
  }

  String _maneuverTypeString(int type) {
    const types = {
      0: 'none',
      1: 'depart',
      2: 'arrive',
      3: 'straight',
      4: 'arrive',
      5: 'slight_right',
      6: 'right',
      7: 'sharp_right',
      8: 'u_turn_right',
      9: 'u_turn_left',
      10: 'sharp_left',
      11: 'left',
      12: 'slight_left',
      13: 'ramp_straight',
      14: 'ramp_right',
      15: 'ramp_left',
      16: 'exit_right',
      17: 'exit_left',
      18: 'stay_straight',
      19: 'stay_right',
      20: 'stay_left',
      21: 'merge',
      22: 'roundabout_enter',
      23: 'roundabout_exit',
      24: 'ferry_enter',
      25: 'ferry_exit',
      26: 'transit',
      27: 'transit_transfer',
      28: 'transit_remain_on',
      29: 'transit_connection_start',
      30: 'transit_connection_transfer',
      31: 'transit_connection_destination',
      32: 'post_transit',
      33: 'merge_right',
      34: 'merge_left',
    };
    return types[type] ?? 'unknown';
  }

  Map<String, dynamic>? _tryParseJson(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> dispose() async {
    _client.close();
  }
}
