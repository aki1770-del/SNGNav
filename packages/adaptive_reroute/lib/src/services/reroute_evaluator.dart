import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import 'package:route_condition_forecast/route_condition_forecast.dart';
import '../models/adaptive_reroute_config.dart';
import '../models/reroute_decision.dart';
import 'detour_planner.dart';

/// Evaluates a [RouteForecast] and decides whether to reroute.
///
/// ## Evaluation rules (applied in order)
///
/// 0. If the forecast contains **no segments**, nothing was assessed →
///    [RerouteDecision.cannotAssess].
/// 1. If any segment is **hazardous** (see [verdictFor]), the earliest one in
///    travel order becomes the trigger:
///    * ETA beyond [AdaptiveRerouteConfig.hazardWindowSeconds] → flag, do not
///      reroute yet.
///    * Forecast confidence below [AdaptiveRerouteConfig.minConfidenceToAct] →
///      signal too uncertain to act on; wait.
///    * Otherwise → reroute recommended, with detour waypoints.
/// 2. Else, if any segment's conditions are **unknown**, the route cannot be
///    certified clear → [RerouteDecision.cannotAssess].
/// 3. Only when **every** segment is known and none is hazardous →
///    [RerouteDecision.noHazardFound], carrying the weakest segment confidence
///    along the route.
///
/// Rules 0 and 2 are new in 0.2.0. Before them, an unknown route fell through
/// to `RerouteDecision.clear()` — *"Route is clear"*, `confidence = 1.0`.
///
/// ## The asymmetry (inherited from driving_weather's `SafetyVerdict`)
///
/// A hazard fires on POSITIVE evidence from any single known signal, even when
/// every other field is absent. Only the NEGATIVE claim — "no hazard on this
/// route" — requires complete knowledge of every segment.
///
/// This is what makes the package safe without crying wolf: being offline does
/// not produce a hazard alert (which the driver would learn to ignore), it
/// produces *unknown*, which the driver is TOLD about.
///
/// The caller acts on [RerouteDecision.shouldReroute] and routes via its chosen
/// routing engine using [RerouteDecision.detourWaypoints] — but must first read
/// [RerouteDecision.isAssessed], because `shouldReroute == false` alone does not
/// mean the route is clear.
class RerouteEvaluator {
  const RerouteEvaluator({
    this.config = const AdaptiveRerouteConfig(),
    DetourPlanner? detourPlanner,
  }) : _detourPlanner = detourPlanner ?? const DetourPlanner();

  final AdaptiveRerouteConfig config;
  final DetourPlanner _detourPlanner;

  /// The tri-state safety verdict for a single [segment].
  ///
  /// * [SafetyVerdict.hazardous] — a fleet hazard zone intersects the segment
  ///   (positive, human-reported evidence), or the segment's weather condition
  ///   is hazardous.
  /// * [SafetyVerdict.unknown] — no fleet hazard was reported *and* the weather
  ///   condition was not measured well enough to answer. An absent fleet report
  ///   is not evidence of safety: nobody driving that road has reported a
  ///   hazard, which is not the same as the road being clear.
  /// * [SafetyVerdict.notHazardous] — no fleet hazard, and the weather is known
  ///   and not hazardous.
  ///
  /// Exposed so integrators can render per-segment state (hazard / clear /
  /// unknown) on a map without re-deriving the asymmetry — and get it wrong.
  SafetyVerdict verdictFor(SegmentConditionForecast segment) {
    // Positive evidence from the fleet fires regardless of what the weather
    // feed did or did not say.
    if (segment.hazardZones.isNotEmpty) return SafetyVerdict.hazardous;
    return segment.condition.hazard;
  }

