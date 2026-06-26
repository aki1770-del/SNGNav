import 'dart:math' as math;

import 'drive_advice.dart';
import 'drive_situation.dart';
import 'mirror_enums.dart';

// =============================================================================
// Named, documented, tunable thresholds.
//
// CAUTION-ADD-ONLY invariant: a change to any constant here may only ever RAISE
// caution (lower a clear band, lower a fast threshold, lower a deceleration),
// never silently lower it. The tests assert monotonicity so a relaxing tweak is
// caught.
// =============================================================================

/// A confidence radius beyond this (~150 m) means the dot is a neighbourhood,
/// not a point — it bumps a degraded position to the worst tier.
const double kRadiusNeighbourhoodM = 150.0;

/// Seconds without a trusted fix beyond which a degraded position is "long
/// blind" and bumps to the worst tier.
const double kStaleFixSeconds = 60.0;

/// A visibility reading older than this (~5 min) is too stale to trust and is
/// treated as unknown. Snow squalls can collapse visibility from kilometres to
/// metres inside this window, so this is a deliberately conservative ceiling on
/// trust, not a promise the reading is still accurate — and it is a public
/// `const` an integrator may shorten for fast-moving-squall regions.
const double kVisStaleSeconds = 300.0;

/// At/above this (~1 km) visibility is clear (concern 0).
const double kVisClearM = 1000.0;

/// At/above this (~500 m) visibility is reduced (concern 1).
const double kVisReducedM = 500.0;

/// At/above this (~200 m) visibility is low (concern 2); below it is the
/// whiteout band (concern 3).
const double kVisLowM = 200.0;

/// Above this ground speed (~13.4 m/s ≈ 48 km/h) the driver is covering
/// uncertain ground fast — an escalator when the core is already degraded.
const double kFastForConditionsMps = 13.4;

/// The deceleration (m/s²) the sight-stopping-speed hint assumes for the road
/// surface. Calibrated to the WORST-CREDIBLE winter surface this package
/// targets — glare / black ice (ブラックアイスバーン), μ ≈ 0.1, ~1.0 m/s² — NOT
/// packed snow (~2.0). The hint must not assume a grip the worst morning cannot
/// give: on the surfaces this package exists for, a higher figure would name a
/// speed at which she could NOT actually stop. Caution-add-only: this may only
/// ever be lowered. This is the one road-surface assumption the package makes;
/// it is disclosed here and in the README honesty bounds, and it is a public
/// `const` an integrator may lower further (never raise).
const double kWinterDecelMps2 = 1.0;

/// Reaction-time margin (s) folded into the sight-stopping-speed hint. Set to a
/// winter, see-the-hazard-then-react figure (~2.5 s, well above the ~1.5 s used
/// for alert dry-road braking) because spotting a stopped car in falling snow
/// and beginning to brake takes longer. Caution-add-only.
const double kReactionTimeSeconds = 2.5;

/// Hard ceiling (m/s) on the sight-stopping-speed hint. The hint is never
/// surfaced above the "covering uncertain ground fast" threshold
/// ([kFastForConditionsMps], ~48 km/h): no matter how far she can see, the
/// model itself treats anything faster as fast-for-conditions, so the hint must
/// not suggest it. This bounds the sight-geometry result, which on its own
/// ignores grip and could otherwise name an unsafe snow-road speed.
const double kSightHintCeilingMps = kFastForConditionsMps;

