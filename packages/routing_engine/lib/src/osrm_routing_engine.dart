/// OSRM routing engine — HTTP GET-based routing for auto/driving routes.
///
/// API: HTTP GET /route/v1/driving/{lon},{lat};{lon},{lat}
/// Polyline precision: 5 (1e5) — differs from Valhalla's precision 6.
/// Default public server: router.project-osrm.org (Zürich, CH).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'exceptions.dart';
import 'route_result.dart';
import 'routing_engine.dart';

const _defaultOsrmUrl = 'http://localhost:5000';

class OsrmRoutingEngine implements RoutingEngine {
  final String baseUrl;
  final http.Client _client;

  OsrmRoutingEngine({
    String? baseUrl,
    http.Client? client,
  })  : baseUrl = baseUrl ?? _defaultOsrmUrl,
        _client = client ?? http.Client();

  @override
  EngineInfo get info => const EngineInfo(name: 'osrm');

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/nearest/v1/driving/136.8815,35.1709');
      final response =
          await _client.get(uri).timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    final stopwatch = Stopwatch()..start();

    final coords =
        '${request.origin.longitude},${request.origin.latitude}'
        ';${request.destination.longitude},${request.destination.latitude}';

    final uri = Uri.parse(
      '$baseUrl/route/v1/driving/$coords'
      '?overview=full&geometries=polyline&steps=true',
    );

