/// The class of driver response a driving-condition assessment recommends.
///
/// This is the *typed* response tier, deliberately distinct from the free-text
/// [DrivingConditionAssessment.advisoryMessage]. Keeping it typed is the whole
/// point: it makes **trip-abandonment a first-class response**, not a sentence
/// buried inside an advisory string that a consumer has to parse.
///
/// Grounded in a recorded driver voice (see `DRIVER_VOICES.md`, the
/// Sapporo→Shinshinotsu whiteout, 2024-12): in whiteout-class conditions the
/// life-saving response is not "drive more carefully" — it is to turn back
/// while you still can. The driver in that account did not reduce speed; she
/// abandoned the trip, having seen a car ahead go off the shoulder. A product
/// that only ever says "slow down" cannot represent that decision.
enum RecommendedResponse {
  /// Conditions are within normal driving tolerance.
  proceed,

  /// Hazardous but driveable with caution — reduce speed, increase following
  /// distance. The existing speed-reduction advisories map here.
  reduceSpeed,

  /// Whiteout-class conditions: visibility and/or grip are failing together.
  /// The recommended response is to turn back / abandon the trip while it is
  /// still safe to do so, rather than to push on.
  considerTurningBack,
}
