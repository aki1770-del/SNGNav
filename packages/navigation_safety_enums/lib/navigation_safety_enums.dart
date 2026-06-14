/// Pure Dart navigation-safety domain enums.
///
/// This package re-exports five enum types that constitute the
/// stable domain-vocabulary baseline shared across navigation-safety
/// consumers:
///
/// - [AlertSeverity] — info / warning / critical, with declaration-
///   order-load-bearing severity comparison via `.index`.
/// - [CircadianPhase] — 24-hour partition for circadian-aware
///   threshold tuning, with caution-add-only multiplier extension.
/// - [DriverState] — live driver-state axis (alert / fatigued /
///   distracted / impairedVisibility), orthogonal to driver-trait.
/// - [DriverProfile] — driver-class trait axis (ageingRural /
///   snowZoneExperienced / noviceUrban / professional /
///   agriculturalForestry / foreignTouristSnowZone).
/// - [HapticCuePattern] — tactile hazard-cue grammar (none / warning /
///   critical) for the accessibility channel, with a pure
///   [hapticCueForSeverity] mapping that mirrors the audio severity gate
///   one-for-one so a deaf driver's cue set equals the hearing driver's
///   warning set.
///
/// No Flutter dependency. No transitive dependencies. Each source
/// file is byte-identical to the corresponding file in
/// `navigation_safety_core` 0.10.0 at extraction time; future
/// releases of `navigation_safety_core` are expected to depend-on
/// and re-export from this package for ABI-compat.
library;

export 'src/alert_severity.dart';
export 'src/circadian_phase.dart';
export 'src/driver_profile.dart';
export 'src/driver_state.dart';
export 'src/haptic_cue_pattern.dart';
