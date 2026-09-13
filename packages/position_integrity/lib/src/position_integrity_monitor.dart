import 'dart:collection';
import 'dart:math' as math;

import 'integrity_verdict.dart';
import 'position_fix.dart';

/// The calibration-free position-integrity floor: wrap your location stream,
/// hand each fused fix to [update], and act on the [IntegrityVerdict].
///
/// This is the FLOOR — layer (1) of the design. It needs nothing but the fixes
/// themselves (latitude/longitude/accuracy/timestamp): no motion model, no road
/// graph, no calibration, no network. It answers one question the platform's
/// accuracy number cannot: *is this fix physically possible given the last
/// one?* When it is not, the monitor says so and recommends a safe source.
///
/// It is deliberately crude and robust. The four gates are scalar physical
/// checks, not statistics, so they keep protecting even when a finer layer
/// (the optional NIS / chi-square consistency test that consumes a motion
/// prediction) is mistuned by degraded winter sensors. That finer layer is a
/// later slice; this floor stands alone and is useful alone.
///
/// This is an ADVISORY floor for app-level display / source-handoff decisions.
/// It is not a safety-rated function and must not be used as an input to
/// automated vehicle control.
///
/// HONESTY BOUND (see also [IntegrityStatus.trusted] and `KNOWN_LIMITATIONS.md`):
/// a `trusted` verdict means "no fault detected by these tests", never
/// "position verified". The gates catch ABRUPT faults (teleports, impossible
/// motion); they do NOT catch a slow, smooth spoof that walks the position away
/// gradually. Lead with multipath/teleport protection; do not market this as
/// anti-spoofing.
class PositionIntegrityMonitor {
  PositionIntegrityMonitor({
    this.maxPlausibleSpeed = 50.0,
    this.maxPlausibleAccel = 8.0,
    this.teleportMaxDistanceMetres = 30.0,
    this.minSpeedDelta = const Duration(milliseconds: 100),
    this.deadReckoningMaxAge = const Duration(seconds: 20),
    this.failAfterConsecutiveSoft = 2,
    this.jitterWindow = 4,
    this.stationaryRadiusMetres = 5.0,
    this.jitterAccuracyMultiplier = 3.0,
  }) {
    // These are RELEASE-MODE guards, deliberately not `assert`s.
    //
    // Until 2026-09-13 this constructor validated its configuration with five
    // asserts in the initializer list. Dart strips asserts from AOT builds
    // (`dart compile exe`, `flutter build --release`) AND from plain
    // `dart run`; they survive only under `dart test` / `flutter test` /
    // Flutter debug. Every test this package has ever produced was taken in
    // the one mode where those guards were present, and none of them existed
    // on a driver's device. `PositionIntegrityMonitor(jitterWindow: 1)` was
    // caught in every test run and in no shipped build.
    //
    // The failure was SILENT, which is what makes it worth an exception. A
    // degenerate `jitterWindow` does not crash: `_evaluateJitter` compares the
    // first and last fix of the window, so with a window of 1 or 2 the net
    // displacement IS the single step and `maxStep > threshold` can never be
    // true. The stationary-jitter gate — the one that catches a fix wandering
    // in place, which is the multipath case in a snow-walled canyon — is
    // simply off, and the monitor keeps returning `trusted`.
    //
    // These are CONFIGURATION values, fixed at construction, so an invalid one
    // throws wherever the integrator's code constructs the monitor. This
    // library cannot see where that is. Constructed at startup, it fails on
    // the developer's first run; constructed later from settings or remote
    // configuration, it throws at that moment, on the device. We do not
    // promise it lands off the drive. Runtime fix data is handled the
    // opposite way: `update` rejects a non-finite fix with a `failed` verdict
    // and never throws.
    _requireFinitePositive(maxPlausibleSpeed, 'maxPlausibleSpeed');
    _requireFinitePositive(maxPlausibleAccel, 'maxPlausibleAccel');
    _requireFinitePositive(
        teleportMaxDistanceMetres, 'teleportMaxDistanceMetres');
    // Not previously guarded at all. `_evaluateJitter` returns early when the
    // net displacement is >= this radius; at <= 0 that is every window, so the
    // jitter gate never fires — the same silent hole as a degenerate
    // `jitterWindow`, by a different door.
    _requireFinitePositive(stationaryRadiusMetres, 'stationaryRadiusMetres');
    // Not previously guarded. At <= 0 the multiplier drops out of
    // `math.max(stationaryRadiusMetres, multiplier * accuracy)`, which makes
    // the gate STRICTER rather than blind, so this is the lenient bound: a
    // negative or non-finite multiplier is nonsense, zero is merely useless.
    _requireFiniteNonNegative(
        jitterAccuracyMultiplier, 'jitterAccuracyMultiplier');
    if (failAfterConsecutiveSoft < 1) {
      // At 0, `_consecutiveSoft >= failAfterConsecutiveSoft` is already true on
      // the first soft fault, so the debounce this parameter exists to provide
      // is gone and one acceleration glitch fails the fix outright.
      throw RangeError.range(
        failAfterConsecutiveSoft,
        1,
        null,
        'failAfterConsecutiveSoft',
        'a soft fault must be allowed to occur at least once before it '
            'escalates; 0 or less defeats the debounce entirely',
      );
    }
    if (jitterWindow < 3) {
      // < 3 makes the stationary-jitter window degenerate (net == the single
      // step), so the gate could never fire; require at least 3.
      throw RangeError.range(
        jitterWindow,
        3,
        null,
        'jitterWindow',
        'below 3 the window net displacement equals its single step, so the '
            'stationary-jitter gate can never fire and is silently disabled',
      );
    }
    if (minSpeedDelta <= Duration.zero) {
      // Not previously guarded. `update` only reaches the teleport gate when
      // dt < minSpeedDelta, and dt is always > 0 (a non-monotonic fix is
      // rejected earlier), so at <= 0 the teleport gate is never evaluated and
      // never appears in `gateResults` — indistinguishable, to a caller
      // auditing that map, from a gate that passed.
      throw ArgumentError.value(
        minSpeedDelta,
        'minSpeedDelta',
        'must be a positive duration; at zero or less the teleport gate is '
            'never evaluated',
      );
    }
    if (deadReckoningMaxAge < Duration.zero) {
      throw ArgumentError.value(
        deadReckoningMaxAge,
        'deadReckoningMaxAge',
        'must not be negative; a negative maximum age can never be satisfied, '
            'so the monitor would always recommend SourceHint.hold',
      );
    }
  }

