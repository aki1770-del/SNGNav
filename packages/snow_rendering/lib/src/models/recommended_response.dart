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
  ///
  /// This is a POSITIVE claim that the road was assessed and found benign. It
  /// requires knowing the conditions. When they are not known, the answer is
  /// [conditionsUnknown] — never this.
  proceed,

  /// The conditions could not be assessed: the data needed to classify the
  /// road was absent (no feed, an empty feed, a coverage gap, or a source that
  /// reported no observation).
  ///
  /// This tier exists because up to 0.2.7 there was nowhere to put "I do not
  /// know", so an unmeasured road fell through to [proceed] and the driver was
  /// told "Conditions normal" about a road nobody had looked at. That is the
  /// defect the Measured-or-Absent contract removes.
  ///
  /// It is deliberately NOT [reduceSpeed]: raising a hazard on every offline
  /// moment would cry wolf until the driver stopped believing the alert, and
  /// she would then ignore it on the night it was real. Unknown is reported AS
  /// unknown — a state she can act on ("drive to what you can see"), which is
  /// the D3 compound-failure answer when the feed is gone.
  conditionsUnknown,

  /// Hazardous but driveable with caution — reduce speed, increase following
  /// distance. The existing speed-reduction advisories map here.
  reduceSpeed,

  /// Whiteout-class conditions: visibility and/or grip are failing together.
  /// The recommended response is to turn back / abandon the trip while it is
  /// still safe to do so, rather than to push on.
  considerTurningBack,
}
