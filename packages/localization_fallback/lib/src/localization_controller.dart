/// The localization fallback controller — the honest GPS→DR→lost handoff.
library;

import 'dead_reckoning_estimate.dart';
import 'estimate_basis.dart';
import 'localization_config.dart';
import 'localization_estimate.dart';
import 'localization_mode.dart';
import 'raw_fix.dart';
import 'trust_signal.dart';

/// Orchestrates the handoff from trusted GPS to dead reckoning to `lost`,
/// emitting exactly one [LocalizationEstimate] per input and NEVER a
/// confidently-wrong fix.
///
/// Feed it fixes with [onFix] and, when no fix arrives but time has passed,
/// advance it with [poll]. It is a plain synchronous state machine — no
/// streams, no timers, no async — so it runs anywhere, including 32-bit ARM.
///
/// ## The honesty contract (enforced here, proven in tests)
///
/// 1. While not `gpsTrusted` AND a position basis exists (a trusted fix has
///    been seen, or an unanchored coarse guess has been established),
///    [LocalizationEstimate.confidenceRadiusMeters] is monotonic
///    non-decreasing. You cannot get more certain without a trusted fix. (The
///    bootstrap "nothing seen yet" state emits an INFINITE radius; the first
///    coarse guess that follows is necessarily finite — both are non-confident
///    `lost`, so this transition never claims false confidence.)
/// 2. `lost` is a first-class, honest state: it still returns the last-known
///    position and a radius, but says plainly that this is a guess.
/// 3. Every estimate carries its [EstimateBasis].
/// 4. A `suspect`/`failed` fix is NEVER blended in as if trusted — its
///    coordinates do not move the dot.
class LocalizationController {
  /// The honesty horizons. See [LocalizationConfig].
  final LocalizationConfig config;

  /// The injected dead-reckoning seam, or `null` if none is wired (then a
  /// degraded estimate freezes at last-known and grows its radius).
  final DeadReckoningSeam? deadReckoningSeam;

  LocalizationController({
    LocalizationConfig? config,
    this.deadReckoningSeam,
  }) : config = config ?? const LocalizationConfig();

  // ---- state ----
  double? _lastTrustedLat;
  double? _lastTrustedLon;
  double _lastTrustedAccuracy = 0;
  DateTime? _lastTrustedTime;

  /// Ground speed (m/s) reported by the last trusted fix, or `null` if unknown.
  /// Used to floor the radius-growth rate while the dot is FROZEN at last-known
  /// (no seam), so the circle still plausibly contains a vehicle that kept
  /// moving after GPS dropped.
  double? _lastTrustedSpeed;

  /// Monotonic floor for the radius while degraded. Reset on a trusted fix.
  double _degradedRadiusFloor = 0;

  LocalizationEstimate? _last;

  /// The most recently emitted estimate, or `null` before any input.
  LocalizationEstimate? get current => _last;

  /// Process a newly arrived raw [fix] with its [trust] verdict (the caller
  /// maps `trust` from e.g. `position_integrity`). Returns the one honest
  /// estimate for this moment.
  LocalizationEstimate onFix(
    RawFix fix, {
    TrustSignal trust = TrustSignal.trusted,
  }) {
    final now = fix.timestamp;

    // Garbage geometry can never be trusted, whatever the caller claims.
    final effectiveTrust =
        fix.hasFiniteGeometry ? trust : TrustSignal.failed;

    if (effectiveTrust == TrustSignal.trusted) {
      // Out-of-order / stale-trusted guard. A "trusted" fix whose timestamp is
      // NOT newer than the last trusted fix is a delayed, duplicated, or
      // replayed fix. We must NOT present it as a current confident position,
      // and we must NOT rewind our clock to it (that would inflate/deflate
      // every later poll's elapsed time). Treat it as a non-current input:
      // degrade from the existing baseline without moving the dot or the clock.
      if (_lastTrustedTime != null && !now.isAfter(_lastTrustedTime!)) {
        return _degraded(_lastTrustedTime!, LocalizationMode.deadReckoning);
      }

      // A fresh, newer trusted fix: reconverge onto it. That is the ONLY way
      // the radius is allowed to shrink.
      _lastTrustedLat = fix.latitude;
      _lastTrustedLon = fix.longitude;
      _lastTrustedAccuracy = fix.accuracyMeters;
      _lastTrustedTime = now;
      _lastTrustedSpeed = fix.speedMps;
      _degradedRadiusFloor = 0;

      // Honesty horizon on the trusted path too. A trusted fix whose OWN
      // reported accuracy already exceeds the trustworthy radius is too
      // imprecise to present as a confident dot — even though it is our best,
      // current, trusted position. We still adopt it as the baseline, but we
      // refuse to claim more precision than the trust horizon allows.
      final beyondHorizon =
          fix.accuracyMeters > config.maxTrustworthyRadiusMeters;
      return _emit(LocalizationEstimate(
        latitude: fix.latitude,
        longitude: fix.longitude,
        confidenceRadiusMeters: fix.accuracyMeters,
        mode: beyondHorizon
            ? LocalizationMode.lost
            : LocalizationMode.gpsTrusted,
        secondsSinceTrustedFix: 0,
        basis: EstimateBasis.trustedGpsFix,
      ));
    }

    // suspect / failed: do NOT blend the fix coordinates. We degrade.
    final mode = effectiveTrust == TrustSignal.suspect
        ? LocalizationMode.gpsSuspect
        : LocalizationMode.deadReckoning;
    // Pass the raw fix only so that, if we have NO trusted baseline at all, we
    // can fall back to it as an unanchored guess — never as a confident dot.
    return _degraded(now, mode, unanchoredFallback: fix);
  }