  /// Rejects NaN, infinity and non-positive values for a threshold.
  ///
  /// The `isFinite` test is the load-bearing half, and it is why this is not
  /// written as a bare `value <= 0`:
  ///
  ///  * `double.infinity > 0` is TRUE, so infinity passed the assert this
  ///    replaced — and then `impliedSpeed > double.infinity` is always false,
  ///    so the gate using it is silently off. The original assert never caught
  ///    this.
  ///  * `double.nan <= 0` is FALSE, so a rewrite to a plain `value <= 0` would
  ///    LOSE the NaN rejection the assert did have. NaN propagates the same
  ///    way: every `x > nan` is false, gate off, verdict still `trusted`.
  static void _requireFinitePositive(double value, String name) {
    if (!value.isFinite || value <= 0) {
      throw ArgumentError.value(
        value,
        name,
        'must be a finite number greater than 0 (NaN and infinity silently '
        'disable the gate that uses it)',
      );
    }
  }

  /// As [_requireFinitePositive], but zero is permitted.
  static void _requireFiniteNonNegative(double value, String name) {
    if (!value.isFinite || value < 0) {
      throw ArgumentError.value(
        value,
        name,
        'must be a finite number greater than or equal to 0 (NaN and infinity '
        'silently disable the gate that uses it)',
      );
    }
  }

  /// Maximum plausible road-vehicle speed, in metres/second (default 50 m/s ≈
  /// 180 km/h). The implied speed between two fixes above this fails the
  /// [GateId.impossibleSpeed] gate. Raise it for genuine high-speed contexts.
  final double maxPlausibleSpeed;

  /// Maximum plausible change in speed, in metres/second² (default 8 m/s² —
  /// hard braking / strong launch). Above this fails [GateId.impossibleAccel].
  final double maxPlausibleAccel;

