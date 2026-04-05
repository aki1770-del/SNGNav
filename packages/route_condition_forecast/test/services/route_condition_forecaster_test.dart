import 'package:driving_weather/driving_weather.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:test/test.dart';

const _engineInfo = EngineInfo(name: 'mock');

RouteManeuver _m(int i, LatLng pos, {double km = 5.0, double t = 300}) =>
    RouteManeuver(
      index: i,
      instruction: 'Step $i',
      type: i == 0 ? 'depart' : 'straight',
      lengthKm: km,
      timeSeconds: t,
      position: pos,
    );

RouteResult _route(List<LatLng> shape, List<RouteManeuver> maneuvers) =>
    RouteResult(
      shape: shape,
      maneuvers: maneuvers,
      totalDistanceKm: maneuvers.fold(0, (s, m) => s + m.lengthKm),
      totalTimeSeconds: maneuvers.fold(0, (s, m) => s + m.timeSeconds),
      summary: 'test route',
      engineInfo: _engineInfo,
    );

void main() {
  final t = DateTime.utc(2026, 4, 5);

  late WeatherCondition clear;
  late WeatherCondition icy;

  setUp(() {
    clear = WeatherCondition(
      precipType: PrecipitationType.none,
      intensity: PrecipitationIntensity.none,
      temperatureCelsius: 15.0,
      visibilityMeters: 10000,
      windSpeedKmh: 0,
      iceRisk: false,
      timestamp: t,
    );
    icy = WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -3.0,
      visibilityMeters: 50,
      windSpeedKmh: 30,
      iceRisk: true,
      timestamp: t,
    );
  });

  group('RouteConditionForecaster', () {
    test('empty route produces empty forecast', () async {
      final empty = RouteResult(
        shape: const [],
        maneuvers: const [],
        totalDistanceKm: 0,
        totalTimeSeconds: 0,
        summary: '',
        engineInfo: _engineInfo,
      );
      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
      );
      final result = await forecaster.forecast(empty);
      expect(result.segments, isEmpty);
      expect(result.hasAnyHazard, isFalse);
    });

    test('clear conditions produce non-hazardous forecast', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      final route = _route([p0, p1], [_m(0, p0, km: 10.0)]);

      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
      );
      final result = await forecaster.forecast(route);

      expect(result.hasAnyHazard, isFalse);
      expect(result.firstHazardSegment, isNull);
      expect(result.firstHazardEtaSeconds, isNull);
    });

    test('icy conditions produce hazardous forecast', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      final route = _route([p0, p1], [_m(0, p0, km: 5.0)]);

      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(icy),
      );
      final result = await forecaster.forecast(route);

      expect(result.hasAnyHazard, isTrue);
      expect(result.hasWeatherHazard, isTrue);
      expect(result.firstHazardSegment, isNotNull);
      expect(result.firstHazardEtaSeconds, closeTo(0.0, 1e-9));
    });

    test('ETA accumulates across segments', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      const p2 = LatLng(35.2, 136.2);
      // Two 30 km segments at 60 km/h → 1800s each
      final route = _route(
        [p0, p1, p2],
        [_m(0, p0, km: 30.0), _m(1, p1, km: 30.0)],
      );

      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
        speedKmh: 60.0,
      );
      final result = await forecaster.forecast(route);

      expect(result.segments.length, 2);
      expect(result.segments[0].etaSeconds, closeTo(0.0, 1e-9));
      // Second segment ETA = 30 km / 60 km/h * 3600 = 1800s
      expect(result.segments[1].etaSeconds, closeTo(1800.0, 1e-3));
    });

    test('confidence at segment 0 is 1.0', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      final route = _route([p0, p1], [_m(0, p0, km: 5.0)]);
      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
      );
      final result = await forecaster.forecast(route);
      expect(result.segments.first.confidence, closeTo(1.0, 1e-9));
    });

    test('confidence degrades for far-ahead segments', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      const p2 = LatLng(35.2, 136.2);
      // 480 km at 60 km/h = 8h ETA for second segment
      final route = _route(
        [p0, p1, p2],
        [_m(0, p0, km: 480.0), _m(1, p1, km: 5.0)],
      );
      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
        speedKmh: 60.0,
      );
      final result = await forecaster.forecast(route);
      expect(result.segments.last.confidence, lessThan(1.0));
      expect(result.segments.last.confidence, greaterThanOrEqualTo(0.1));
    });

    test('fleet hazard zone intersecting segment is detected', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      // Zone centered exactly at segment midpoint
      const midLat = (35.0 + 35.1) / 2;
      const midLng = (136.0 + 136.1) / 2;
      final zone = HazardZone(
        center: const LatLng(midLat, midLng),
        radiusMeters: 2000,
        severity: HazardSeverity.icy,
        reports: [
          FleetReport(
            vehicleId: 'v1',
            position: const LatLng(midLat, midLng),
            timestamp: DateTime.utc(2026, 4, 5),
            condition: RoadCondition.icy,
          ),
        ],
      );

      final route = _route([p0, p1], [_m(0, p0, km: 12.0)]);
      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
        hazardZones: [zone],
      );
      final result = await forecaster.forecast(route);

      expect(result.hasFleetHazard, isTrue);
      expect(result.firstHazardSegment, isNotNull);
      expect(result.segments.first.hazardZones, contains(zone));
    });

    test('fleet hazard zone not on route is ignored', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      // Zone far from the route
      final zone = HazardZone(
        center: const LatLng(36.5, 138.0),
        radiusMeters: 500,
        severity: HazardSeverity.icy,
        reports: [
          FleetReport(
            vehicleId: 'v1',
            position: const LatLng(36.5, 138.0),
            timestamp: DateTime.utc(2026, 4, 5),
            condition: RoadCondition.icy,
          ),
        ],
      );

      final route = _route([p0, p1], [_m(0, p0, km: 10.0)]);
      final forecaster = RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
        hazardZones: [zone],
      );
      final result = await forecaster.forecast(route);
      expect(result.hasFleetHazard, isFalse);
    });

    test('generatedAt is set', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      final route = _route([p0, p1], [_m(0, p0)]);
      final before = DateTime.now().toUtc();
      final result = await RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(clear),
      ).forecast(route);
      final after = DateTime.now().toUtc();
      expect(result.generatedAt.isAfter(before) || result.generatedAt == before, isTrue);
      expect(result.generatedAt.isBefore(after) || result.generatedAt == after, isTrue);
    });

    test('hazardSegmentCount counts correctly', () async {
      const p0 = LatLng(35.0, 136.0);
      const p1 = LatLng(35.1, 136.1);
      const p2 = LatLng(35.2, 136.2);
      final route = _route([p0, p1, p2], [_m(0, p0), _m(1, p1)]);
      final result = await RouteConditionForecaster(
        forecastProvider: CurrentConditionsForecastProvider(icy),
      ).forecast(route);
      expect(result.hazardSegmentCount, 2);
    });
  });
}