/// Fuse position-trust × visibility (with advisory severity + speed as
/// escalators) into one honest, immutable in-drive caution record.
///
/// Total, deterministic, synchronous, pure: same input → same output; defined
/// for every enum, for `null`, [double.infinity], and [double.nan] — clamped,
/// never thrown. The one intentional non-linearity is the compounding rule
/// (§3.5): position-uncertain AND low-visibility TOGETHER yields the strongest
/// caution. That non-linearity is the whole reason this in-drive package exists
/// distinct from the pre-trip one.
DriveAdvice adviseInDrive(DriveSituation s) {
  // --- position concern: pc ∈ {0,1,2,3} ---
  final int pc = _positionConcern(s);

  // --- visibility known-ness, then concern: vc ∈ {0,1,2,3} ---
  final _VisibilityResolution vis = _resolveVisibility(s);
  final int vc = vis.concern;

  // --- advisory concern: ac ∈ {0,1,2,3} ---
  final int ac = _advisoryConcern(s.advisorySeverity);

  // --- fusion (position×visibility is PRIMARY; advisory + speed are escalators) ---
  final int corePair = math.max(pc, vc);
  final bool compounding = pc >= 2 && vc >= 2;

  // Speed escalator — only meaningful when the core is already degraded.
  final double? speed = s.speedMetersPerSecond;
  final bool speedKnown = speed != null && !speed.isNaN;
  final bool fast = speedKnown && speed > kFastForConditionsMps;

  int score = corePair;
  if (compounding) score = math.min(3, score + 1); // worse than either alone
  if (ac >= 2) score = math.min(3, score + 1); // severe/extreme escalates by one
  if (fast && corePair >= 1) {
    score = math.min(3, score + 1); // covering uncertain ground fast
  }
  // An extreme advisory, a lost position, or a whiteout each stands alone at
  // the ceiling — an escalator may never be the SOLE reason to reach it, but
  // these single axes at their worst may.
  score = math.max(score, ac);
  score = math.max(math.max(score, pc), vc);

  final DriveAction action = switch (score) {
    0 => DriveAction.continueDriving,
    1 || 2 => DriveAction.heightenedCaution,
    _ => DriveAction.considerStopping,
  };

  // --- honest axis flags ---
  final bool positionUncertain =
      s.positionTrust != PositionTrust.trusted || !s.hasPosition;
  final bool visibilityKnown = vis.known;
  final bool visibilityLow = visibilityKnown && vc >= 2;

  // --- reasons ---
  // INVARIANT: every axis that contributes to a raised action must contribute a
  // reason, so a returned action above continueDriving can never carry an empty
  // reasons set (asserted below + tested). Each band emits exactly ONE reason:
  // a known visibility reading is reduced (vc 1) XOR low/whiteout (vc ≥ 2); an
  // advisory above minor is moderate (ac 1) XOR severe/extreme (ac ≥ 2).
  final reasons = <CautionReason>{};
  if (pc >= 1) reasons.add(CautionReason.positionUncertain);
  if (visibilityKnown) {
    if (vc >= 2) {
      reasons.add(CautionReason.lowVisibility);
    } else if (vc == 1) {
      reasons.add(CautionReason.reducedVisibility);
    }
  } else {
    if (vis.stale) {
      reasons.add(CautionReason.staleVisibility);
    } else {
      reasons.add(CautionReason.unknownVisibility);
    }
  }
  if (ac >= 2) {
    reasons.add(CautionReason.severeAdvisory);
  } else if (ac == 1) {
    reasons.add(CautionReason.moderateAdvisory);
  }
  if (fast && corePair >= 1) {
    reasons.add(CautionReason.highSpeedInDegradedConditions);
  }

  // The honesty contract in code: a raised action ALWAYS has a statable WHY.
  // (Debug/test-mode assertion; the band logic above makes it true by
  // construction — every axis that can raise the score also emits a reason.)
  assert(
    action == DriveAction.continueDriving || reasons.isNotEmpty,
    'invariant violated: action $action raised with no reason (score $score, '
    'pc $pc, vc $vc, ac $ac)',
  );

  // --- first-class unknowns ---
  final unknowns = <Unknown>[];
  if (!s.hasPosition) {
    unknowns.add(Unknown.noPositionAtAll);
  } else if (s.positionTrust != PositionTrust.trusted) {
    unknowns.add(Unknown.positionCouldBeAnywhereInRadius);
  }
  if (s.positionTrust != PositionTrust.trusted && _fixIsStale(s)) {
    unknowns.add(Unknown.noTrustedGpsForAWhile);
  }
  if (!visibilityKnown) {
    if (vis.stale) {
      unknowns.add(Unknown.visibilityReadingIsStale);
    } else {
      unknowns.add(Unknown.noVisibilityReading);
    }
  }
  if (!speedKnown) unknowns.add(Unknown.speedUnknown);

  // --- optional sight-stopping-speed hint ---
  // Emitted ONLY when visibility is grounded AND in the low/whiteout band —
  // i.e. when "stop within what you can see" is the LIVE decision. In the clear
  // and reduced bands the sight-limited speed is far above any sane winter road
  // speed (it would read as an "all-clear-ish" 90–180 km/h number a driver
  // could wrongly ease toward), so we surface no hint there rather than a
  // misleading one. `null` whenever visibility is unknown or adequate.
  final double? hint =
      visibilityLow ? _sightStoppingSpeed(s.visibilityMeters!) : null;

  return DriveAdvice(
    action: action,
    compounding: compounding,
    positionUncertain: positionUncertain,
    visibilityKnown: visibilityKnown,
    visibilityLow: visibilityLow,
    reasons: reasons,
    unknowns: unknowns,
    sightStoppingSpeedHintMps: hint,
  );
}

