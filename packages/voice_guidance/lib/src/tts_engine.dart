/// Abstract text-to-speech engine used by voice guidance flows.
library;

/// Outcome of the most recent [TtsEngine.speak] call.
///
/// A queued utterance is not a heard one. An engine that cannot observe its own
/// output reports [unknown] rather than letting "accepted" read as "delivered" —
/// for a driver in unexpected snow the difference is the whole warning.
enum SpeechDelivery {
  /// The engine confirmed the utterance finished.
  delivered,

  /// The engine reported a failure, or did not finish within the bound.
  failed,

  /// Not observable on this engine. Never treat as delivered.
  unknown,
}

/// An engine that can report whether its last utterance actually arrived.
///
/// Kept OFF [TtsEngine] deliberately. A member added there — even one with a
/// body — breaks every existing `implements TtsEngine`, which the analyzer
/// proved on this package's own two sibling engines. Consumers opt in with
/// `if (engine is DeliveryObservable)`; anything that does not implement it is
/// simply unobserved, which is the truth rather than a silent pass.
abstract interface class DeliveryObservable {
  /// Outcome of the most recent `speak`. Never [SpeechDelivery.delivered]
  /// unless the engine confirmed it.
  SpeechDelivery get lastDelivery;
}

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
