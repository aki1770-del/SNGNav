import 'package:driving_weather/driving_weather.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:adaptive_reroute/adaptive_reroute.dart';
import 'package:test/test.dart';

const _engineInfo = EngineInfo(name: 'mock');

RouteResult _route(List<LatLng> shape, List<RouteManeuver> maneuvers) =>
    RouteResult(
      shape: shape,
      maneuvers: maneuvers,
      totalDistanceKm: maneuvers.fold(0, (s, m) => s + m.lengthKm),
      totalTimeSeconds: maneuvers.fold(0, (s, m) => s + m.timeSeconds),
      summary: 'test',
      engineInfo: _engineInfo,
    );

RouteManeuver _m(int i, LatLng pos, {double km = 5.0, double t = 300}) =>
    RouteManeuver(
      index: i,
      instruction: 'Step $i',
      type: 'straight',
      lengthKm: km,
      timeSeconds: t,
      position: pos,
    );

SegmentConditionForecast _seg({
  required int index,
  required LatLng start,
  required LatLng end,
  required bool hazardous,
  List<HazardZone> zones = const [],
  double eta = 0,
  double confidence = 0.9,
}) {
  final t = DateTime.utc(2026, 4, 5);
  final condition = hazardous
      ? WeatherCondition(
          precipType: PrecipitationType.snow,
          intensity: PrecipitationIntensity.heavy,
          temperatureCelsius: -3,
          visibilityMeters: 50,
          windSpeedKmh: 30,
          iceRisk: true,
          timestamp: t,
        )
      : WeatherCondition(
          precipType: PrecipitationType.none,
          intensity: PrecipitationIntensity.none,
          temperatureCelsius: 15,
          visibilityMeters: 10000,
          windSpeedKmh: 0,
          iceRisk: false,
          timestamp: t,
        );
  return SegmentConditionForecast(
    segment: RouteSegment(index: index, start: start, end: end, distanceKm: 5),
    condition: condition,
    hazardZones: zones,
    etaSeconds: eta,
    confidence: confidence,
  );
}

RouteForecast _forecast(List<SegmentConditionForecast> segs) {
  const p0 = LatLng(35.0, 136.0);
  const p1 = LatLng(35.1, 136.1);
  final route = _route([p0, p1], [_m(0, p0)]);
  return RouteForecast(
    route: route,
    segments: segs,
    generatedAt: DateTime.utc(2026, 4, 5),
  );
}

void main() {
  const origin = LatLng(35.0, 136.0);
  const p1 = LatLng(35.1, 136.0);
  const p2 = LatLng(35.2, 136.0);

  group('RerouteEvaluator', () {
    test('clear forecast → no reroute', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: false),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('clear'));
    });

    test('hazardous segment within window → reroute', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: true, eta: 600),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.triggerSegment, isNotNull);
    });

    test('hazardous segment beyond window → no reroute', () {
      const config = AdaptiveRerouteConfig(hazardWindowSeconds: 300);
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: true, eta: 3600),
      ]);
      final decision =
          RerouteEvaluator(config: config).evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('window'));
    });

    test('low confidence hazard → no reroute', () {
      const config = AdaptiveRerouteConfig(minConfidenceToAct: 0.6);
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            hazardous: true,
            eta: 300,
            confidence: 0.3),
      ]);
      final decision =
          RerouteEvaluator(config: config).evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('confidence'));
    });

    test('reroute decision carries trigger segment', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: true, eta: 120),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(decision.triggerSegment, isNotNull);
      expect(decision.triggerSegment!.segment.index, 0);
    });

    test('fleet hazard generates detour waypoints', () {
      const hazardCenter = LatLng(35.05, 136.0);
      final zone = HazardZone(
        center: hazardCenter,
        radiusMeters: 500,
        severity: HazardSeverity.icy,
        reports: [
          FleetReport(
            vehicleId: 'v1',
            position: hazardCenter,
            timestamp: DateTime.utc(2026, 4, 5),
            condition: RoadCondition.icy,
          ),
        ],
      );
      final forecast = _forecast([
        _seg(
          index: 0,
          start: origin,
          end: p1,
          hazardous: false,
          zones: [zone],
          eta: 300,
          confidence: 0.9,
        ),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.detourWaypoints, hasLength(2));
    });

    test('weather-only hazard reason contains ice or hazard keyword', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: true, eta: 120),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(
        decision.reason.toLowerCase(),
        anyOf(contains('ice'), contains('hazard')),
      );
    });

    test('confidence of decision matches trigger segment confidence', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            hazardous: true,
            eta: 60,
            confidence: 0.75),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(decision.confidence, closeTo(0.75, 1e-9));
    });

    test('first hazardous segment in multi-segment forecast is trigger', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: false, eta: 0),
        _seg(index: 1, start: p1, end: p2, hazardous: true, eta: 300),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.triggerSegment!.segment.index, 1);
    });
  });
}
