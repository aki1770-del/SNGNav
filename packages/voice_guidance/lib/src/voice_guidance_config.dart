/// Runtime config for voice guidance behavior.
library;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety/navigation_safety.dart' show DriverProfile;

import 'budget_aware_pace_profile.dart';

/// Per-profile speaking-rate multipliers. The values are recorded
/// decisions; no source cited gives them. They follow the direction of
/// the package's per-profile threshold differentiation: an older rural
/// driver and a foreign-tourist driver in an unfamiliar snow-zone are
/// given a slower delivery, meant to help them act on the same line in
/// the same window as the experienced snow-zone driver (effect not
/// measured). Cooper et al. 2020 (PMC7283540) found that "Older drivers
/// took longer to complete tasks, were slower to react to stimuli, and
/// reported higher task demand when interacting with IVIS"; that study
/// did not vary or measure speaking rate.
///
/// Multipliers applied to the engine's base rate of `1.0`:
///
/// | profile                  | multiplier |
/// |--------------------------|-----------:|
/// | `snowZoneExperienced`    |       1.00 |
/// | `professional`           |       1.00 |
/// | `agriculturalForestry`   |       1.00 |
/// | `noviceUrban`            |       0.85 |
/// | `ageingRural`            |       0.70 |
/// | `foreignTouristSnowZone` |       0.70 |
const Map<DriverProfile, double> kSpeakingRateMultiplierByProfile =
    <DriverProfile, double>{
      DriverProfile.snowZoneExperienced: 1.0,
      DriverProfile.professional: 1.0,
      DriverProfile.agriculturalForestry: 1.0,
      DriverProfile.noviceUrban: 0.85,
      DriverProfile.ageingRural: 0.70,
      DriverProfile.foreignTouristSnowZone: 0.70,
    };

class VoiceGuidanceConfig extends Equatable {
  const VoiceGuidanceConfig({
    this.enabled = true,
    this.languageTag = 'ja-JP',
    this.volume = 1.0,
    this.speakingRate = 1.0,
    this.maneuverLeadDistanceMeters = 120.0,
    this.minAnnouncementIntervalSeconds = 3,
    this.budgetAwarePace,
  }) : assert(volume >= 0.0 && volume <= 1.0),
       assert(speakingRate > 0.0 && speakingRate <= 2.0),
       assert(maneuverLeadDistanceMeters >= 0),
       assert(minAnnouncementIntervalSeconds >= 0);

  final bool enabled;
  final String languageTag;
  final double volume;

  /// Normalized speaking-rate. `1.0` is the engine's base rate; values
  /// below `1.0` are slower and above are faster. Engine
  /// implementations clamp to per-engine ranges; the config validates
  /// only the broad sanity range `(0.0, 2.0]`.
  final double speakingRate;

  final double maneuverLeadDistanceMeters;
  final int minAnnouncementIntervalSeconds;

  /// Optional glance-budget-aware pace adjustment profile (0.6.0).
  ///
  /// When non-null, the bloc subscribes to a `GlanceBudgetTracker`
  /// (supplied by the integrator at bloc construction) and dynamically
  /// modulates the effective TTS speaking-rate as the off-road glance
  /// budget is consumed. Disabled by default to preserve back-compat
  /// with 0.5.0 consumers; opt-in via construction.
  ///
  /// Caution-add-only invariant (load-bearing): pace ≤ 1.0× baseline;
  /// the dynamic adjustment can only SLOW speech, never speed it up.
  final BudgetAwarePaceProfile? budgetAwarePace;

  /// Returns the per-profile speaking-rate computed from the engine's
  /// base rate of `1.0` multiplied by the per-profile multiplier in
  /// [kSpeakingRateMultiplierByProfile]. Profiles without a published
  /// multiplier fall back to `1.0` (defensive default).
  static double speakingRateForProfile(DriverProfile profile) {
    return kSpeakingRateMultiplierByProfile[profile] ?? 1.0;
  }

  /// Returns a copy of this config with [speakingRate] set to the
  /// per-profile multiplier for [profile]. Other fields are preserved.
  VoiceGuidanceConfig forProfile(DriverProfile profile) {
    return copyWith(speakingRate: speakingRateForProfile(profile));
  }

  VoiceGuidanceConfig copyWith({
    bool? enabled,
    String? languageTag,
    double? volume,
    double? speakingRate,
    double? maneuverLeadDistanceMeters,
    int? minAnnouncementIntervalSeconds,
    BudgetAwarePaceProfile? budgetAwarePace,
  }) {
    return VoiceGuidanceConfig(
      enabled: enabled ?? this.enabled,
      languageTag: languageTag ?? this.languageTag,
      volume: volume ?? this.volume,
      speakingRate: speakingRate ?? this.speakingRate,
      maneuverLeadDistanceMeters:
          maneuverLeadDistanceMeters ?? this.maneuverLeadDistanceMeters,
      minAnnouncementIntervalSeconds:
          minAnnouncementIntervalSeconds ?? this.minAnnouncementIntervalSeconds,
      budgetAwarePace: budgetAwarePace ?? this.budgetAwarePace,
    );
  }

  @override
  List<Object?> get props => [
    enabled,
    languageTag,
    volume,
    speakingRate,
    maneuverLeadDistanceMeters,
    minAnnouncementIntervalSeconds,
    budgetAwarePace,
  ];
}