  /// In the degenerate regime where the time delta is below [minSpeedDelta]
  /// (so a speed cannot be computed reliably), a jump beyond this many metres
  /// fails the [GateId.teleport] gate (default 30 m).
  final double teleportMaxDistanceMetres;

  /// Below this positive time delta, the implied speed/acceleration are treated
  /// as unreliable and the monitor uses the absolute-jump [GateId.teleport]
  /// check instead of the rate gates (default 100 ms, i.e. the rate gates run
  /// for fused streams up to ~10 Hz).
  final Duration minSpeedDelta;

  /// On a fault, [SourceHint.deadReckoning] is only recommended if the caller
  /// passed a `deadReckoningAge` no older than this (default 20 s). Otherwise
  /// the monitor recommends the conservative [SourceHint.hold].
  final Duration deadReckoningMaxAge;

  /// A soft fault (impossible acceleration) escalates from
  /// [IntegrityStatus.suspect] to [IntegrityStatus.failed] only after this many
  /// CONSECUTIVE such faults (default 2), to avoid flapping on one glitch. Hard
  /// faults (teleport, impossible speed) fail immediately; stationary jitter is
  /// suspect-only and never escalates.
  final int failAfterConsecutiveSoft;

  /// How many recent fixes the stationary-jitter gate looks back over (>= 3).
  final int jitterWindow;

  /// Net displacement (metres) below which, across [jitterWindow], the vehicle
  /// is considered stationary for the jitter gate (default 5 m).
  final double stationaryRadiusMetres;

  /// While stationary, a single step longer than this multiple of the fix's
  /// reported accuracy counts as jitter (default 3×).
  final double jitterAccuracyMultiplier;

  PositionFix? _last;
  double? _lastImpliedSpeed;
  // The interval (seconds) over which _lastImpliedSpeed was measured. Paired
  // with _lastImpliedSpeed — always set and cleared together — so the
  // acceleration gate can divide the speed change by the mean of the two
  // intervals rather than the current one alone.
  double? _lastDtSeconds;
  int _consecutiveSoft = 0;
  final Queue<PositionFix> _recent = Queue<PositionFix>();

  /// Whether at least one fix has been observed.
  bool get isInitialized => _last != null;

  /// Reset the monitor to its initial state (e.g. after a session boundary).
  void reset() {
    _last = null;
    _lastImpliedSpeed = null;
    _lastDtSeconds = null;
    _consecutiveSoft = 0;
    _recent.clear();
  }

