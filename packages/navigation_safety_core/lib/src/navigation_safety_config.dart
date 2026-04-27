/// Threshold configuration for score and environmental safety posture.
library;

import 'package:equatable/equatable.dart';

import 'alert_density_throttle.dart';
import 'driver_profile.dart';

class NavigationSafetyConfig extends Equatable {
  final double safeScoreFloor;
  final double infoScoreFloor;
  final double warningScoreFloor;

  final int infoTemperatureCelsius;
  final int warningTemperatureCelsius;
  final int criticalTemperatureCelsius;

  final int infoVisibilityMeters;
  final int warningVisibilityMeters;
  final int criticalVisibilityMeters;

  /// Optional override for the per-profile alerts/min cap used by
  /// [AlertDensityThrottle]. When `null` (the default), the throttle
  /// uses the literature-anchored per-profile default from
  /// [AlertDensityThrottle.defaultCapFor]. Integrating apps with their
  /// own measured per-population data should set this.
  ///
  /// Resolved via [effectiveAlertsPerMinuteCap] — pass the active
  /// [DriverProfile] and receive the cap that should be applied
  /// (override if set, profile default otherwise).
  final double? alertsPerMinuteCapOverride;

  /// Build a config with thresholds tuned to a [DriverProfile].
  ///
  /// See `driver_profile.dart` for profile semantics. Use this factory
  /// when the consuming app knows the driver-class; falls back to
  /// [DriverProfile.snowZoneExperienced] (the historical defaults) for
  /// any profile whose tuning isn't more conservative or more permissive.
  ///
  /// Returns the same shape as the default constructor — callers can
  /// further override any threshold via `copyWith`-style construction
  /// once they have a profile-derived baseline.
  factory NavigationSafetyConfig.forProfile(DriverProfile profile) {
    switch (profile) {
      case DriverProfile.ageingRural:
        // 0.3.0 calibration corrections per published literature.
        // - infoTemperatureCelsius: 0.2.0 had 5°C; combined with
        //   infoVisibilityMeters 1500m this fired alert-fatigue on
        //   most autumn evenings in Hokkaido/Tohoku (V14 silent
        //   safety failure per arxiv 2410.06388 + AAA-FTS). Lowered
        //   to 4°C to preserve information-tier signal without
        //   firing on routine cold autumn evenings.
        // - warningTemperatureCelsius: 0.2.0 had 1°C; black ice
        //   forms at road-surface ≤0°C even when ambient air is
        //   several degrees warmer (well-documented). 1°C left no
        //   margin above formation envelope. Raised to 2°C.
        return NavigationSafetyConfig(
          safeScoreFloor: 0.85,
          infoScoreFloor: 0.55,
          warningScoreFloor: 0.35,
          infoTemperatureCelsius: 4,
          warningTemperatureCelsius: 2,
          criticalTemperatureCelsius: -3,
          infoVisibilityMeters: 1500,
          warningVisibilityMeters: 300,
          criticalVisibilityMeters: 80,
        );
      case DriverProfile.snowZoneExperienced:
        // Standard defaults. The loom trusts the experienced
        // snow-zone driver's interpretation of standard warnings.
        return NavigationSafetyConfig();
      case DriverProfile.noviceUrban:
        // 0.3.0 calibration correction per published literature.
        // - warningVisibilityMeters: 0.2.0 had 250m (+50m over
        //   standard). Novice hazard-perception RT is 3.58s vs 1.32s
        //   experienced (PubMed 16313881). At 60 km/h that's ~37m
        //   additional reaction-distance from RT alone — +50m left
        //   no braking margin. Raised to 320m to give RT-margin +
        //   braking margin per published novice-fog crash-rate
        //   elevation (Konstantopoulos PubMed 22664714).
        return NavigationSafetyConfig(
          safeScoreFloor: 0.85,
          infoScoreFloor: 0.55,
          warningScoreFloor: 0.32,
          infoTemperatureCelsius: 4,
          warningTemperatureCelsius: 0,
          criticalTemperatureCelsius: -5,
          infoVisibilityMeters: 1500,
          warningVisibilityMeters: 320,
          criticalVisibilityMeters: 60,
        );
      case DriverProfile.professional:
        // Trained drivers — thresholds near standard; minimum-distraction
        // optimization happens in the Flutter UX layer (voice
        // brevity, modal-alert duration), not in the core thresholds.
        return NavigationSafetyConfig();
      case DriverProfile.agriculturalForestry:
        // Off-road semantics belong to a future revision (don't alert
        // "off route" on forest tracks). Today: same threshold defaults
        // as snowZoneExperienced; the off-route semantic extension is
        // a downstream package's job.
        return NavigationSafetyConfig();
      case DriverProfile.foreignTouristSnowZone:
        // 0.3.0 — most-conservative defaults across every dimension.
        // Foreign tourists in unfamiliar snow-zones have novice-equivalent
        // unfamiliarity with local conditions + likely non-winterised
        // rental vehicle + language-localization gaps in road signage.
        // The loom shifts caution further than any other profile;
        // alerts arrive earliest on weather + visibility; score floors
        // highest. Hokkaido winter accidents involve foreign self-driving
        // tourists at meaningful rates — this profile closes a V100 gap
        // the previous taxonomy mis-mapped to either snowZoneExperienced
        // (catastrophically wrong) or noviceUrban (location-wrong).
        return NavigationSafetyConfig(
          safeScoreFloor: 0.90,
          infoScoreFloor: 0.60,
          warningScoreFloor: 0.40,
          infoTemperatureCelsius: 5,
          warningTemperatureCelsius: 2,
          criticalTemperatureCelsius: -2,
          infoVisibilityMeters: 1800,
          warningVisibilityMeters: 400,
          criticalVisibilityMeters: 100,
        );
    }
  }