  /// Advance the controller when NO fix arrived but time moved on. Use this on
  /// a tick / timer so the radius keeps growing and the mode can reach `lost`
  /// during a GPS blackout.
  LocalizationEstimate poll(DateTime now) {
    if (_lastTrustedTime == null) {
      // Nothing has ever been trusted and nothing to guess from.
      return _emit(const LocalizationEstimate(
        latitude: double.nan,
        longitude: double.nan,
        confidenceRadiusMeters: double.infinity,
        mode: LocalizationMode.lost,
        secondsSinceTrustedFix: double.infinity,
        basis: EstimateBasis.unanchoredGuess,
      ));
    }
    // A long gap since the last trusted fix means GPS has effectively dropped.
    return _degraded(now, LocalizationMode.deadReckoning);
  }

  /// Build a degraded (suspect / DR / lost) estimate at [now]. Enforces the
  /// monotonic-radius and no-blend contract.
  LocalizationEstimate _degraded(
    DateTime now,
    LocalizationMode requestedMode, {
    RawFix? unanchoredFallback,
  }) {
    // No trusted baseline yet: the best we can honestly do is a coarse,
    // explicitly-unanchored guess (mode lost), or nothing.
    if (_lastTrustedTime == null) {
      if (unanchoredFallback != null &&
          unanchoredFallback.hasFiniteGeometry) {
        final r = _bumpFloor(
          _maxFinite(unanchoredFallback.accuracyMeters,
              config.maxTrustworthyRadiusMeters),
        );
        return _emit(LocalizationEstimate(
          latitude: unanchoredFallback.latitude,
          longitude: unanchoredFallback.longitude,
          confidenceRadiusMeters: r,
          mode: LocalizationMode.lost,
          secondsSinceTrustedFix: double.infinity,
          basis: EstimateBasis.unanchoredGuess,
        ));
      }
      return _emit(const LocalizationEstimate(
        latitude: double.nan,
        longitude: double.nan,
        confidenceRadiusMeters: double.infinity,
        mode: LocalizationMode.lost,
        secondsSinceTrustedFix: double.infinity,
        basis: EstimateBasis.unanchoredGuess,
      ));
    }

    final secondsDead =
        now.difference(_lastTrustedTime!).inMicroseconds / 1e6;
    final secondsSafe = secondsDead.isFinite && secondsDead >= 0
        ? secondsDead
        : 0.0;

    // Ask the dead-reckoning seam for a position (and maybe its own accuracy).
    DeadReckoningEstimate? dr;
    final seam = deadReckoningSeam;
    if (seam != null) {
      final candidate = seam(now);
      if (candidate != null && candidate.hasFiniteGeometry) {
        dr = candidate;
      }
    }

    final double lat;
    final double lon;
    final EstimateBasis basis;
    if (dr != null) {
      lat = dr.latitude;
      lon = dr.longitude;
      basis = EstimateBasis.deadReckoning;
    } else {
      // No seam (or it gave up): hold the last trusted position frozen.
      lat = _lastTrustedLat!;
      lon = _lastTrustedLon!;
      basis = EstimateBasis.lastKnownPosition;
    }

    // Documented growth model: last trusted accuracy + drift * seconds.
    //
    // When the dot is FROZEN at last-known (no seam carried it forward), the
    // vehicle may have travelled even though the dot has not. Floor the growth
    // rate by the last known ground speed so the confidence circle still
    // plausibly contains a vehicle that kept moving after GPS dropped. This
    // only ever GROWS the radius (more conservative), never shrinks it.
    var driftRate = config.driftRateMetersPerSecond;
    if (basis == EstimateBasis.lastKnownPosition &&
        _lastTrustedSpeed != null &&
        _lastTrustedSpeed!.isFinite &&
        _lastTrustedSpeed! > driftRate) {
      driftRate = _lastTrustedSpeed!;
    }
    final modelled = _lastTrustedAccuracy + driftRate * secondsSafe;

    // Radius = max(growth model, seam's own claim), then forced monotonic.
    var radius = modelled;
    final seamAcc = dr?.estimatedAccuracyMeters;
    if (seamAcc != null && seamAcc.isFinite && seamAcc > radius) {
      radius = seamAcc;
    }
    radius = _bumpFloor(radius);

    // Honesty horizon: too uncertain, or dead too long → lost.
    final beyondRadius = radius > config.maxTrustworthyRadiusMeters;
    final beyondTime = secondsSafe > config.maxDeadReckoningSeconds;
    final mode = (beyondRadius || beyondTime)
        ? LocalizationMode.lost
        : requestedMode;

    return _emit(LocalizationEstimate(
      latitude: lat,
      longitude: lon,
      confidenceRadiusMeters: radius,
      mode: mode,
      secondsSinceTrustedFix: secondsSafe,
      basis: basis,
    ));
  }

  /// Force the radius to never decrease while degraded, and remember the floor.
  double _bumpFloor(double candidate) {
    final r = candidate > _degradedRadiusFloor ? candidate : _degradedRadiusFloor;
    _degradedRadiusFloor = r;
    return r;
  }

  double _maxFinite(double a, double b) => a > b ? a : b;

  LocalizationEstimate _emit(LocalizationEstimate e) {
    _last = e;
    return e;
  }
}
