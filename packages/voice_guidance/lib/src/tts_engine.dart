/// Abstract text-to-speech engine used by voice guidance flows.
library;

abstract class TtsEngine {
  /// Returns true if this engine can serve speech requests.
  Future<bool> isAvailable();

  /// Sets a BCP-47 language tag such as `ja-JP` or `en-US`.
  Future<void> setLanguage(String languageTag);

  /// Sets normalized output volume in `[0.0, 1.0]`.
  Future<void> setVolume(double volume);

  /// Speaks the provided text.
  Future<void> speak(String text);

  /// Stops any in-progress speech.
  Future<void> stop();

  /// Releases engine resources.
  Future<void> dispose();
}
