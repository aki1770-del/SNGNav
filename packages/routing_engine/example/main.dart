import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';

void main() async {
  final engine = ExampleRoutingEngine();
  final request = const RouteRequest(
    origin: LatLng(35.1709, 136.9066),
    destination: LatLng(34.9551, 137.1771),
  );

  if (await engine.isAvailable()) {
    final route = await engine.calculateRoute(request);
    print(route.summary);
    print('distance: ${route.totalDistanceKm}km');
    print('maneuvers: ${route.maneuvers.length}');
    print('engine: ${route.engineInfo.name}');
  }

  await engine.dispose();
}

class ExampleRoutingEngine implements RoutingEngine {
  @override
  EngineInfo get info => const EngineInfo(
        name: 'example-engine',
        version: '0.1.0',
        queryLatency: Duration(milliseconds: 6),
      );

  @override
  Future<RouteResult> calculateRoute(RouteRequest request) async {
    return RouteResult(
      shape: [request.origin, request.destination],
      maneuvers: [
        RouteManeuver(
          index: 0,
          instruction: 'Depart from Sakae Station',
          type: 'depart',
          lengthKm: 0.0,
          timeSeconds: 0.0,
          position: request.origin,
        ),
        RouteManeuver(
          index: 1,
          instruction: 'Arrive at Higashiokazaki Station',
          type: 'arrive',
          lengthKm: 38.7,
          timeSeconds: 2860,
          position: request.destination,
        ),
      ],
      totalDistanceKm: 38.7,
      totalTimeSeconds: 2860,
      summary: 'Example route from ${request.origin} to ${request.destination}',
      engineInfo: info,
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  Future<bool> isAvailable() async => true;
}