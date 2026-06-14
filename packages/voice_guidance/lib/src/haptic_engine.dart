/// Abstract tactile (haptic) engine used by the accessibility hazard channel.
library;

import 'package:navigation_safety_enums/navigation_safety_enums.dart';

/// Renders a [HapticCuePattern] as a physical tactile sensation.
///
/// **Why this exists** — accessibility. The audio channel is not a universal
/// channel: a deaf or hard-of-hearing driver receives nothing from an
/// audio-only hazard warning, and neither does a hearing driver inside a
/// roaring-wind whiteout where speech cannot carry. The haptic channel
/// carries the **same hazard warning** off the **same severity gate** as
/// the audio channel — never a reduced subset.
///
/// The engine is **additive and advisory**: it renders a cue *beside* the
/// audio channel; it never gates, delays, or silences audio, and it holds
/// no actuator authority. A [cue] call must not throw — an unavailable or
/// failed haptic platform degrades silently to no sensation (honest
/// degradation), exactly as the audio [TtsEngine] does for missing TTS.
///
/// The cue is a pure function of severity (see [hapticCueForSeverity]); the
/// engine takes a [HapticCuePattern] and never a `DriverProfile`. Severity
/// decides whether/what; a profile only ever decides how.
abstract class HapticEngine {
  /// Returns true if this engine can render tactile cues.
  ///
  /// Truthful-degradation contract: returns false once the haptic platform
  /// has reported itself missing (e.g. `MissingPluginException` on a host
  /// with no engine plugin). See the per-implementation note on what
  /// "available" can and cannot guarantee about a physical vibration motor.
  Future<bool> isAvailable();

  /// Renders [pattern] as a tactile sensation.
  ///
  /// [HapticCuePattern.none] produces no sensation. Implementations MUST NOT
  /// throw: a missing or failed haptic platform degrades silently so the
  /// audio channel is never affected.
  Future<void> cue(HapticCuePattern pattern);

  /// Stops any in-progress tactile rendering.
  Future<void> stop();

  /// Releases engine resources.
  Future<void> dispose();
}