    try {
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 15));

      stopwatch.stop();

      if (response.statusCode != 200) {
        throw RoutingException(
          'OSRM route failed (${response.statusCode}): ${response.body}',
        );
      }

      // 0.3.3: a 200 response is not a promise of well-formed JSON. A proxy,
      // captive portal, or cache can return an HTML/error body with status 200.
      // 0.3.1 threw a raw FormatException/TypeError here, which escaped the
      // documented RoutingException contract and crashed the caller. Convert it
      // to a RoutingException a `^0.3.0` consumer already catches.
      final dynamic decoded;
      try {
        decoded = jsonDecode(response.body);
      } on FormatException {
        throw RoutingException('OSRM returned a non-JSON body (HTTP 200)');
      }
      if (decoded is! Map<String, dynamic>) {
        throw RoutingException('OSRM returned an unexpected JSON shape (HTTP 200)');
      }
      final json = decoded;

      final code = json['code'] as String?;
      if (code != 'Ok') {
        throw RoutingException(
          'OSRM error: ${json['message'] ?? code ?? 'unknown'}',
        );
      }

      return _parseRouteResponse(json, stopwatch.elapsed);
    } on http.ClientException catch (e) {
      throw RoutingException('OSRM network error: $e');
    }
  }

  RouteResult _parseRouteResponse(
    Map<String, dynamic> json,
    Duration latency,
  ) {
    // 0.3.3: crash backstop. The targeted guards above fix the high-reach
    // malformations (they still return a usable, flagged route). This wrapper
    // catches ANY residual parse throw — a non-object element, a numeric field
    // sent as a string, a shape this decoder cannot handle — and converts it to
    // the documented RoutingException instead of letting a raw
    // RangeError/TypeError/FormatException escape and crash the caller.
    // RoutingExceptions raised deliberately below pass through unchanged.
    try {
      return _parseRouteResponseImpl(json, latency);
    } on RoutingException {
      rethrow;
    } catch (e) {
      throw RoutingException(
        'OSRM returned a response this package could not parse: $e',
      );
    }
  }

  RouteResult _parseRouteResponseImpl(
    Map<String, dynamic> json,
    Duration latency,
  ) {
    final routes = json['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw RoutingException('OSRM returned no routes');
    }

    final route = routes[0] as Map<String, dynamic>;
    final geometry = route['geometry'] as String? ?? '';
    final distanceMeters = (route['distance'] as num?)?.toDouble() ?? 0;
    final durationSeconds = (route['duration'] as num?)?.toDouble() ?? 0;

    final shape = geometry.isNotEmpty ? _decodePolyline5(geometry) : <LatLng>[];

    final legs = route['legs'] as List<dynamic>? ?? [];
    final allManeuvers = <RouteManeuver>[];
    var maneuverIndex = 0;

    for (final leg in legs) {
      final legMap = leg as Map<String, dynamic>;
      final steps = legMap['steps'] as List<dynamic>? ?? [];

      for (final step in steps) {
        final stepMap = step as Map<String, dynamic>;
        final maneuver = stepMap['maneuver'] as Map<String, dynamic>? ?? {};
        final location = maneuver['location'] as List<dynamic>?;
        // 0.3.1: when OSRM omits or malforms `maneuver.location`, this used to
        // substitute `const LatLng(0, 0)` — Null Island, a real coordinate in the
        // Gulf of Guinea, thousands of kilometres from any route. Consumers had no
        // way to know it was fabricated: it is a valid LatLng like any other.
        //
        // We cannot know where the maneuver actually is. But we DO know it is
        // somewhere on this route, and the route shape is already decoded above.
        // So we clamp into the corridor: the last maneuver we placed, or the route
        // origin. The result may be imprecise — it can never be in an ocean.
        //
        // An imprecise point on her road is a small error. A confident point in the
        // Atlantic is a lie.
        // 0.3.2: the maneuver's own position is RESOLVED only when OSRM gave us
        // a well-formed `location`. When it did not, we still clamp into the
        // corridor (previous maneuver, or route origin) for backward
        // compatibility, but flag it `positionResolved: false` so the consumer
        // can refuse to narrate a place / distance it must not trust.
        // 0.3.3: a well-formed `location` must be TWO NUMBERS. 0.3.1 checked
        // only `length >= 2`, so a malformed `["a","b"]` threw a raw cast error
        // (`String` is not a `num`) that escaped RoutingException and crashed the
        // caller. Now a non-numeric location is treated as unresolved (clamped +
        // flagged), never a throw.
        final bool positionResolved = location != null &&
            location.length >= 2 &&
            location[0] is num &&
            location[1] is num;
        final LatLng? position = positionResolved
            ? LatLng(
                (location[1] as num).toDouble(),
                (location[0] as num).toDouble(),
              )
            : (allManeuvers.isNotEmpty
                ? allManeuvers.last.position
                : (shape.isNotEmpty ? shape.first : null));

        // If we cannot place this maneuver ANYWHERE truthful, we do not invent a
        // place for it. We drop it rather than hand the caller a coordinate we made
        // up. A missing turn is visible; a fabricated one is not.
        if (position == null) continue;

        final stepDistanceM = (stepMap['distance'] as num?)?.toDouble() ?? 0;
        final stepDurationS = (stepMap['duration'] as num?)?.toDouble() ?? 0;

        allManeuvers.add(RouteManeuver(
          index: maneuverIndex++,
          instruction: _buildInstruction(stepMap, maneuver),
          type: _mapModifierToType(maneuver),
          lengthKm: stepDistanceM / 1000,
          timeSeconds: stepDurationS,
          position: position,
          positionResolved: positionResolved,
        ));
      }
    }

    final totalDistanceKm = distanceMeters / 1000;

    return RouteResult(
      shape: shape,
      maneuvers: allManeuvers,
      totalDistanceKm: totalDistanceKm,
      totalTimeSeconds: durationSeconds,
      summary: '${totalDistanceKm.toStringAsFixed(1)} km, '
          '${(durationSeconds / 60).toStringAsFixed(0)} min',
      engineInfo: EngineInfo(
        name: 'osrm',
        queryLatency: latency,
      ),
    );
  }

  String _buildInstruction(
    Map<String, dynamic> step,
    Map<String, dynamic> maneuver,
  ) {
    final name = step['name'] as String? ?? '';
    final maneuverType = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';

    if (maneuverType == 'depart') {
      return name.isNotEmpty ? 'Depart on $name' : 'Depart';
    }
    if (maneuverType == 'arrive') {
      return 'Arrive at destination';
    }

    final direction = modifier.isNotEmpty
        ? modifier.replaceAll(' ', '_')
        : maneuverType;

    if (name.isNotEmpty) {
      return '${_capitalize(direction.replaceAll('_', ' '))} onto $name';
    }
    return _capitalize(direction.replaceAll('_', ' '));
  }

  String _mapModifierToType(Map<String, dynamic> maneuver) {
    final type = maneuver['type'] as String? ?? '';
    final modifier = maneuver['modifier'] as String? ?? '';

    if (type == 'depart') return 'depart';
    if (type == 'arrive') return 'arrive';
    if (type == 'roundabout' || type == 'rotary') return 'roundabout_enter';
    if (type == 'merge') return 'merge';
    if (type == 'on ramp' || type == 'off ramp') {
      return modifier.contains('right') ? 'ramp_right' : 'ramp_left';
    }

    return switch (modifier) {
      'left' => 'left',
      'slight left' => 'slight_left',
      'sharp left' => 'sharp_left',
      'right' => 'right',
      'slight right' => 'slight_right',
      'sharp right' => 'sharp_right',
      'straight' => 'straight',
      'uturn' => 'u_turn_left',
      _ => type.isNotEmpty ? type : 'straight',
    };
  }

  /// Decode polyline with precision 5 (OSRM default, 1e5).
  List<LatLng> _decodePolyline5(String encoded) {
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

      points.add(LatLng(lat / 1e5, lng / 1e5));
    }

    return points;
  }

  static String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  @override
  Future<void> dispose() async {
    _client.close();
  }
}
