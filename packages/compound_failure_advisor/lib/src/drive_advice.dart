/// The entire actionable vocabulary — three rungs, a strict monotonic ladder.
///
/// Deliberately three, not four or five: a driver can hold this in working
/// memory at the wheel while it is snowing, and three is the most the inputs
/// (a confidence radius and one visibility reading) can honestly support.
///
/// There is structurally NO "do not drive" / "abort" / "turn back" rung — that
/// rung is ABSENT from this enum, so the package is incapable of telling her to
/// abandon the drive to her mother. The worst case demotes the MAP, never the
/// JOURNEY.
enum DriveAction {
  /// "Conditions are within normal bounds for what's known right now." The
  /// ABSENCE of a raised concern — NOT an assertion of safety. Worded for the
  /// surface as *continue* (she was already driving), never "safe to continue".
  continueDriving,

  /// "One or more conditions have degraded — ease your speed, leave more room,
  /// watch for the next safe option." The default working state of a winter
  /// drive; asks for attention/margin, not for a stop.
  heightenedCaution,

  /// The ceiling. "If you can do so safely, a safe place to pause is an option
  /// whenever you want one." An invitation she owns — never "stop now", never a
  /// command. Reached chiefly by the compounding case or a single axis at its
  /// worst (lost / whiteout / extreme advisory).
  considerStopping,
}

/// Exactly which inputs raised the action — surfaced so the integrator can say
/// WHY in the driver's own terms, with no re-derivation.
enum CautionReason {
  /// Position is not trusted (suspect / degraded / lost / no dot).
  positionUncertain,

  /// A known visibility reading is in the LOW or WHITEOUT band (concern ≥ 2,
  /// below ~200 m–500 m). The harder visibility band; [reducedVisibility] covers
  /// the milder one — exactly one of the two fires per known reading, never both.
  lowVisibility,

  /// A known visibility reading is in the REDUCED band (concern 1, ~500–1000 m):
  /// degraded but not yet low. Milder counterpart to [lowVisibility]; it is the
  /// statable WHY when a single mild visibility drop is the only thing that
  /// raised the action.
  reducedVisibility,

  /// No visibility reading near her — distinct from [lowVisibility]; "we can't
  /// see a measurement" is honestly different from "you can see fine".
  unknownVisibility,

  /// A visibility reading exists but is too old to trust → treated as unknown.
  staleVisibility,

  /// A severe or extreme area advisory is in force. The harder advisory band;
  /// [moderateAdvisory] covers the milder one — exactly one of the two fires per
  /// advisory level above `minor`, never both.
  severeAdvisory,

  /// A moderate area advisory is in force (concern 1): above `minor`/none but
  /// below severe. Milder counterpart to [severeAdvisory]; the statable WHY when
  /// a moderate advisory alone raised the action.
  moderateAdvisory,

  /// Covering uncertain ground fast — speed is high while the core is degraded.
  highSpeedInDegradedConditions,
}

/// First-class unknowns — the heart of the honesty contract, NOT a footnote.
///
/// An enum, not prose, so the integrator localizes for HER Japanese mother. The
/// surface shows these as plain facts, each alongside the input field it refers
/// to (the integrator still holds the [DriveSituation]).
enum Unknown {
  /// The dot could be anywhere in the confidence radius (carry
  /// `confidenceRadiusMeters`).
  positionCouldBeAnywhereInRadius,

  /// No trusted GPS fix for a while (carry `secondsSinceTrustedFix`).
  noTrustedGpsForAWhile,

  /// No position at all (`!hasPosition`).
  noPositionAtAll,

  /// No visibility reading in hand (`visibilityMeters == null`).
  noVisibilityReading,

  /// A visibility reading exists but is beyond the freshness window.
  visibilityReadingIsStale,

  /// Ground speed is unknown.
  speedUnknown,
}

/// One immutable, honest caution label on how to hold the wheel right now.
///
/// It carries NO lat/lng, NO "safe" boolean, NO ETA, NO route mutation, and no
/// live reading of the road surface, other vehicles, or her car (it never
/// senses grip). The ONE surface assumption it makes is a single, disclosed,
/// worst-credible-ice deceleration used only for the optional
/// [sightStoppingSpeedHintMps] — chosen low on purpose so the hint cannot
/// over-state the speed at which she could stop. It asserts no safety it cannot
/// back. Advisory-only: it labels the moment; she drives it.
class DriveAdvice {
  /// Creates an immutable advisory. The unmodifiable collection guarantees the
  /// honesty surface cannot be mutated after the fact.
  DriveAdvice({
    required this.action,
    required this.compounding,
    required this.positionUncertain,
    required this.visibilityKnown,
    required this.visibilityLow,
    required Set<CautionReason> reasons,
    required List<Unknown> unknowns,
    required this.sightStoppingSpeedHintMps,
  })  : reasons = Set.unmodifiable(reasons),
        unknowns = List.unmodifiable(unknowns);

  /// The recommended rung. See [DriveAction].
  final DriveAction action;

  /// LOAD-BEARING. `true` iff position is uncertain AND visibility is low at the
  /// same time — the two dangers are STACKING (worse than either alone) and the
  /// action was escalated for THAT reason, not for one axis crossing a
  /// threshold. The reason this package exists.
  final bool compounding;

  /// `positionTrust != trusted` (or `!hasPosition`).
  final bool positionUncertain;

  /// `false` when the visibility reading is `null` OR too stale to trust.
  final bool visibilityKnown;

  /// `true` only when visibility is KNOWN and in the low/whiteout band; `false`
  /// when unknown (we never call unknown "low", nor "clear").
  final bool visibilityLow;

  /// Exactly which inputs raised the action. Unmodifiable.
  final Set<CautionReason> reasons;

  /// Explicit, first-class unknown list — the heart of the honesty contract.
  /// Unmodifiable.
  final List<Unknown> unknowns;

  /// OPTIONAL "a speed at which you could stop within what you can see ahead".
  ///
  /// Surfaced ONLY when visibility is a grounded reading in the LOW or WHITEOUT
  /// band (where "stop within sight" is the live decision); `null` in the clear
  /// and reduced bands, and `null` whenever visibility is unknown or stale — we
  /// will NOT invent a number we cannot ground, nor an "all-clear-ish" speed in
  /// good visibility. It assumes worst-credible glare-ice grip (see
  /// [kWinterDecelMps2]), plans to stop within HALF the visible distance, and is
  /// capped at a winter ceiling ([kSightHintCeilingMps]) — all fail-toward-slower
  /// so it cannot over-state a safe speed. A hint to ease toward, never a
  /// commanded speed.
  final double? sightStoppingSpeedHintMps;

  @override
  String toString() => 'DriveAdvice(action: ${action.name}, '
      'compounding: $compounding, '
      'positionUncertain: $positionUncertain, '
      'visibilityKnown: $visibilityKnown, '
      'visibilityLow: $visibilityLow, '
      'reasons: {${reasons.map((r) => r.name).join(', ')}}, '
      'unknowns: [${unknowns.map((u) => u.name).join(', ')}], '
      'sightStoppingSpeedHintMps: $sightStoppingSpeedHintMps)';
}
