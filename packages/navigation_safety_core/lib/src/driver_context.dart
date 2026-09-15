/// Trait × state composite driver context.
///
/// Couples a [DriverProfile] (trait — who the driver is) with a
/// [DriverState] (live state — what state the driver is in right now).
/// This is the v0.6.0 spike implementation of the trait/state split.
/// Regan and Strayer 2014 (PMC4001671) list driver conditions and
/// driver states as factors in driver inattention.
///
/// `DriverContext` is **opt-in** and **additive**. v0.5.0 callers that
/// continue to pass [DriverProfile] alone to existing factories
/// (`NavigationSafetyConfig.forProfile`,
/// `NavigationSafetyConfig.forProfileWithContext`) see no behaviour
/// change. The new factory `NavigationSafetyConfig.forDriverContext`
/// is the only way to opt into state-axis tuning.
///
/// State adjustments are conservative-only for thresholds (per the 0.5.0
/// contract): they may make thresholds warn earlier than the per-profile
/// baseline, never later. An earlier info or critical threshold can
/// still cost a later warning its slot in `AlertDensityThrottle`'s
/// window; see `driver_state.dart`. See `KNOWN_LIMITATIONS.md`
/// (state-axis section) for the per-state delta shapes and the
/// UNVERIFIED-magnitude disclosure on every state-effect.
library;

import 'package:equatable/equatable.dart';

import 'driver_profile.dart';
import 'driver_state.dart';

/// Trait × state composite driver context.
///
/// Construct via the default constructor or the [combineWith] factory.
/// Both produce the same shape; `combineWith` reads more naturally at
/// call-sites that already hold a profile.
class DriverContext extends Equatable {
  /// Driver-class trait. See [DriverProfile] for class semantics.
  final DriverProfile profile;

  /// Live driver state. See [DriverState] for state semantics.
  final DriverState state;

  /// Construct a context value from explicit trait + state.
  const DriverContext({required this.profile, required this.state});

  /// Combine a [profile] with a [state] into a [DriverContext]. Equivalent
  /// to the default constructor; expressed as a named factory so call-sites
  /// that already hold a [DriverProfile] read as
  /// `DriverContext.combineWith(profile: p, state: s)`.
  factory DriverContext.combineWith({
    required DriverProfile profile,
    required DriverState state,
  }) => DriverContext(profile: profile, state: state);

  /// Return a new [DriverContext] with the same [profile] and a different
  /// [state]. Useful when the live state changes mid-trip but the trait
  /// is invariant.
  DriverContext withState(DriverState newState) =>
      DriverContext(profile: profile, state: newState);

  @override
  List<Object?> get props => [profile, state];

  @override
  bool get stringify => true;
}
