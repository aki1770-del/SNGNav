// Regression tests for the 0.1.6 fix: placeholder / corrupt positions
// ((0, 0) or non-finite) must never produce detour bearings, and must
// never be reported as clear with confidence 1.0.

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

HazardZone _zone(LatLng center, {double radius = 500}) => HazardZone(
      center: center,
      radiusMeters: radius,
      severity: HazardSeverity.icy,
      vehicleCount: 1,
      reports: [
        ZoneObservation(
          position: center,
          timestamp: DateTime.utc(2026, 4, 5),
          condition: RoadCondition.icy,
          confidence: 0.8,
        ),
      ],
    );

void main() {
  const origin = LatLng(35.0, 136.0);
  const p1 = LatLng(35.1, 136.0);
  const p2 = LatLng(35.2, 136.0);
  const nullIsland = LatLng(0.0, 0.0);

  group('RerouteDecision.cannotAssess', () {
    test('carries no-reroute, zero confidence, no waypoints', () {
      const d = RerouteDecision.cannotAssess(reason: 'Segment 3 unusable');
      expect(d.shouldReroute, isFalse);
      expect(d.confidence, 0.0);
      expect(d.detourWaypoints, isEmpty);
      expect(d.reason, contains('Segment 3'));
      expect(d.triggerSegment, isNull);
    });
  });

  group('RerouteEvaluator with unusable positions', () {
    test(
        'hazardous trigger whose segment.start is (0,0) → cannotAssess, '
        'never a detour waypoint', () {
      final forecast = _forecast([
        _seg(
          index: 0,
          start: nullIsland,
          end: p1,
          hazardous: true,
          zones: [_zone(const LatLng(35.05, 136.0))],
          eta: 120,
        ),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.detourWaypoints, isEmpty);
      expect(decision.confidence, 0.0);
      expect(decision.reason, contains('could not be assessed'));
      expect(decision.reason, contains('Segment 0'));
    });

    test(
        'route containing a (0,0)-endpoint segment never returns '
        'clear with confidence 1.0', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: false),
        _seg(index: 1, start: p1, end: nullIsland, hazardous: false),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision, isNot(equals(const RerouteDecision.clear())));
      expect(decision.reason, isNot(contains('Route is clear')));
      expect(decision.confidence, 0.0);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('could not be assessed'));
      expect(decision.reason, contains('Segment 1'));
    });

    test('non-finite segment endpoint → cannotAssess', () {
      final forecast = _forecast([
        _seg(
          index: 0,
          start: origin,
          end: const LatLng(double.nan, 136.0),
          hazardous: true,
          eta: 120,
        ),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.detourWaypoints, isEmpty);
      expect(decision.confidence, 0.0);
      expect(decision.reason, contains('could not be assessed'));
    });

    test('(0,0) current position → cannotAssess, no bearing math', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: true, eta: 120),
      ]);
      final decision = const RerouteEvaluator()
          .evaluate(forecast, currentPosition: nullIsland);
      expect(decision.shouldReroute, isFalse);
      expect(decision.detourWaypoints, isEmpty);
      expect(decision.confidence, 0.0);
      expect(decision.reason, contains('Current position'));
    });

    test('multiple poisoned segments are counted in the reason', () {
      final forecast = _forecast([
        _seg(index: 0, start: nullIsland, end: p1, hazardous: false),
        _seg(index: 1, start: p1, end: nullIsland, hazardous: false),
        _seg(index: 2, start: p1, end: p2, hazardous: false),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.confidence, 0.0);
      expect(decision.reason, contains('Segment 0'));
      expect(decision.reason, contains('1 more segment'));
    });

    test('well-located route still evaluates exactly as before', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, hazardous: true, eta: 120),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.triggerSegment!.segment.index, 0);
    });
  });

  group('DetourPlanner with unusable input', () {
    const planner = DetourPlanner();

    test('zone centred at (0,0) yields no waypoints', () {
      final waypoints =
          planner.plan([_zone(nullIsland)], approachBearing: 45.0);
      expect(waypoints, isEmpty);
    });

    test('non-finite zone centre or radius is skipped, valid zone kept', () {
      final waypoints = planner.plan(
        [
          _zone(const LatLng(double.infinity, 136.0)),
          _zone(const LatLng(35.05, 136.0), radius: double.nan),
          _zone(const LatLng(35.05, 136.0)),
        ],
        approachBearing: 45.0,
      );
      expect(waypoints, hasLength(2));
      for (final w in waypoints) {
        expect(w.position.latitude.isFinite, isTrue);
        expect(w.position.longitude.isFinite, isTrue);
      }
    });

    test('non-finite approach bearing yields no waypoints', () {
      final waypoints = planner.plan(
        [_zone(const LatLng(35.05, 136.0))],
        approachBearing: double.nan,
      );
      expect(waypoints, isEmpty);
    });
  });
}
