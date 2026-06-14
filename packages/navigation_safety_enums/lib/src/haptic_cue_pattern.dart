/// Tactile (haptic) hazard-cue grammar for the accessibility channel.
library;

import 'alert_severity.dart';

/// The class of tactile cue a hazard warning is rendered as on the haptic
/// (vibration) channel.
///
/// **Why this exists** — accessibility. The audio channel is not a universal
/// channel: a deaf or hard-of-hearing driver receives nothing from an
/// audio-only hazard warning, and neither does a hearing driver inside a
/// roaring-wind whiteout where speech cannot carry. The haptic channel must
/// therefore carry the **same warning set** as the audio channel, fired off
/// the **same severity gate** — never a reduced subset that silently drops
/// the most serious warnings for the driver who can least afford to miss them.
///
/// **Why the grammar is differentiated** — grounded in recorded driver
/// voices (see `DRIVER_VOICES.md`, the deaf / hard-of-hearing entry citing
/// SafeDrive4Deaf n=25/100%, Bauman 2009, and Gaffary & Lécuyer 2018):
/// a single undifferentiated buzz is *worse than honest*. A deaf driver who
/// feels one generic vibration cannot act on it — they cannot tell *reduce
/// speed* from *consider turning back*. The cited evidence shows differentiated
/// cues are both wanted (SafeDrive4Deaf colour-coding: red = immediate,
/// yellow = distant) and effective (Gaffary & Lécuyer: dynamic, patterned
/// vibration — not a single static buzz — differentiates urgency and shortens
/// reaction time). So the grammar **distinguishes severity**.
///
/// **What it maps from** — the channel this cue is rendered beside gates on
/// [AlertSeverity] (the type the hazard event carries). Map from that gate
/// via [hapticCueForSeverity]; the cue is a pure function of severity ONLY,
/// never of a driver profile (severity decides whether/what; a profile only
/// ever decides how).
///
/// **Correspondence to the higher-layer `RecommendedResponse` tiers**
/// (defined in `snow_rendering`, deliberately NOT imported here to keep this
/// package Flutter-free with no transitive deps) is one-for-one:
///
/// | RecommendedResponse   | AlertSeverity | HapticCuePattern |
/// |-----------------------|---------------|------------------|
/// | proceed               | info          | none             |
/// | reduceSpeed           | warning       | warning          |
/// | considerTurningBack   | critical      | critical         |
///
/// Declaration order is load-bearing in the same way as [AlertSeverity]:
/// it parallels the severity ranking and is locked by
/// `test/haptic_cue_pattern_test.dart`.
enum HapticCuePattern {
  /// No tactile cue. Corresponds to [AlertSeverity.info] / the `proceed`
  /// response tier — the audio channel does not announce info-class alerts,
  /// so the haptic channel produces no cue either (set parity).
  none,

  /// "Reduce speed" tier. Corresponds to [AlertSeverity.warning] / the
  /// `reduceSpeed` response tier. Rendered as a distinct, less-urgent
  /// patterned cue (see [pulseCount]).
  warning,

  /// "Consider turning back" tier. Corresponds to [AlertSeverity.critical] /
  /// the `considerTurningBack` response tier. Rendered as a distinct,
  /// more-urgent patterned cue (see [pulseCount]) so a deaf driver can tell
  /// it apart from the warning cue.
  critical,
}

/// Pure (Flutter-free) rendering parameters for a [HapticCuePattern].
extension HapticCuePatternRendering on HapticCuePattern {
  /// Number of discrete pulses the cue is composed of.
  ///
  /// This is the *grammar*, not a platform call: a Flutter-side engine
  /// renders these as N escalating-intensity impacts. The counts are chosen
  /// so the two announced tiers are doubly distinguishable — by count
  /// (2 vs 3) and, at the rendering layer, by intensity (medium vs heavy):
  ///
  /// - [HapticCuePattern.none]: `0` (no sensation)
  /// - [HapticCuePattern.warning]: `2` (a measured double-pulse)
  /// - [HapticCuePattern.critical]: `3` (an urgent triple-pulse)
  int get pulseCount => switch (this) {
    HapticCuePattern.none => 0,
    HapticCuePattern.warning => 2,
    HapticCuePattern.critical => 3,
  };

  /// True when this cue produces an actual tactile sensation (i.e. it is a
  /// real warning the driver should feel). The set of severities for which
  /// this is true is exactly the set the audio channel announces — see
  /// [hapticCueForSeverity].
  bool get isTactile => this != HapticCuePattern.none;
}

/// Maps an [AlertSeverity] to its tactile [HapticCuePattern].
///
/// This is the haptic channel's severity gate, and it mirrors the audio
/// channel's gate exactly: the audio channel announces a hazard iff
/// `severity.index >= AlertSeverity.warning.index`, and this function returns
/// a tactile (non-[HapticCuePattern.none]) cue for exactly that same set
/// `{warning, critical}`. The deaf driver's cue set therefore equals the
/// hearing driver's warning set — no reduced subset — with the two announced
/// tiers rendered as **distinct** cues so they can be told apart.
///
/// Pure function of severity only; takes no driver profile by construction.
HapticCuePattern hapticCueForSeverity(AlertSeverity severity) =>
    switch (severity) {
      AlertSeverity.info => HapticCuePattern.none,
      AlertSeverity.warning => HapticCuePattern.warning,
      AlertSeverity.critical => HapticCuePattern.critical,
    };