  /// Evaluates [forecast] and returns a [RerouteDecision].
  ///
  /// [currentPosition] is used to compute the approach bearing toward hazards
  /// for detour waypoint generation.
  RerouteDecision evaluate(
    RouteForecast forecast, {
    required LatLng currentPosition,
  }) {
    final segments = forecast.segments;

    // Rule 0 — nothing was forecast, so nothing was assessed. An empty segment
    // list is not an empty hazard list.
    if (segments.isEmpty) {
      return const RerouteDecision.cannotAssess(
        reason: 'Route conditions unavailable — no segments were forecast; '
            'the route could not be assessed',
      );
    }

    // How much of the route could we not see at all? Carried into every branch
    // below: a hazard elsewhere on the route must not make an unknown segment
    // disappear from what the driver is told.
    final unknownCount =
        segments.where((s) => verdictFor(s) == SafetyVerdict.unknown).length;

    // How much of the route was never even SEGMENTED? `RouteSegmenter.byManeuver`
    // SKIPS a maneuver that carries no position (routing_engine 0.6.0 made
    // `RouteManeuver.position` nullable rather than silently returning Null
    // Island). So a route most of which could not be located produces a SHORT
    // segment list — and a short forecast reads exactly like a clear one unless
    // somebody looks. `RouteForecast` computes this correctly and this evaluator
    // used to throw it away, deriving its verdict purely from `segments`: a
    // 3-maneuver route with 2 positionless maneuvers, whose single located
    // segment was measured-clear, returned "No hazard found on the assessed
    // route" with confidence 0.90 and isAssessed = true.
    final unlocatable = forecast.unlocatableManeuverCount;

    // Rule 1 — positive hazard evidence wins, in travel order.
    final trigger = segments
        .where((s) => verdictFor(s) == SafetyVerdict.hazardous)
        .firstOrNull;

    if (trigger != null) {
      String note(String reason) => _withUnlocatableNote(
        _withUnknownNote(reason, unknownCount, segments.length),
        unlocatable,
      );

      if (trigger.etaSeconds > config.hazardWindowSeconds) {
        return RerouteDecision(
          shouldReroute: false,
          reason: note(
            'Hazard at ${(trigger.etaSeconds / 60).toStringAsFixed(0)} min '
            '— outside ${(config.hazardWindowSeconds / 60).toStringAsFixed(0)} min window',
          ),
          triggerSegment: trigger,
          confidence: trigger.confidence,
        );
      }

      if (trigger.confidence < config.minConfidenceToAct) {
        return RerouteDecision(
          shouldReroute: false,
          reason: note(
            'Hazard detected but forecast confidence '
            '${trigger.confidence.toStringAsFixed(2)} < '
            'threshold ${config.minConfidenceToAct}',
          ),
          triggerSegment: trigger,
          confidence: trigger.confidence,
        );
      }

      final approachBearing = _bearing(currentPosition, trigger.segment.start);
      final waypoints = _detourPlanner.plan(
        trigger.hazardZones,
        approachBearing: approachBearing,
      );

      return RerouteDecision(
        shouldReroute: true,
        reason: note(_reason(trigger)),
        triggerSegment: trigger,
        detourWaypoints: waypoints,
        confidence: trigger.confidence,
      );
    }

    // Rule 2 — no hazard fired, but were we actually able to look?
    //
    // The word "clear" is deliberately absent from this string. It is the
    // driver-facing reason for a route we could NOT see, and an HMI that
    // truncates it, or matches on keywords, must not be able to render it as an
    // all-clear. (A test pins this: the string is checked for the absence of
    // "clear". It failed once, on "cannot be certified clear" — a phrase that
    // is technically a denial and practically a hazard.)
    if (unknownCount > 0) {
      return RerouteDecision.cannotAssess(
        reason: _withUnlocatableNote(
          'Route conditions unknown for '
              '${_segmentCount(unknownCount, segments.length)}'
              ' — the route could not be assessed',
          unlocatable,
        ),
      );
    }

    // Rule 2b — the segments we DID forecast were all known and all benign, but
    // the forecast did not cover the whole route: some maneuvers carried no
    // position and were never segmented at all. "No hazard found on the
    // assessed route" would be true and USELESS — the driver hears "clear", and
    // the stretch nobody looked at vanishes. Absence of coverage is not
    // absence of hazard.
    if (!forecast.coversWholeRoute) {
      return RerouteDecision.cannotAssess(
        reason: 'Route conditions unknown for $unlocatable of '
            '${forecast.route.maneuvers.length} maneuvers (no position) '
            '— the route could not be assessed',
      );
    }

    // Rule 3 — every segment known, none hazardous, whole route covered. The
    // only honest place from which to say "nothing found". Confidence is the
    // weakest link along the route, never a manufactured 1.0.
    return RerouteDecision.noHazardFound(
      confidence: segments
          .map((s) => s.confidence)
          .reduce((a, b) => a < b ? a : b),
    );
  }

  /// "1 of 3 segments" / "1 of 1 segment".
  static String _segmentCount(int n, int of) =>
      '$n of $of segment${of == 1 ? '' : 's'}';

  /// Appends an honest note when part of the route could not be seen.
  ///
  /// A hazard found on one segment must not erase the fact that another segment
  /// was never observed. Without this, "hazard beyond the window → no reroute"
  /// would be rendered by an integrator as "nothing to do", and the unknown
  /// stretch of road would vanish from what the driver is told — the same
  /// absence-becomes-silence defect this release exists to end, one branch over.
  static String _withUnknownNote(String reason, int unknownCount, int total) {
    if (unknownCount == 0) return reason;
    return '$reason; conditions unknown for '
        '${_segmentCount(unknownCount, total)}';
  }

  /// Appends the stretch of route that was never forecast at all.
  ///
  /// Distinct from [_withUnknownNote]: that one reports segments we forecast
  /// and could not resolve. This one reports maneuvers we could not even
  /// LOCATE, which therefore produced no segment and are invisible in
  /// `segments.length`. Silence about them is how a short forecast passes for a
  /// complete one.
  static String _withUnlocatableNote(String reason, int unlocatable) {
    if (unlocatable == 0) return reason;
    return '$reason; $unlocatable maneuver'
        '${unlocatable == 1 ? '' : 's'} could not be located and were not '
        'forecast';
  }

  String _reason(SegmentConditionForecast trigger) {
    final etaMin = (trigger.etaSeconds / 60).toStringAsFixed(0);
    if (trigger.hazardZones.isNotEmpty) {
      final sev = trigger.worstFleetSeverity!.name;
      return 'Fleet hazard ($sev) at segment ${trigger.segment.index} in $etaMin min';
    }
    // `iceRisk` is `bool?`: only an explicit `true` is evidence of ice. A null
    // (not measured) must never read as ice, nor silently as no-ice — it simply
    // is not the reason this segment fired, so fall through to the general case.
    if (trigger.condition.iceRisk == true) {
      return 'Ice risk at segment ${trigger.segment.index} in $etaMin min';
    }
    return 'Hazardous weather at segment ${trigger.segment.index} in $etaMin min';
  }

  /// Bearing from [from] to [to] in degrees (0–360, clockwise from north).
  static double _bearing(LatLng from, LatLng to) {
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final x = math.sin(dLng) * math.cos(lat2);
    final y = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return (math.atan2(x, y) * 180 / math.pi + 360) % 360;
  }
}
