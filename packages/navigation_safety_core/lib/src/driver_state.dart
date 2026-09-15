/// Live driver-state axis (transient), orthogonal to [DriverProfile] (trait).
///
/// Regan and Strayer 2014 (PMC4001671, "Towards an understanding of
/// driver inattention: taxonomy and theory") list driver conditions
/// (e.g. young, inexperienced, old) and driver states (e.g. bored,
/// sleepy, fatigued, drugged, emotional) as factors in driver
/// inattention. This package treats trait (who the driver is) and state
/// (what state the driver is in right now) as separate inputs. Our
/// v0.5.0 taxonomy collapsed both into trait via [DriverProfile].
/// v0.6.0 introduces this state axis as an additive, opt-in dimension;
/// consumers that pass only a [DriverProfile] continue to receive the
/// v0.5.0 behaviour.
///
/// State is intentionally coarse-grained at this spike. The full
/// trait × state matrix is a v1.0 architecture decision.
/// This enum is a forward-
/// compatible foothold, not the final shape.
///
/// State adjustments are **conservative-only** for thresholds — they
/// may make the thresholds warn earlier than the per-profile baseline,
/// never later. An earlier threshold has its own cost:
/// [DriverState.impairedVisibility] also moves the info and critical
/// visibility thresholds earlier, and info and critical alerts take
/// slots in `AlertDensityThrottle`'s rolling window as warnings do, so
/// a later warning can be dropped.
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
