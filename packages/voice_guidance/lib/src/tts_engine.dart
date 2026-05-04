/// Abstract text-to-speech engine used by voice guidance flows.
library;

abstract class TtsEngine {
  /// Returns true if this engine can serve speech requests.
  Future<bool> isAvailable();

  /// Sets a BCP-47 language tag such as `ja-JP` or `en-US`.
  Future<void> setLanguage(String languageTag);

  /// Sets normalized output volume in `[0.0, 1.0]`.
  Future<void> setVolume(double volume);

  /// Sets normalized speaking rate. Engines map this onto their own
  /// rate scale; the default base rate is `1.0` (engine-default).
  /// Implementations clamp the value to a sensible per-engine range.
  ///
  /// **Driver-facing rationale**: a Japanese announcer's standard
  /// pace is too fast for an older rural driver and a foreign-tourist
  /// driver in unexpected snow; per-profile rate lets each driver
  /// hear the line at a pace they can act on. The
  /// `VoiceGuidanceConfig.speakingRateForProfile()` helper returns
  /// per-profile rate multipliers anchored on the Strayer-AAA
  /// auditory-load study (PMC7283540) and the package's published
  /// per-profile threshold differentiation.
  Future<void> setSpeechRate(double rate);

  /// Speaks the provided text.
  Future<void> speak(String text);

  /// Stops any in-progress speech.
  Future<void> stop();

  /// Releases engine resources.
  Future<void> dispose();
}
