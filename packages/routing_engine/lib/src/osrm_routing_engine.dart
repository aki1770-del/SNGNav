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
import 'maneuver_localizer.dart';
import 'route_result.dart';
import 'routing_engine.dart';

const _defaultOsrmUrl = 'http://localhost:5000';

class OsrmRoutingEngine implements RoutingEngine {
  final String baseUrl;
  final http.Client _client;

  OsrmRoutingEngine({String? baseUrl, http.Client? client})
    : baseUrl = baseUrl ?? _defaultOsrmUrl,
      _client = client ?? http.Client();

  @override
  EngineInfo get info => const EngineInfo(name: 'osrm');

  @override
  Future<bool> isAvailable() async {
    try {
      final uri = Uri.parse('$baseUrl/nearest/v1/driving/136.8815,35.1709');
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 3));
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

      // Decode the bytes as UTF-8 explicitly: response.body honors the
      // content-type charset header and falls back to Latin-1 when a server
      // omits it — which would mangle Japanese street names. OSRM responses
      // are UTF-8 JSON regardless of header.
      final json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      final code = json['code'] as String?;
      if (code != 'Ok') {
        throw RoutingException(
          'OSRM error: ${json['message'] ?? code ?? 'unknown'}',
        );
      }

      return _parseRouteResponse(json, stopwatch.elapsed, request.language);
    } on RoutingException {
      rethrow;
    } on Exception catch (e) {
      throw RoutingException('OSRM network error: $e');
    }
  }

  RouteResult _parseRouteResponse(
    Map<String, dynamic> json,
    Duration latency,
    String language,
  ) {
    final routes = json['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) {
      throw RoutingException('OSRM returned no routes');
    }

    final route = routes[0] as Map<String, dynamic>;
    final geometry = route['geometry'] as String? ?? '';
    // Absence of a distance is absence of a measurement — never a measured
    // zero. Up to 0.5.1 an omitted `distance`/`duration` coalesced to 0 and was
    // rendered to the driver as "0.0 km, 0 min": a figure OSRM never sent.
    // Backported from 0.6.1 so consumers pinned to ^0.5.x receive it too.
    final distanceRaw = route['distance'] as num?;
    final durationRaw = route['duration'] as num?;
    if (distanceRaw == null) {
      throw RoutingException('OSRM route carried no distance');
    }
    if (durationRaw == null) {
      throw RoutingException('OSRM route carried no duration');
    }
    final distanceMeters = distanceRaw.toDouble();
    final durationSeconds = durationRaw.toDouble();

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
        // A maneuver whose location OSRM did not give us has no position.
        // Up to 0.5.0 this substituted const LatLng(0, 0) — Null Island, off
        // the coast of Africa — presenting a fabricated coordinate as a real
        // place. 0.5.1 skips the maneuver instead: no coordinate is emitted
        // for a maneuver that cannot be located. Route geometry, distance
        // and duration are unaffected.
        final hasPair = location != null && location.length >= 2;
        if (!hasPair || location[0] is! num || location[1] is! num) {
          continue;
        }
        final position = LatLng(
          (location[1] as num).toDouble(),
          (location[0] as num).toDouble(),
        );

        final stepDistanceM = (stepMap['distance'] as num?)?.toDouble() ?? 0;
        final stepDurationS = (stepMap['duration'] as num?)?.toDouble() ?? 0;

        allManeuvers.add(
          RouteManeuver(
            index: maneuverIndex++,
            instruction: _localizedInstruction(stepMap, maneuver, language),
            type: _mapModifierToType(maneuver),
            lengthKm: stepDistanceM / 1000,
            timeSeconds: stepDurationS,
            position: position,
          ),
        );
      }
    }

    final totalDistanceKm = distanceMeters / 1000;

    return RouteResult(
      shape: shape,
      maneuvers: allManeuvers,
      totalDistanceKm: totalDistanceKm,
      totalTimeSeconds: durationSeconds,
      summary:
          '${totalDistanceKm.toStringAsFixed(1)} km, '
          '${(durationSeconds / 60).toStringAsFixed(0)} min',
      engineInfo: EngineInfo(name: 'osrm', queryLatency: latency),
    );
  }

  /// Build the localized instruction for the requested [language], degrading
  /// to the engine's own English phrasing when the locale/type is unsupported.
  String _localizedInstruction(
    Map<String, dynamic> step,
    Map<String, dynamic> maneuver,
    String language,
  ) {
    final name = step['name'] as String? ?? '';
    return ManeuverLocalizer.localize(
      language: language,
      type: _mapModifierToType(maneuver),
      streetName: name,
      // OSRM supplies the 1-based exit ordinal on roundabout maneuvers.
      roundaboutExit: (maneuver['exit'] as num?)?.toInt(),
      englishFallback: () => _buildInstruction(step, maneuver),
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
    if (type == 'exit roundabout' || type == 'exit rotary') {
      return 'roundabout_exit';
    }
    if (type == 'merge') return 'merge';
    if (type == 'on ramp' || type == 'off ramp') {
      // Only claim a side the engine actually stated — a fabricated side is a
      // wrong direction on a road, the one thing the localizer must never say.
      if (modifier.contains('right')) return 'ramp_right';
      if (modifier.contains('left')) return 'ramp_left';
      return 'ramp';
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
      // No type and no modifier: do NOT synthesize 'straight' — the maneuver
      // may really be a turn. 'proceed' defers to the road (道なりに進む).
      _ => type.isNotEmpty ? type : 'proceed',
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
