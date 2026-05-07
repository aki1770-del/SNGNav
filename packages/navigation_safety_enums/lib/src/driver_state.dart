/// Live driver-state axis (transient), orthogonal to [DriverProfile] (trait).
///
/// Per Regan, Hallett & Gordon (2011) PMC4001671 — "Driver distraction
/// and driver inattention: definitions, relationship and taxonomy" —
/// trait (who the driver is) and state (what state the driver is in
/// right now) are orthogonal axes of risk. Our v0.5.0 taxonomy collapsed
/// both into trait via [DriverProfile]. v0.6.0 introduces this state
/// axis as an additive, opt-in dimension; consumers that pass only a
/// [DriverProfile] continue to receive the v0.5.0 behaviour.
///
/// State is intentionally coarse-grained at this spike. The full
/// trait × state matrix (Regan T3) is a v1.0 architecture decision
/// per insight #23 of the HER Pivot 100. This enum is a forward-
/// compatible foothold, not the final shape.
///
/// State adjustments are **conservative-only** — they may make the
/// thresholds warn earlier than the per-profile baseline, never later.
/// See `KNOWN_LIMITATIONS.md` (state-axis section, 0.6.0) for the
/// UNVERIFIED-magnitude flag on every state-effect delta below.
library;

/// Live driver-state for state-aware threshold tuning.
///
/// Pass alongside a [DriverProfile] in a [DriverContext]; the
/// resulting context can be handed to
/// `NavigationSafetyConfig.forDriverContext` to receive thresholds
/// tuned to both axes.
enum DriverState {
  /// Baseline state — well-rested, attentive, sensorily-unimpaired.
  /// No state-axis adjustment is applied; the per-profile thresholds
  /// are returned unchanged.
  alert,

  /// Fatigued state — long-drive, post-shift, late-hour. Reaction
  /// time degrades; cognitive bandwidth narrows. State-axis
  /// adjustment: small additive reaction-time penalty (visibility
  /// threshold expands), small additive temperature warning lift.
  /// Magnitudes UNVERIFIED at this spike (see KNOWN_LIMITATIONS).
  fatigued,

  /// Distracted state — smartphone-native multi-task default,
  /// passenger-conversation load, in-vehicle-info-system interaction.
  /// State-axis adjustment: larger additive reaction-time penalty.
  /// Magnitudes UNVERIFIED at this spike (see KNOWN_LIMITATIONS).
  distracted,

  /// Sensorily-impaired state — sun glare, snow whiteout, headlight
  /// glare, fog. Visual processing is degraded independent of trait.
  /// State-axis adjustment: visibility threshold expands more
  /// aggressively; temperature unchanged. Magnitudes UNVERIFIED at
  /// this spike (see KNOWN_LIMITATIONS).
  impairedVisibility,
}
