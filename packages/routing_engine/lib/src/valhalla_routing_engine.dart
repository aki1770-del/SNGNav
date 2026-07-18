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

      // 0.3.3: a 200 body may still be non-JSON (proxy/portal/cache). 0.3.1 threw
      // a raw FormatException/TypeError here that escaped the RoutingException
      // contract and crashed the caller. Convert it to a RoutingException.
      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw RoutingException('Valhalla returned a non-JSON body (HTTP 200)');
      }
      if (decoded is! Map<String, dynamic>) {
        throw RoutingException('Valhalla returned an unexpected JSON shape (HTTP 200)');
      }
      return _parseRouteResponse(decoded, stopwatch.elapsed);
    } on http.ClientException catch (e) {
      throw RoutingException('Valhalla network error: $e');
    }
  }

  RouteResult _parseRouteResponse(
    Map<String, dynamic> json,
    Duration latency,
  ) {
    // 0.3.3: crash backstop. The targeted guards below fix the high-reach
    // malformations (they still return a usable, flagged route). This wrapper
    // catches ANY residual parse throw — a non-object leg/maneuver, a numeric
    // field sent as a string, a shape this decoder cannot handle — and converts
    // it to the documented RoutingException instead of letting a raw
    // RangeError/TypeError/FormatException escape and crash the caller.
    // RoutingExceptions raised deliberately below pass through unchanged.
    try {
      return _parseRouteResponseImpl(json, latency);
    } on RoutingException {
      rethrow;
    } catch (e) {
      throw RoutingException(
        'Valhalla returned a response this package could not parse: $e',
      );
    }
  }

  RouteResult _parseRouteResponseImpl(
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
        // 0.3.3: read as `num?` not `int?`. 0.3.1's `as int?` threw a raw cast
        // error when a server sent `begin_shape_index: 1.0` (a JSON double),
        // crashing the whole route call. `num?.toInt()` accepts int or double.
        final rawShapeIdx = (mMap['begin_shape_index'] as num?)?.toInt();
        final shapeIdx = rawShapeIdx ?? 0;
        // No decoded shape => no truthful point exists for this maneuver. We drop it
        // rather than fabricate one. A missing turn is visible; a fabricated one is not.
        if (allPoints.isEmpty) continue;
        // 0.3.2: honest signal on top of the 0.3.1 clamp. The maneuver's own
        // position is RESOLVED only when we had a real `begin_shape_index` that
        // lands inside the decoded shape. A MISSING index (defaulted to 0, i.e.
        // silently "at the route start") or one PAST the shape (clamped to the
        // last decoded point) is a substitution — imprecise, on the route, but
        // NOT this turn's location. We keep the same clamped [position] for
        // backward compatibility and flag it via `positionResolved: false`.
        final positionResolved =
            rawShapeIdx != null && rawShapeIdx >= 0 && rawShapeIdx < allPoints.length;
        // 0.3.3: CRASH FIX. 0.3.1 used `shapeIdx < allPoints.length ? [shapeIdx]
        // : last`, which threw RangeError for a NEGATIVE index (`-1 < len` is
        // true, then `allPoints[-1]`). A crash takes down the entire route call —
        // deeper harm than an imprecise point. Clamp into the real decoded range:
        // for every non-negative index the value is byte-identical to 0.3.1
        // (in-range -> that point; past-the-end -> the last point); a negative
        // index now lands on the first point instead of throwing. Never fabricates
        // (allPoints is non-empty here), never throws.
        final safeIdx = shapeIdx.clamp(0, allPoints.length - 1);
        allManeuvers.add(RouteManeuver(
          index: maneuverIndex++,
          instruction: mMap['instruction'] as String? ?? '',
          // 0.3.3: `num?.toInt()` — 0.3.1's `as int?` threw on a double `type`.
          type: _maneuverTypeString((mMap['type'] as num?)?.toInt() ?? 0),
          lengthKm: (mMap['length'] as num?)?.toDouble() ?? 0,
          timeSeconds: (mMap['time'] as num?)?.toDouble() ?? 0,
          position: allPoints[safeIdx],
          positionResolved: positionResolved,
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
      var shift = 0;
      var result = 0;
      int b;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lat += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      lng += (result & 1) != 0 ? ~(result >> 1) : (result >> 1);

      points.add(LatLng(lat / 1e6, lng / 1e6));
    }

    return points;
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
