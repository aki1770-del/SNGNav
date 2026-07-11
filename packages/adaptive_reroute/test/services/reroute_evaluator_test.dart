import 'package:driving_weather/driving_weather.dart';
import 'package:fleet_hazard/fleet_hazard.dart';
import 'package:latlong2/latlong.dart';
import 'package:routing_engine/routing_engine.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'package:adaptive_reroute/adaptive_reroute.dart';
import 'package:test/test.dart';

const _engineInfo = EngineInfo(name: 'mock');
final _t = DateTime.utc(2026, 4, 5);

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

// --- Condition fixtures -----------------------------------------------------

/// Measured, and unambiguously hazardous.
WeatherCondition _measuredHazard() => WeatherCondition(
      precipType: PrecipitationType.snow,
      intensity: PrecipitationIntensity.heavy,
      temperatureCelsius: -3,
      visibilityMeters: 50,
      windSpeedKmh: 30,
      iceRisk: true,
      source: ObservationSource.measured,
      timestamp: _t,
    );

/// Measured, COMPLETE, and not hazardous. The only kind of condition from which
/// an "all clear" may honestly be derived.
WeatherCondition _measuredClear() => WeatherCondition(
      precipType: PrecipitationType.none,
      intensity: PrecipitationIntensity.none,
      temperatureCelsius: 15,
      visibilityMeters: 10000,
      windSpeedKmh: 0,
      iceRisk: false,
      source: ObservationSource.measured,
      timestamp: _t,
    );

/// Nothing measured at all — the empty-feed / offline / coverage-gap case.
WeatherCondition _unknownCondition() => WeatherCondition.unknown(timestamp: _t);

/// Ice is known; NOTHING else is. Proves the caution-add-only asymmetry.
WeatherCondition _iceOnly() => WeatherCondition(
      iceRisk: true,
      source: ObservationSource.measured,
      timestamp: _t,
    );

/// A road authority DECLARED a severe situation; it measured no temperature, no
/// visibility, no wind. This is the Digitraffic shape.
WeatherCondition _severeAssertionOnly() => WeatherCondition(
      hazardAssertion: HazardAssertion.severe,
      source: ObservationSource.measured,
      timestamp: _t,
    );

SegmentConditionForecast _seg({
  required int index,
  required LatLng start,
  required LatLng end,
  required WeatherCondition condition,
  List<HazardZone> zones = const [],
  double eta = 0,
  double confidence = 0.9,
}) =>
    SegmentConditionForecast(
      segment:
          RouteSegment(index: index, start: start, end: end, distanceKm: 5),
      condition: condition,
      hazardZones: zones,
      etaSeconds: eta,
      confidence: confidence,
    );

RouteForecast _forecast(List<SegmentConditionForecast> segs) {
  const p0 = LatLng(35.0, 136.0);
  const p1 = LatLng(35.1, 136.1);
  final route = _route([p0, p1], [_m(0, p0)]);
  return RouteForecast(
    route: route,
    segments: segs,
    generatedAt: _t,
  );
}

HazardZone _zone(LatLng center) => HazardZone(
      center: center,
      radiusMeters: 500,
      severity: HazardSeverity.icy,
      vehicleCount: 1,
      reports: [
        ZoneObservation(
          position: center,
          timestamp: _t,
          condition: RoadCondition.icy,
          confidence: 0.8,
        ),
      ],
    );

