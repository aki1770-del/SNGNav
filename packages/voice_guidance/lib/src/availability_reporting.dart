/// The third state, added WITHOUT breaking a single implementer.
///
/// **The defect this routes around.** [TtsEngine.isAvailable] and
/// [HapticEngine.isAvailable] return `Future<bool>`, which cannot say *"we
/// could not tell"*. A probe that fails — no platform channel, a plugin
/// exception, a host that never answers — must therefore return `false`, and
/// an integrator reads that as *"this device has no speech"*. Those are
/// different facts and only one of them is actionable.
///
/// Measured 2026-08-30 against AGL's shipped `ondemandnavi`: its guidance path
/// builds a shell string, calls `system()` and **discards the return value**,
/// so a failed announcement is indistinguishable from a delivered one and a
/// turn simply goes unspoken. A consumer of a two-state availability answer
/// inherits that blind spot one layer up.
///
/// This package's own host app is three-state throughout — `VoiceLaneVerdict
/// .unknown`, `AudioReadiness?`, `HapticReadinessProbe.read() -> Future<bool?>`
/// — and renders NOTHING on unknown rather than guessing. These interfaces give
/// integrators the answer we kept for ourselves (D1, D4: all weavers, the same
/// loom).
///
/// **Why a side-interface and not a default method.** Measured, not assumed:
/// adding `Future<bool?> readAvailability() async => ...` to [TtsEngine] with a
/// default body FAILS TO COMPILE for every `implements TtsEngine` class —
/// Dart's `implements` demands every member, concrete bodies included. Our own
/// `LinuxTtsEngine` broke instantly, and so would every integrator's engine.
/// A separate interface is opt-in, polymorphic, and breaks nobody. The same
/// shape this codebase already uses for `AdvisoryFeedFreshnessReporting`.
///
/// Callers use it by probing:
/// ```dart
/// final e = myEngine;
/// final bool? ready =
///     e is AvailabilityReporting ? await e.readAvailability() : null;
/// // `null` means UNKNOWN — render nothing, never a guess.
/// ```
library;

/// Opt-in capability: an engine that can distinguish *unavailable* from
/// *could not tell*.
abstract class AvailabilityReporting {
  /// `true` ready · `false` genuinely unavailable · **`null` = could not tell.**
  ///
  /// Implementations MUST return `null` rather than `false` when the probe
  /// itself failed to produce an answer.
  Future<bool?> readAvailability();
}