int _positionConcern(DriveSituation s) {
  // No dot at all dominates everything.
  if (!s.hasPosition) return 3;
  switch (s.positionTrust) {
    case PositionTrust.trusted:
      return 0;
    case PositionTrust.suspect:
      // Suspect is untrusted too, so its radius is grows-only and its fix can
      // go stale. A suspect dot that has drifted to neighbourhood scale (or has
      // had no trusted fix for a long blind period) is no milder than a fresh
      // degraded dot — bump it one tier (1 → 2). Caution-add-only; a small,
      // fresh suspect fix stays at 1.
      final double rs = s.confidenceRadiusMeters;
      final bool suspectRadiusBad =
          rs.isNaN || rs < 0 || rs > kRadiusNeighbourhoodM;
      if (suspectRadiusBad || _fixIsStale(s)) return 2;
      return 1;
    case PositionTrust.degraded:
      // Worst-for-tier on a NaN/negative radius; a neighbourhood-sized radius
      // or a long blind period bumps degraded (2) to the worst tier (3).
      final double r = s.confidenceRadiusMeters;
      final bool radiusBad = r.isNaN || r < 0 || r > kRadiusNeighbourhoodM;
      if (radiusBad || _fixIsStale(s)) return 3;
      return 2;
    case PositionTrust.lost:
      return 3;
  }
}

/// `true` when there has been no trusted fix for longer than [kStaleFixSeconds]
/// — [double.infinity] and [double.nan] both count as stale (conservative).
bool _fixIsStale(DriveSituation s) {
  final double t = s.secondsSinceTrustedFix;
  if (t.isNaN) return true;
  return t > kStaleFixSeconds;
}

class _VisibilityResolution {
  const _VisibilityResolution({
    required this.known,
    required this.stale,
    required this.concern,
  });

  /// Whether a usable, fresh reading is in hand.
  final bool known;

  /// Whether a reading exists but is beyond the freshness window (a distinct
  /// kind of unknown from "no reading at all").
  final bool stale;

  /// 0..3 concern level.
  final int concern;
}

_VisibilityResolution _resolveVisibility(DriveSituation s) {
  final double? m = s.visibilityMeters;
  final double? age = s.visibilityAgeSeconds;

  // A reading is "stale" (cannot be trusted as fresh) when a reading EXISTS and
  // its age is null, NaN, or beyond the window. A null age means "unknown age"
  // (drive_situation.dart) — we CANNOT confirm freshness, exactly like a NaN
  // age — so a null-age reading is NOT trusted as known/fresh. Trusting it would
  // be the one false-confidence path the held level-1 floor exists to refuse: a
  // reading of unknown currency must never clear her or ground a sight hint.
  final bool readingExists = m != null && !m.isNaN;
  final bool stale = readingExists &&
      (age == null || age.isNaN || age > kVisStaleSeconds);

  final bool known = readingExists && !stale;
  if (!known) {
    // Held, non-zero floor: cannot clear her (not 0), must not over-warn as a
    // whiteout (not 3).
    return _VisibilityResolution(known: false, stale: stale, concern: 1);
  }

  final double v = m;
  final int concern;
  if (v >= kVisClearM) {
    concern = 0;
  } else if (v >= kVisReducedM) {
    concern = 1;
  } else if (v >= kVisLowM) {
    concern = 2;
  } else {
    // Below the low band (incl. negative) is the whiteout band.
    concern = 3;
  }
  return _VisibilityResolution(known: true, stale: false, concern: concern);
}

int _advisoryConcern(AdvisoryLevel? a) {
  switch (a) {
    case null:
    case AdvisoryLevel.minor:
      return 0;
    case AdvisoryLevel.moderate:
      return 1;
    case AdvisoryLevel.severe:
      return 2;
    case AdvisoryLevel.extreme:
      return 3;
  }
}

/// A conservative speed (m/s) at which stopping distance fits within the
/// visible distance ahead. Three deliberate safety margins stack, all in the
/// fail-toward-slower direction:
///
///  1. **Worst-credible grip.** Deceleration is [kWinterDecelMps2] (~glare ice),
///     not packed snow — the package must not assume grip the worst morning
///     cannot give.
///  2. **Stop within HALF of sight.** A stopped obstacle (a stuck car) may sit
///     anywhere in the visible distance, so the speed is solved for stopping
///     within `visibleMeters / 2`, not the full distance.
///  3. **Hard winter ceiling.** The result is capped at [kSightHintCeilingMps]
///     so pure sight-geometry can never name a snow-road speed the model itself
///     treats as fast-for-conditions.
///
/// Solves `d = v·t_react + v²/(2a)` for the largest `v`, rounded DOWN, clamped
/// to ≥ 0. A hint to ease toward, never a command.
double _sightStoppingSpeed(double visibleMeters) {
  final double sight = visibleMeters > 0 ? visibleMeters : 0.0;
  // Plan to stop within HALF of what she can see (margin 2 above).
  final double d = sight / 2.0;
  // (1/(2a))·v² + t·v − d = 0  →  v = a·(−t + sqrt(t² + 2d/a))
  final double a = kWinterDecelMps2;
  final double t = kReactionTimeSeconds;
  final double v = a * (-t + math.sqrt(t * t + (2 * d) / a));
  final double safe = v.isFinite && v > 0 ? v : 0.0;
  // Hard winter ceiling (margin 3 above).
  final double capped = math.min(safe, kSightHintCeilingMps);
  return capped.floorToDouble();
}
