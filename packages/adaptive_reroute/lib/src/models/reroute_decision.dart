import 'package:equatable/equatable.dart';
import 'package:route_condition_forecast/route_condition_forecast.dart';
import 'detour_waypoint.dart';

/// The result of evaluating whether to reroute based on a [RouteForecast].
///
/// Produced by [RerouteEvaluator]. The calling code acts on [shouldReroute]
/// and, if true, uses [detourWaypoints] to build an alternative route with
/// the routing engine of choice.
///
/// This package decides; it never routes. The caller routes.
///
/// ## Three outcomes, not two
///
/// A decision reports one of three facts, and they are **not** interchangeable:
///
/// * **reroute** — a hazard was found, inside the look-ahead window, with
///   enough forecast confidence to act on. [shouldReroute] is `true`.
/// * **no hazard found** — the route *was* assessed and nothing fired. See
///   [RerouteDecision.noHazardFound]. [confidence] is inherited from the
///   forecast.
/// * **cannot assess** — the conditions along the route were not known, so no
///   claim about the route can be made at all. See
///   [RerouteDecision.cannotAssess]. [confidence] is `null`.
///
/// The third outcome did not exist before 0.2.0, and its absence was a safety
/// defect: a route whose conditions were entirely unknown returned
/// `RerouteDecision.clear()` — reason *"Route is clear"*, `confidence = 1.0`.
/// Absence of data was reported as certainty of safety.
///
/// **Check [isAssessed] before treating `shouldReroute == false` as good news.**
class RerouteDecision extends Equatable {
  /// Whether the evaluator recommends rerouting.
  ///
  /// **`false` does not mean "the route is safe."** It means "no reroute is
  /// recommended" — which is also what this package returns when it could not
  /// assess the route at all. Read [isAssessed] to tell those two apart.
  final bool shouldReroute;

  /// Human-readable explanation for logging or driver UI.
  final String reason;

  /// The hazardous segment that triggered the recommendation, if any.
  final SegmentConditionForecast? triggerSegment;

  /// Detour waypoints to feed to a routing engine if [shouldReroute] is true.
  /// Empty when [shouldReroute] is false.
  final List<DetourWaypoint> detourWaypoints;

  /// Confidence of this decision in `[0, 1]` — or `null` when the route could
  /// not be assessed.
  ///
  /// `null` means **not assessable**: the conditions this decision would have
  /// rested on were absent. It never means "zero confidence", and it never
  /// means "no hazard".
  ///
  /// When non-null it is inherited from the forecast — the confidence of the
  /// [triggerSegment] for a hazard decision, or the weakest segment confidence
  /// along the route for a [RerouteDecision.noHazardFound]. It is never a
  /// synthetic `1.0`: this package observes no conditions of its own, so it can
  /// be no more certain than the forecast it was handed.
  final double? confidence;

  const RerouteDecision({
    required this.shouldReroute,
    required this.reason,
    required this.confidence,
    this.triggerSegment,
    this.detourWaypoints = const [],
  });

  /// The route was assessed, and no hazard fired.
  ///
  /// [confidence] is inherited from the forecast — normally the weakest segment
  /// confidence along the route. It is **not** `1.0`: a negative claim derived
  /// from a forecast that degrades with horizon cannot be more certain than
  /// that forecast.
  ///
  /// Replaces the removed `RerouteDecision.clear()`, which asserted
  /// `confidence = 1.0` — a certainty this package never had, and which it also
  /// returned when the conditions were simply unknown.
  const RerouteDecision.noHazardFound({required double confidence})
      : this(
          shouldReroute: false,
          reason: 'No hazard found on the assessed route',
          confidence: confidence,
        );

  /// The route could **not** be assessed: the conditions it would have been
  /// judged on were absent.
  ///
  /// [shouldReroute] is `false` because this package has no grounds to
  /// recommend a detour — **not** because the route is clear. [confidence] is
  /// `null`, and [isAssessed] is `false`.
  ///
  /// Integrators must surface this to the driver as *unknown* — never as an
  /// all-clear. "We could not look" and "we looked and found nothing" are
  /// different facts.
  const RerouteDecision.cannotAssess({required String reason})
      : this(
          shouldReroute: false,
          reason: reason,
          confidence: null,
        );

  /// Whether this decision rests on conditions that were actually known.
  ///
  /// `false` means the route conditions were absent and **no** claim — clear or
  /// hazardous — can be made. Gate any "route is clear" UI on this.
  bool get isAssessed => confidence != null;

  @override
  List<Object?> get props =>
      [shouldReroute, reason, triggerSegment, detourWaypoints, confidence];

  @override
  String toString() {
    final c = confidence;
    final conf = c == null ? 'unassessed' : 'conf=${c.toStringAsFixed(2)}';
    return 'RerouteDecision(reroute=$shouldReroute, $conf, reason="$reason")';
  }
}
