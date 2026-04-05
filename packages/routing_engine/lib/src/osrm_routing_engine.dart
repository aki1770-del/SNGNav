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

      final json = jsonDecode(response.body) as Map<String, dynamic>;

      final code = json['code'] as String?;
      if (code != 'Ok') {
        throw RoutingException(
          'OSRM error: ${json['message'] ?? code ?? 'unknown'}',
        );
      }

      return _parseRouteResponse(json, stopwatch.elapsed);
    } on RoutingException {
      rethrow;
    } on Exception catch (e) {
      throw RoutingException('OSRM network error: $e');
    }
  }

  RouteResult _parseRouteResponse(
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
        final position = location != null && location.length >= 2
            ? LatLng(
                (location[1] as num).toDouble(),
                (location[0] as num).toDouble(),
              )
            : const LatLng(0, 0);

        final stepDistanceM = (stepMap['distance'] as num?)?.toDouble() ?? 0;
        final stepDurationS = (stepMap['duration'] as num?)?.toDouble() ?? 0;

        allManeuvers.add(RouteManeuver(
          index: maneuverIndex++,
          instruction: _buildInstruction(stepMap, maneuver),
          type: _mapModifierToType(maneuver),
          lengthKm: stepDistanceM / 1000,
          timeSeconds: stepDurationS,
          position: position,
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