  NavigationSafetyConfig({
    this.safeScoreFloor = 0.80,
    this.infoScoreFloor = 0.50,
    this.warningScoreFloor = 0.30,
    this.infoTemperatureCelsius = 3,
    this.warningTemperatureCelsius = 0,
    this.criticalTemperatureCelsius = -5,
    this.infoVisibilityMeters = 1000,
    this.warningVisibilityMeters = 200,
    this.criticalVisibilityMeters = 50,
    this.alertsPerMinuteCapOverride,
  }) {
    if (safeScoreFloor < 0 || safeScoreFloor > 1) {
      throw RangeError.range(safeScoreFloor, 0, 1, 'safeScoreFloor');
    }
    if (infoScoreFloor < 0 || infoScoreFloor > 1) {
      throw RangeError.range(infoScoreFloor, 0, 1, 'infoScoreFloor');
    }
    if (warningScoreFloor < 0 || warningScoreFloor > 1) {
      throw RangeError.range(warningScoreFloor, 0, 1, 'warningScoreFloor');
    }
    if (safeScoreFloor < infoScoreFloor) {
      throw ArgumentError(
        'safeScoreFloor ($safeScoreFloor) must be >= infoScoreFloor ($infoScoreFloor)',
      );
    }
    if (infoScoreFloor < warningScoreFloor) {
      throw ArgumentError(
        'infoScoreFloor ($infoScoreFloor) must be >= warningScoreFloor ($warningScoreFloor)',
      );
    }
  }

  /// Resolve the alerts/min cap for [profile]: the override if set,
  /// the literature-anchored per-profile default otherwise.
  ///
  /// Use this when constructing an [AlertDensityThrottle] from a
  /// config that may carry an integrating-app override.
  double effectiveAlertsPerMinuteCap(DriverProfile profile) =>
      alertsPerMinuteCapOverride ?? AlertDensityThrottle.defaultCapFor(profile);

  @override
  List<Object?> get props => [
        safeScoreFloor,
        infoScoreFloor,
        warningScoreFloor,
        infoTemperatureCelsius,
        warningTemperatureCelsius,
        criticalTemperatureCelsius,
        infoVisibilityMeters,
        warningVisibilityMeters,
        criticalVisibilityMeters,
        alertsPerMinuteCapOverride,
      ];
}
