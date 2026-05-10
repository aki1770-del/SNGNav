/// Glance-budget-aware voice-pace adjustment profile.
///
/// Why this exists:
///
/// `voice_guidance` 0.4.0 ships per-`DriverProfile` speaking-rate
/// multipliers (a static per-cohort baseline; `kSpeakingRateMultiplier
/// ByProfile`). That baseline does not respond to live cognitive-load
/// state — when the driver's cumulative off-road glance time approaches
/// the NHTSA Phase 2 12-second budget, the same baseline-pace voice
/// announcement competes for attention against an already-overloaded
/// cognitive channel. This profile lets an integrator slow speech
/// further, dynamically, as the glance budget is consumed.
///
/// **Disabled by default** (opt-in via the `budgetAwarePace` field on
/// `VoiceGuidanceConfig`); preserves back-compat for existing 0.5.0
/// consumers that did not subscribe to a `GlanceBudgetTracker`.
///
/// **Caution-add-only invariant** (load-bearing): pace ≤ 1.0× baseline.
/// The profile asserts `minPace <= maxPace <= 1.0` at construction time;
/// the dynamic adjustment can only SLOW speech relative to the
/// per-profile baseline, never speed it up. A dynamic adjustment that
/// could speed speech past 1.0× would defeat the cognitive-load-relief
/// intent.
///
/// **Driver-always-drives invariant**: voice pace is presentation-
/// class only. The profile modulates the speaking-rate parameter the
/// TTS engine consumes; it does not actuate the vehicle, suppress
/// driver inputs, or close any control loop.
///
/// **Severity-not-profile invariant preserved**: pace adjustment does
/// not change severity. Critical alerts still fire (severity gate
/// remains upstream); the only effect at the audio channel is
/// slower-speak under high cognitive load.
///
/// Default magnitudes (UNVERIFIED-magnitude design-default-hypotheses):
///
/// - `minPace = 0.7` (effective rate floor when budget is fully
///   exhausted) — design-default; pending field-evidence on whether
///   0.7× is the right floor across cohorts.
/// - `maxPace = 1.0` (engine-base; matches the per-profile-baseline
///   behaviour when budget has barely been consumed) — anchored by the
///   pre-existing `kSpeakingRateMultiplierByProfile` baseline contract.
/// - `curve = InterpolationCurve.linear` (simple, monotone) — the
///   smoothstep alternative is reserved for v2 if integrators report
///   abrupt-pace-change UX issues.
///
/// Typical wiring:
///
/// ```dart
/// final config = VoiceGuidanceConfig(
///   budgetAwarePace: const BudgetAwarePaceProfile(),
/// );
/// // ...integrator wires GlanceBudgetTracker.budgetEvents into the
/// //    voice-guidance bloc; the bloc applies the interpolated rate
/// //    via `_ttsEngine.setSpeechRate(...)` next setSpeechRate call.
/// ```
library;

import 'package:equatable/equatable.dart';

/// Interpolation curve between [BudgetAwarePaceProfile.minPace] and
/// [BudgetAwarePaceProfile.maxPace] given a remaining-budget ratio in
/// `[0.0, 1.0]`.
enum InterpolationCurve {
  /// Linear interpolation. Default at v1.
  linear,

  /// Smoothstep (cubic Hermite); softer transitions near boundaries.
  /// Available at v1; reserved for graduation if integrator UX evidence
  /// supports it.
  smoothstep,
}

/// Configuration profile for glance-budget-aware voice-pace adjustment.
///
/// See library-level documentation for the caution-add-only invariant
/// and default-magnitude rationale.
class BudgetAwarePaceProfile extends Equatable {
  /// Effective rate floor when the glance budget is fully exhausted
  /// (remaining-budget ratio = 0). Default 0.7. Must be in
  /// `(0.0, maxPace]`.
  final double minPace;

  /// Effective rate ceiling when the glance budget is fully unused
  /// (remaining-budget ratio = 1). Default 1.0 (engine-base). Must be
  /// in `[minPace, 1.0]` — the caution-add-only invariant prevents the
  /// dynamic adjustment from speeding up speech above the per-profile
  /// baseline.
  final double maxPace;

  /// Interpolation curve between [minPace] and [maxPace]. Default
  /// linear.
  final InterpolationCurve curve;

  const BudgetAwarePaceProfile({
    this.minPace = 0.7,
    this.maxPace = 1.0,
    this.curve = InterpolationCurve.linear,
  }) : assert(minPace > 0.0, 'minPace must be greater than 0.0; got $minPace'),
       assert(
         minPace <= maxPace,
         'minPace must be <= maxPace; caution-add-only invariant',
       ),
       assert(
         maxPace <= 1.0,
         'maxPace must be <= 1.0; caution-add-only invariant '
         '(pace must never exceed engine-base)',
       );

  /// Compute the budget-aware pace multiplier given a remaining-budget
  /// ratio in `[0.0, 1.0]`. The integrator multiplies this value by
  /// the per-profile baseline (`kSpeakingRateMultiplierByProfile`) to
  /// get the effective TTS speaking rate.
  ///
  /// At ratio = 1.0 (full budget remaining) returns [maxPace];
  /// at ratio = 0.0 (budget exhausted) returns [minPace];
  /// values in between interpolate per [curve].
  double paceForRemainingRatio(double remainingRatio) {
    final clamped = remainingRatio.clamp(0.0, 1.0).toDouble();
    final t = switch (curve) {
      InterpolationCurve.linear => clamped,
      InterpolationCurve.smoothstep =>
        clamped * clamped * (3.0 - 2.0 * clamped),
    };
    return minPace + (maxPace - minPace) * t;
  }

  @override
  List<Object?> get props => [minPace, maxPace, curve];
}