  /// Evaluate [fix] against the previous fix and return the [IntegrityVerdict].
  ///
  /// Pass [deadReckoningAge] — how long ago your dead-reckoning estimate was
  /// last good — to allow the monitor to recommend [SourceHint.deadReckoning]
  /// on a fault; without it (or if it is older than [deadReckoningMaxAge]) the
  /// monitor recommends [SourceHint.hold].
  IntegrityVerdict update(PositionFix fix, {Duration? deadReckoningAge}) {
    // A non-finite / out-of-range fix is the most impossible fix there is. Fail
    // it without advancing any state (never let NaN poison the speed estimate).
    if (!_isUsable(fix)) {
      return IntegrityVerdict(
        status: IntegrityStatus.failed,
        recommendedSource: _faultSource(deadReckoningAge),
        reason: 'non-finite or out-of-range fix',
        gateResults: const <GateId, bool>{},
      );
    }

    final previous = _last;

    // First fix: nothing to compare against. Initialise and trust.
    if (previous == null) {
      _last = fix;
      _recent
        ..clear()
        ..addLast(fix);
      return const IntegrityVerdict(
        status: IntegrityStatus.trusted,
        recommendedSource: SourceHint.gps,
        reason: 'first fix — no prior position to compare',
        gateResults: <GateId, bool>{},
      );
    }

    // Non-monotonic fix (duplicate or out-of-order timestamp): we cannot reason
    // about motion, and advancing state on it would corrupt the baseline. Flag
    // suspect and skip — do not advance _last / _recent / _lastImpliedSpeed.
    if (!fix.timestamp.isAfter(previous.timestamp)) {
      return const IntegrityVerdict(
        status: IntegrityStatus.suspect,
        recommendedSource: SourceHint.gps,
        reason: 'out-of-order or duplicate timestamp — skipped',
        gateResults: <GateId, bool>{},
      );
    }

    _pushRecent(fix);

    final distance = _haversineMetres(previous, fix);
    final interval = fix.timestamp.difference(previous.timestamp);
    final dtSeconds = interval.inMicroseconds / 1e6;

    final tests = <GateId, bool>{};
    final faults = <_Fault>[];

    if (dtSeconds < minSpeedDelta.inMicroseconds / 1e6) {
      // Degenerate regime: positive but too brief for a reliable speed. Use the
      // absolute-jump teleport check; leave the rate gates unevaluated.
      final teleport = distance > teleportMaxDistanceMetres;
      tests[GateId.teleport] = !teleport;
      if (teleport) {
        faults.add(_Fault.hard(GateId.teleport,
            'teleport: ${distance.toStringAsFixed(0)} m in '
            '${dtSeconds.toStringAsFixed(2)} s'));
      }
      // no reliable speed to carry forward — clear the paired speed+interval
      _lastImpliedSpeed = null;
      _lastDtSeconds = null;
    } else {
      final impliedSpeed = distance / dtSeconds;

      final tooFast = impliedSpeed > maxPlausibleSpeed;
      tests[GateId.impossibleSpeed] = !tooFast;
      if (tooFast) {
        faults.add(_Fault.hard(GateId.impossibleSpeed,
            'impossible speed: ${impliedSpeed.toStringAsFixed(0)} m/s '
            '(max ${maxPlausibleSpeed.toStringAsFixed(0)})'));
      }

      final lastSpeed = _lastImpliedSpeed;
      final lastDt = _lastDtSeconds;
      if (lastSpeed != null && lastDt != null) {
        // Each implied speed is an average over its own interval, best
        // attributed to that interval's midpoint; the elapsed time between the
        // two speed samples is therefore the MEAN of the two intervals.
        // Dividing the speed change by the current dt alone inflates the
        // acceleration when sampling is irregular — a short burst after a long
        // dropout, the winter-canyon reacquisition pattern — and fabricates an
        // impossibleAccel fault on legitimate motion.
        final accelDt = 0.5 * (dtSeconds + lastDt);
        final accel = (impliedSpeed - lastSpeed).abs() / accelDt;
        final tooHard = accel > maxPlausibleAccel;
        tests[GateId.impossibleAccel] = !tooHard;
        if (tooHard) {
          faults.add(_Fault.soft(GateId.impossibleAccel,
              'impossible acceleration: ${accel.toStringAsFixed(1)} m/s^2 '
              '(max ${maxPlausibleAccel.toStringAsFixed(1)})'));
        }
      }
      // Never seed the acceleration baseline with a speed that already failed
      // its own gate — that would spuriously flag the next legitimate fix.
      // Keep the speed and its interval paired.
      _lastImpliedSpeed = tooFast ? null : impliedSpeed;
      _lastDtSeconds = tooFast ? null : dtSeconds;
    }

    // Stationary-jitter gate (history-based; suspect-only).
    final jitter = _evaluateJitter(fix);
    if (jitter != null) {
      tests[GateId.stationaryJitter] = false;
      faults.add(jitter);
    } else if (_recent.length >= jitterWindow) {
      tests[GateId.stationaryJitter] = true;
    }

    _last = fix;
    return _aggregate(faults, tests, deadReckoningAge, interval);
  }