void main() {
  const origin = LatLng(35.0, 136.0);
  const p1 = LatLng(35.1, 136.0);
  const p2 = LatLng(35.2, 136.0);

  group('RerouteEvaluator — hazard path (behaviour preserved)', () {
    test('hazardous segment within window → reroute', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredHazard(),
            eta: 600),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.triggerSegment, isNotNull);
      expect(decision.isAssessed, isTrue);
    });

    test('hazardous segment beyond window → no reroute', () {
      const config = AdaptiveRerouteConfig(hazardWindowSeconds: 300);
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredHazard(),
            eta: 3600),
      ]);
      final decision = RerouteEvaluator(config: config)
          .evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('window'));
      // Still an ASSESSED decision — we saw the hazard, we are simply not
      // acting on it yet. That is not the same as "could not look".
      expect(decision.isAssessed, isTrue);
    });

    test('low confidence hazard → no reroute', () {
      const config = AdaptiveRerouteConfig(minConfidenceToAct: 0.6);
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredHazard(),
            eta: 300,
            confidence: 0.3),
      ]);
      final decision = RerouteEvaluator(config: config)
          .evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('confidence'));
    });

    test('reroute decision carries trigger segment', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredHazard(),
            eta: 120),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.triggerSegment, isNotNull);
      expect(decision.triggerSegment!.segment.index, 0);
    });

    test('fleet hazard generates detour waypoints', () {
      final forecast = _forecast([
        _seg(
          index: 0,
          start: origin,
          end: p1,
          condition: _measuredClear(),
          zones: [_zone(const LatLng(35.05, 136.0))],
          eta: 300,
          confidence: 0.9,
        ),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.detourWaypoints, hasLength(2));
    });

    test('weather-only hazard reason contains ice or hazard keyword', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredHazard(),
            eta: 120),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
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
            condition: _measuredHazard(),
            eta: 60,
            confidence: 0.75),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.confidence, closeTo(0.75, 1e-9));
    });

    test('first hazardous segment in multi-segment forecast is trigger', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredClear(),
            eta: 0),
        _seg(
            index: 1,
            start: p1,
            end: p2,
            condition: _measuredHazard(),
            eta: 300),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.triggerSegment!.segment.index, 1);
    });
  });

  // ===========================================================================
  // THE DEFECT. Before 0.2.0 every case in this group returned
  // `RerouteDecision.clear()` — reason "Route is clear", confidence 1.0.
  // ===========================================================================
  group('RerouteEvaluator — absence is never an all-clear (the 0.2.0 fix)', () {
    test('unknown conditions → cannotAssess, NOT "route is clear"', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _unknownCondition(),
            eta: 300),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);

      // The regression that shipped: absence read as a confident all-clear.
      expect(decision.confidence, isNull,
          reason: 'absent conditions must never yield a confidence value');
      expect(decision.isAssessed, isFalse);
      expect(decision.reason.toLowerCase(), contains('unknown'));
      expect(decision.reason.toLowerCase(), isNot(contains('clear')));

      // No detour is recommended — but because we have no grounds, NOT because
      // the road is good.
      expect(decision.shouldReroute, isFalse);
      expect(decision.detourWaypoints, isEmpty);
    });

    test('unknown conditions never produce confidence 1.0', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, condition: _unknownCondition()),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.confidence, isNot(1.0));
      expect(decision.confidence, isNull);
    });

    test('empty forecast (nothing assessed) → cannotAssess', () {
      final decision = const RerouteEvaluator()
          .evaluate(_forecast(const []), currentPosition: origin);
      expect(decision.isAssessed, isFalse);
      expect(decision.confidence, isNull);
      expect(decision.shouldReroute, isFalse);
      expect(decision.reason.toLowerCase(), contains('no segments'));
      // No driver-facing reason for an unseen route may contain the word
      // "clear" — a truncating or keyword-matching HMI must not be able to
      // render it as an all-clear.
      expect(decision.reason.toLowerCase(), isNot(contains('clear')));
    });

    test('ONE unknown segment among known-clear ones defeats the all-clear',
        () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, condition: _measuredClear()),
        _seg(index: 1, start: p1, end: p2, condition: _unknownCondition()),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.isAssessed, isFalse);
      expect(decision.reason, contains('1 of 2'));
    });

    test(
        'a hazard elsewhere does not erase an unknown segment from the reason',
        () {
      // Near segment: NOT observed. Far segment: a known hazard, but beyond the
      // look-ahead window, so no reroute is recommended. An integrator that
      // renders this as "nothing to do" must still be told the near road was
      // never seen.
      const config = AdaptiveRerouteConfig(hazardWindowSeconds: 300);
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _unknownCondition(),
            eta: 60),
        _seg(
            index: 1,
            start: p1,
            end: p2,
            condition: _measuredHazard(),
            eta: 3600),
      ]);
      final decision = RerouteEvaluator(config: config)
          .evaluate(forecast, currentPosition: origin);

      expect(decision.shouldReroute, isFalse);
      expect(decision.reason, contains('window'));
      expect(decision.reason, contains('conditions unknown for 1 of 2'));
    });

    test('all segments known and clear → noHazardFound, assessed, conf < 1.0',
        () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _measuredClear(),
            confidence: 0.8),
        _seg(
            index: 1,
            start: p1,
            end: p2,
            condition: _measuredClear(),
            confidence: 0.6),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);

      expect(decision.shouldReroute, isFalse);
      expect(decision.isAssessed, isTrue);
      // Inherited from the WEAKEST segment — never a manufactured 1.0.
      expect(decision.confidence, closeTo(0.6, 1e-9));
      expect(decision.reason, contains('No hazard found'));
    });
  });

  group('RerouteEvaluator — caution-add-only asymmetry', () {
    test('ice known, everything else absent → still hazardous → reroute', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, condition: _iceOnly(), eta: 300),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue,
          reason: 'positive evidence must fire on partial data');
      expect(decision.reason.toLowerCase(), contains('ice'));
    });

    test('severe authority assertion with NO measured fields → hazardous', () {
      final forecast = _forecast([
        _seg(
            index: 0,
            start: origin,
            end: p1,
            condition: _severeAssertionOnly(),
            eta: 300),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      // Not an ice reason — nothing measured ice. The generic hazard reason.
      expect(decision.reason.toLowerCase(), contains('hazard'));
    });

    test('fleet hazard zone fires even when the weather is UNKNOWN', () {
      final forecast = _forecast([
        _seg(
          index: 0,
          start: origin,
          end: p1,
          condition: _unknownCondition(),
          zones: [_zone(const LatLng(35.05, 136.0))],
          eta: 300,
        ),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue,
          reason: 'a human-reported hazard is evidence even with no weather');
      expect(decision.detourWaypoints, hasLength(2));
      expect(decision.reason.toLowerCase(), contains('fleet'));
    });

    test('a known hazard outranks an unknown segment (hazard wins)', () {
      final forecast = _forecast([
        _seg(index: 0, start: origin, end: p1, condition: _unknownCondition()),
        _seg(
            index: 1,
            start: p1,
            end: p2,
            condition: _measuredHazard(),
            eta: 300),
      ]);
      final decision =
          const RerouteEvaluator().evaluate(forecast, currentPosition: origin);
      expect(decision.shouldReroute, isTrue);
      expect(decision.triggerSegment!.segment.index, 1);
    });
  });

  group('RerouteEvaluator.verdictFor', () {
    const e = RerouteEvaluator();

    test('measured + clear → notHazardous', () {
      expect(
        e.verdictFor(_seg(
            index: 0, start: origin, end: p1, condition: _measuredClear())),
        SafetyVerdict.notHazardous,
      );
    });

    test('nothing measured → unknown (NOT notHazardous)', () {
      expect(
        e.verdictFor(_seg(
            index: 0, start: origin, end: p1, condition: _unknownCondition())),
        SafetyVerdict.unknown,
      );
    });

    test('measured hazard → hazardous', () {
      expect(
        e.verdictFor(_seg(
            index: 0, start: origin, end: p1, condition: _measuredHazard())),
        SafetyVerdict.hazardous,
      );
    });

    test('fleet zone + unknown weather → hazardous', () {
      expect(
        e.verdictFor(_seg(
          index: 0,
          start: origin,
          end: p1,
          condition: _unknownCondition(),
          zones: [_zone(const LatLng(35.05, 136.0))],
        )),
        SafetyVerdict.hazardous,
      );
    });
  });

  group('RerouteDecision', () {
    test('noHazardFound is assessed and carries the forecast confidence', () {
      const d = RerouteDecision.noHazardFound(confidence: 0.7);
      expect(d.isAssessed, isTrue);
      expect(d.confidence, 0.7);
      expect(d.shouldReroute, isFalse);
    });

    test('cannotAssess has null confidence and is not assessed', () {
      const d = RerouteDecision.cannotAssess(reason: 'no data');
      expect(d.isAssessed, isFalse);
      expect(d.confidence, isNull);
      expect(d.shouldReroute, isFalse);
      expect(d.detourWaypoints, isEmpty);
    });

    test('toString marks an unassessed decision rather than printing a number',
        () {
      const d = RerouteDecision.cannotAssess(reason: 'no data');
      expect(d.toString(), contains('unassessed'));
    });
  });

  // ==========================================================================
  // A SHORT forecast must not read as a CLEAR one.
  //
  // routing_engine 0.6.0 made RouteManeuver.position nullable, and
  // RouteSegmenter.byManeuver SKIPS a maneuver it cannot locate. So a route
  // most of which was never forecast produces a short segment list — and if
  // the few located segments are measured-clear, this evaluator used to return
  // noHazardFound ("No hazard found on the assessed route", isAssessed = true,
  // confidence 0.90). RouteForecast.hazard computed `unknown` correctly one
  // layer up; the evaluator never consulted it.
  // ==========================================================================
  group('incomplete route COVERAGE is not the same as no hazard', () {
    const p0 = LatLng(35.0, 136.0);
    const p1 = LatLng(35.1, 136.1);

    RouteForecast partiallyLocatedRoute() {
      // Three maneuvers; two of them could not be located at all.
      final route = _route([p0, p1], [
        _m(0, p0),
        RouteManeuver(
          index: 1,
          instruction: 'Step 1',
          type: 'straight',
          lengthKm: 5,
          timeSeconds: 300,
          position: null,
        ),
        RouteManeuver(
          index: 2,
          instruction: 'Step 2',
          type: 'straight',
          lengthKm: 5,
          timeSeconds: 300,
          position: null,
        ),
      ]);

      return RouteForecast(
        route: route,
        // Only the located maneuver produced a segment — and it is clear.
        segments: [
          _seg(index: 0, start: p0, end: p1, condition: _measuredClear()),
        ],
        generatedAt: _t,
      );
    }

    test('a route with unlocatable maneuvers is NOT "no hazard found"', () {
      final d = RerouteEvaluator().evaluate(
        partiallyLocatedRoute(),
        currentPosition: p0,
      );

      expect(d.shouldReroute, isFalse);
      // The load-bearing assertion: the decision must ADMIT it is not a claim.
      expect(d.isAssessed, isFalse);
      expect(d.confidence, isNull);
      expect(d.reason, isNot(contains('No hazard found')));
      expect(d.reason, contains('could not be assessed'));
      expect(d.reason, contains('2 of 3 maneuvers'));
    });

    test('the forecast itself already knew — the evaluator now agrees', () {
      final f = partiallyLocatedRoute();

      expect(f.coversWholeRoute, isFalse);
      expect(f.unlocatableManeuverCount, 2);
      expect(f.hazard, SafetyVerdict.unknown);

      final d = RerouteEvaluator().evaluate(f, currentPosition: p0);
      expect(d.isAssessed, isFalse);
    });

    test(
      'a hazard elsewhere still fires, and still discloses the unseen stretch',
      () {
        final route = _route([p0, p1], [
          _m(0, p0),
          RouteManeuver(
            index: 1,
            instruction: 'Step 1',
            type: 'straight',
            lengthKm: 5,
            timeSeconds: 300,
            position: null,
          ),
        ]);
        final f = RouteForecast(
          route: route,
          segments: [
            _seg(index: 0, start: p0, end: p1, condition: _measuredHazard()),
          ],
          generatedAt: _t,
        );

        final d = RerouteEvaluator().evaluate(f, currentPosition: p0);

        // Positive evidence still wins (caution-add-only) …
        expect(d.shouldReroute, isTrue);
        // … and the stretch nobody looked at does not vanish.
        expect(d.reason, contains('could not be located'));
      },
    );
  });
}
