/// How much the monitor trusts the latest fix.
///
/// This enum is the stable contract: switch on it. (`GateId` may grow as later
/// layers add gates, so do NOT write exhaustive switches over `GateId`.)
enum IntegrityStatus {
  /// No fault was detected by the monitor's tests.
  ///
  /// HONESTY BOUND: this is NOT a claim that the position is correct. It means
  /// only that none of the plausibility tests fired for this fix. A slowly
  /// drifting spoof or a correlated error can be consistent with motion and
  /// still be wrong (see `KNOWN_LIMITATIONS.md`). Treat `trusted` as
  /// "no fault detected by these tests", never as "position verified".
  trusted,

  /// One or more soft plausibility tests fired but have not yet been sustained,
  /// or the position is jittering while the vehicle appears stationary. Use the
  /// fix with caution — it is not yet a confirmed fault, but it is no longer
  /// clean. On `suspect` the [IntegrityVerdict.recommendedSource] deliberately
  /// stays [SourceHint.gps]: the floor does not advise a handoff on a single
  /// soft fault. Consumers MUST act on [IntegrityVerdict.status], not on
  /// `recommendedSource` alone.
  suspect,

  /// A confirmed integrity fault: a teleport, an impossible speed, or a
  /// sustained impossible acceleration. The fix should not be trusted as the
  /// vehicle's position. (Stationary jitter is suspect-only and never reaches
  /// `failed` on its own.)
  failed,
}

/// What position source the monitor recommends the app trust right now.
enum SourceHint {
  /// Keep using the GPS / fused fix (no handoff).
  gps,

  /// Stop trusting GPS and switch to dead reckoning.
  ///
  /// Only recommended when the caller has told [PositionIntegrityMonitor]
  /// (via `deadReckoningAge`) that the dead-reckoning estimate is RECENT. The
  /// monitor cannot judge whether your DR is any good — only that you said it
  /// is fresh — so condition your own use of this on DR quality.
  deadReckoning,

  /// Stop trusting GPS, and do NOT hand off — hold the last known-good state.
  ///
  /// Used on a fault when no fresh dead-reckoning source is known to the
  /// monitor (the caller passed no `deadReckoningAge`, or it was stale). This
  /// is the conservative recommendation: better to hold than to switch to a
  /// source that may itself have degraded.
  hold,
}

/// The four calibration-free plausibility gates of the floor.
///
/// Each gate is a physical-plausibility check that needs no tuning to the
/// sensor: it asks whether the motion implied between two fixes is possible at
/// all for a road vehicle. They are intentionally crude and robust — the floor
/// that keeps protecting even when a finer statistical layer is mistuned.
///
/// This set may GROW in later releases (e.g. a statistical consistency gate).
/// Do not write exhaustive switches over [GateId]; switch on [IntegrityStatus].
enum GateId {
  /// A position jump too large to be real over a time delta too small to
  /// compute a reliable speed from (bursty / high-rate multipath).
  teleport,

  /// The implied speed between two fixes exceeds what a road vehicle can do.
  impossibleSpeed,

  /// The implied change in speed between two fixes exceeds what a road vehicle
  /// can do (impossible acceleration / deceleration).
  impossibleAccel,

  /// The position is wandering while the vehicle appears stationary — the
  /// classic parked-with-a-drifting-fix signature. Suspect-only.
  stationaryJitter,
}

/// The monitor's verdict on a single fix: a consumable trust decision plus a
/// source-handoff recommendation, a human-readable reason, and a per-gate
/// audit map.
///
/// New fields added in later releases will be optional / defaulted so this
/// `const` constructor stays non-breaking.
class IntegrityVerdict {
  const IntegrityVerdict({
    required this.status,
    required this.recommendedSource,
    required this.reason,
    required this.gateResults,
  });

  /// Whether the latest fix is trusted, suspect, or failed.
  final IntegrityStatus status;

  /// The source the app should trust right now.
  final SourceHint recommendedSource;

  /// A short, human-readable explanation, e.g.
  /// `'teleport: 35 m in 0.05 s'` or `'impossible speed: 205 m/s (max 50)'`.
  /// On a clean fix this reads `'no fault detected'`.
  final String reason;

  /// Per-gate result for this fix: `true` means the gate PASSED (no violation),
  /// `false` means it was violated. Gates that could not be evaluated for this
  /// fix (e.g. rate gates on the first fix, or when the time delta was too
  /// small) are simply ABSENT from the map. Prefer the [violatedGates] /
  /// [hasViolation] getters at call sites — they read unambiguously and avoid
  /// the `true == passed` polarity and the absent-key null trap.
  final Map<GateId, bool> gateResults;

  /// The gates that were VIOLATED for this fix (empty on a clean fix).
  Set<GateId> get violatedGates => gateResults.entries
      .where((e) => !e.value)
      .map((e) => e.key)
      .toSet();

  /// Whether any gate was violated this fix.
  bool get hasViolation => gateResults.values.any((passed) => !passed);

  @override
  String toString() =>
      'IntegrityVerdict($status, $recommendedSource, "$reason")';
}