  IntegrityVerdict _aggregate(
    List<_Fault> faults,
    Map<GateId, bool> tests,
    Duration? deadReckoningAge,
    Duration interFixInterval,
  ) {
    if (faults.isEmpty) {
      _consecutiveSoft = 0;
      return IntegrityVerdict(
        status: IntegrityStatus.trusted,
        recommendedSource: SourceHint.gps,
        reason: 'no fault detected',
        gateResults: Map.unmodifiable(tests),
        interFixInterval: interFixInterval,
      );
    }

    final hard = faults.where((f) => f.hard).toList();
    if (hard.isNotEmpty) {
      _consecutiveSoft = 0;
      return IntegrityVerdict(
        status: IntegrityStatus.failed,
        recommendedSource: _faultSource(deadReckoningAge),
        reason: hard.map((f) => f.reason).join('; '),
        gateResults: Map.unmodifiable(tests),
        interFixInterval: interFixInterval,
      );
    }

    // Soft fault(s) only. Stationary jitter is suspect-only and never escalates;
    // only a NON-jitter soft fault (impossible acceleration) drives escalation.
    final escalatingSoft = faults.any((f) => f.gate != GateId.stationaryJitter);
    if (!escalatingSoft) {
      _consecutiveSoft = 0; // an escalating fault did not recur
      return IntegrityVerdict(
        status: IntegrityStatus.suspect,
        recommendedSource: SourceHint.gps,
        reason: faults.map((f) => f.reason).join('; '),
        gateResults: Map.unmodifiable(tests),
        interFixInterval: interFixInterval,
      );
    }

    _consecutiveSoft++;
    final escalated = _consecutiveSoft >= failAfterConsecutiveSoft;
    return IntegrityVerdict(
      status: escalated ? IntegrityStatus.failed : IntegrityStatus.suspect,
      recommendedSource:
          escalated ? _faultSource(deadReckoningAge) : SourceHint.gps,
      reason: '${faults.map((f) => f.reason).join('; ')}'
          '${escalated ? ' (sustained ×$_consecutiveSoft)' : ''}',
      gateResults: Map.unmodifiable(tests),
      interFixInterval: interFixInterval,
    );
  }

  /// On a fault, hand off to dead reckoning only if the caller said it is fresh;
  /// otherwise hold. The monitor cannot judge DR QUALITY — only its recency —
  /// so when in doubt it holds rather than switch to a possibly-degraded source.
  SourceHint _faultSource(Duration? deadReckoningAge) {
    if (deadReckoningAge != null &&
        deadReckoningAge >= Duration.zero &&
        deadReckoningAge <= deadReckoningMaxAge) {
      return SourceHint.deadReckoning;
    }
    return SourceHint.hold;
  }

  _Fault? _evaluateJitter(PositionFix fix) {
    if (_recent.length < jitterWindow) return null;
    final window = _recent.toList();
    final net = _haversineMetres(window.first, window.last);
    if (net >= stationaryRadiusMetres) return null; // not stationary

    // Stationary across the window, yet a single step jumped far relative to
    // the reported accuracy → the fix is wandering in place.
    final threshold = math.max(
        stationaryRadiusMetres, jitterAccuracyMultiplier * fix.accuracyMetres);
    var maxStep = 0.0;
    for (var i = 1; i < window.length; i++) {
      final step = _haversineMetres(window[i - 1], window[i]);
      if (step > maxStep) maxStep = step;
    }
    if (maxStep > threshold) {
      return _Fault.soft(GateId.stationaryJitter,
          'stationary jitter: ${maxStep.toStringAsFixed(0)} m step while net '
          'displacement ${net.toStringAsFixed(0)} m');
    }
    return null;
  }

  void _pushRecent(PositionFix fix) {
    _recent.addLast(fix);
    while (_recent.length > jitterWindow) {
      _recent.removeFirst();
    }
  }

  static bool _isUsable(PositionFix f) =>
      f.latitude.isFinite &&
      f.longitude.isFinite &&
      f.accuracyMetres.isFinite &&
      f.latitude.abs() <= 90 &&
      f.longitude.abs() <= 180;

  static const double _earthRadiusMetres = 6371000.0;

  static double _haversineMetres(PositionFix a, PositionFix b) {
    final lat1 = a.latitude * math.pi / 180.0;
    final lat2 = b.latitude * math.pi / 180.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180.0;
    final dLon = (b.longitude - a.longitude) * math.pi / 180.0;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * _earthRadiusMetres * math.asin(math.min(1.0, math.sqrt(h)));
  }
}

/// Internal: a single gate violation, tagged hard (fail now) or soft (debounce).
class _Fault {
  _Fault.hard(this.gate, this.reason) : hard = true;
  _Fault.soft(this.gate, this.reason) : hard = false;

  final GateId gate;
  final String reason;
  final bool hard;
}
