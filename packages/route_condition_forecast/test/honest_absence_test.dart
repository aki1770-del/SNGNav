// The Measured-or-Absent contract at the ROUTE layer.
//
// This package is the supply line into `adaptive_reroute`. Up to 0.1.5 it had a
// `bool get hasAnyHazard`, and a `bool` cannot say "I do not know" — so a route
// whose every segment carried unmeasured weather answered **false**, meaning
// NOT hazardous, meaning *clear*. `adaptive_reroute` then emitted
// `RerouteDecision.clear()` with `confidence: 1.0`.
//
// A route nobody had looked at was reported to the driver as verified safe,
// with total certainty. These tests exist so that cannot come back.

import 'package:driving_weather/driving_weather.dart';
import 'package:latlong2/latlong.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:test/test.dart';

const _engineInfo = EngineInfo(name: 'test');
final _t = DateTime.utc(2026, 1, 15, 6, 30);

RouteResult _route(List<LatLng> shape, List<RouteManeuver> maneuvers) =>
    RouteResult(
      shape: shape,
      maneuvers: maneuvers,
      totalDistanceKm: 10,
      totalTimeSeconds: 600,
      summary: '',
      engineInfo: _engineInfo,
    );

RouteManeuver _m(int i, LatLng? p, {double km = 5.0}) => RouteManeuver(
      index: i,
      instruction: 'go',
      type: 'continue',
      lengthKm: km,
      timeSeconds: 300,
      position: p,
    );

/// A fully measured, genuinely benign condition.
WeatherCondition _measuredClear() => WeatherCondition(
      precipType: PrecipitationType.none,
      intensity: PrecipitationIntensity.none,
      temperatureCelsius: 5.0,
      visibilityMeters: 10000,
      windSpeedKmh: 0,
      iceRisk: false,
      source: ObservationSource.measured,
      timestamp: _t,
    );

Future<RouteForecast> _forecast(WeatherCondition c, RouteResult r) =>
    RouteConditionForecaster(
      forecastProvider: CurrentConditionsForecastProvider(c),
    ).forecast(r);

void main() {
  const p0 = LatLng(39.72, 140.10);
  const p1 = LatLng(39.80, 140.30);

  group('an UNMEASURED route is unknown — never clear', () {
    test('all-unknown weather → route hazard is unknown, NOT notHazardous',
        () async {
      final r = await _forecast(
        WeatherCondition.unknown(timestamp: _t),
        _route([p0, p1], [_m(0, p0)]),
      );
      expect(r.hazard, SafetyVerdict.unknown);
      expect(r.hazard, isNot(SafetyVerdict.notHazardous));
      // ...and the old API would have said "no hazard here", i.e. clear.
      expect(r.firstHazardSegment, isNull);
      // which is precisely why `firstHazardSegment == null` must never be read
      // as "clear". The unassessed segment is what tells the truth:
      expect(r.unassessedSegmentCount, 1);
      expect(r.firstUnassessedSegment, isNotNull);
    });

    test('segment-level: unknown condition → segment hazard unknown', () async {
      final r = await _forecast(
        WeatherCondition.unknown(timestamp: _t),
        _route([p0, p1], [_m(0, p0)]),
      );
      final seg = r.segments.single;
      expect(seg.hazard, SafetyVerdict.unknown);
      expect(seg.weatherHazard, SafetyVerdict.unknown);
      expect(seg.isUnassessed, isTrue);
    });

    test('ONE unknown segment poisons a route of otherwise-clear segments',
        () async {
      // A route is only as assessed as its least-assessed segment. If we could
      // not look at one stretch, we cannot tell the driver "the route is clear".
      final route = _route([p0, p1], [_m(0, p0), _m(1, p1)]);

      var call = 0;
      final r = await RouteConditionForecaster(
        forecastProvider: _AlternatingProvider(
          () => call++ == 0
              ? _measuredClear()
              : WeatherCondition.unknown(timestamp: _t),
        ),
      ).forecast(route);

      expect(r.segments.length, 2);
      expect(r.hazard, SafetyVerdict.unknown);
      expect(r.unassessedSegmentCount, 1);
    });

    test('an EMPTY forecast is unknown, not clear', () async {
      final r = await _forecast(_measuredClear(), _route([p0, p1], const []));
      expect(r.segments, isEmpty);
      expect(r.hazard, SafetyVerdict.unknown);
      expect(r.minimumConfidence, isNull); // was a fabricated 1.0
    });
  });

  group('POSITIVE evidence still fires on partial data', () {
    test('a hazardous segment fires even while other data is absent', () async {
      // Only an ice flag — no temperature, no visibility, no wind.
      final r = await _forecast(
        WeatherCondition(
          iceRisk: true,
          source: ObservationSource.measured,
          timestamp: _t,
        ),
        _route([p0, p1], [_m(0, p0)]),
      );
      expect(r.hazard, SafetyVerdict.hazardous);
      expect(r.firstHazardSegment, isNotNull);
    });
  });

  group('a route we could not fully LOCATE admits it', () {
    test('a positionless maneuver is skipped, and the gap is REPORTED',
        () async {
      // routing_engine 0.6.0: `position == null` means the engine gave us no
      // usable coordinate. Up to 0.5.0 it was silently `LatLng(0, 0)` — Null
      // Island — so we would have forecast the weather in the Gulf of Guinea and
      // attributed it to a road in Akita.
      final route = _route([p0, p1], [_m(0, p0), _m(1, null)]);

      final r = await _forecast(_measuredClear(), route);

      // The unlocatable maneuver yields no segment — it is not placed at (0,0).
      expect(r.segments.length, 1);

      // But the gap is not hidden: a short forecast reads exactly like a clear
      // one unless it says so.
      expect(r.unlocatableManeuverCount, 1);
      expect(r.coversWholeRoute, isFalse);

      // ...and because coverage is incomplete, the route is NOT declared clear,
      // even though every segment we DID forecast came back benign.
      expect(r.hazard, SafetyVerdict.unknown);
    });
  });

  group('NO CRYING WOLF — a fully measured, fully located route still clears',
      () {
    test('measured-clear + all maneuvers located → notHazardous', () async {
      final r = await _forecast(
        _measuredClear(),
        _route([p0, p1], [_m(0, p0), _m(1, p1)]),
      );
      expect(r.coversWholeRoute, isTrue);
      expect(r.hazard, SafetyVerdict.notHazardous);
      expect(r.unassessedSegmentCount, 0);
      expect(r.minimumConfidence, isNotNull);
    });
  });
}

/// Returns a different condition on each call, so a route's segments can carry
/// a MIX of measured and unmeasured weather.
class _AlternatingProvider implements ForecastProvider {
  _AlternatingProvider(this._next);
  final WeatherCondition Function() _next;

  @override
  Future<WeatherCondition> forecastAt(
    LatLng position, {
    required double etaSeconds,
  }) async =>
      _next();
}
