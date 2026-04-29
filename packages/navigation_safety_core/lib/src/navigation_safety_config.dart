/// Threshold configuration for score and environmental safety posture.
library;

import 'package:equatable/equatable.dart';

import 'alert_density_throttle.dart';
import 'calibration/humidity_dependent_temperature.dart';
import 'calibration/precipitation_history_decay.dart';
import 'calibration/speed_dependent_visibility.dart';
import 'driver_context.dart';
import 'driver_profile.dart';
import 'driver_state.dart';
import 'navigation_safety_context.dart';

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

  /// Build a config tuned to a [DriverProfile] AND live driving conditions.
  ///
  /// Delegates to [NavigationSafetyConfig.forProfile] when [context] is
  /// `null`, preserving the per-profile baseline. When [context] is
  /// supplied, the relevant thresholds adjust as follows:
  ///
  /// - If `context.speedMps` is non-null, the warning visibility floor
  ///   raises to fit reaction time + braking distance for the current
  ///   speed, using a per-profile reaction-time default. The
  ///   per-profile baseline acts as a lower bound: context can only
  ///   warn earlier (longer visibility floor), never later.
  /// - If both `context.humidityRH` and `context.ambientTempCelsius`
  ///   are non-null, the warning temperature raises to cover
  ///   dew-point-driven black-ice risk: the effective road-surface
  ///   temperature (ambient minus dew-point depression) replaces
  ///   ambient when it crosses the warning threshold earlier.
  /// - If `context.timeSincePrecipitation` is non-null, the warning
  ///   visibility additionally raises by a residual-moisture margin
  ///   proportional to the surface-moisture fraction (longer
  ///   visibility floor while the road is still drying).
  ///
  /// The factory respects the per-profile baseline as a floor for
  /// every threshold: context can only add caution, not remove it.
  ///
  /// Citations for each formula are documented in the
  /// `lib/src/calibration/` module headers and in `KNOWN_LIMITATIONS.md`.
  factory NavigationSafetyConfig.forProfileWithContext(
    DriverProfile profile, {
    DrivingContext? context,
  }) {
    final base = NavigationSafetyConfig.forProfile(profile);
    if (context == null) return base;

    var infoVisibility = base.infoVisibilityMeters;
    var warningVisibility = base.warningVisibilityMeters;
    var criticalVisibility = base.criticalVisibilityMeters;
    var warningTemperature = base.warningTemperatureCelsius;

    // Speed-dependent visibility floor.
    if (context.speedMps != null) {
      final adjusted = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: base.warningVisibilityMeters.toDouble(),
        speedMps: context.speedMps!,
        driverReactionTimeSeconds: _reactionTimeSecondsFor(profile),
      );
      warningVisibility = adjusted.ceil();
    }

    // Precipitation-history surface-moisture margin.
    if (context.timeSincePrecipitation != null) {
      final ambient = context.ambientTempCelsius ?? 5.0;
      final fraction = computeSurfaceMoistureFraction(
        timeSincePrecipitation: context.timeSincePrecipitation!,
        ambientCelsius: ambient,
      );
      // Conservative add-on: residual-moisture margin scales with the
      // moisture fraction times the per-profile baseline, capped at
      // the baseline (i.e. up to 100% additional headroom while the
      // surface is still fully wet, decaying with moisture).
      final margin = (base.warningVisibilityMeters * fraction).round();
      final candidate = base.warningVisibilityMeters + margin;
      if (candidate > warningVisibility) {
        warningVisibility = candidate;
      }
    }

    // Humidity-dependent effective temperature for black-ice risk.
    if (context.humidityRH != null && context.ambientTempCelsius != null) {
      final effective = computeEffectiveTemperatureCelsius(
        ambientCelsius: context.ambientTempCelsius!,
        humidityRH: context.humidityRH!,
      );
      // If the effective temperature reaches the baseline warning
      // temperature earlier than ambient, raise the warning so the
      // alert fires on ambient-temperature inputs that would today
      // pass the baseline check.
      if (effective <= base.warningTemperatureCelsius.toDouble()) {
        final lift = (base.warningTemperatureCelsius -
                effective.floor())
            .clamp(0, 10);
        warningTemperature = base.warningTemperatureCelsius + lift;
      }
    }

    return NavigationSafetyConfig(
      safeScoreFloor: base.safeScoreFloor,
      infoScoreFloor: base.infoScoreFloor,
      warningScoreFloor: base.warningScoreFloor,
      infoTemperatureCelsius: base.infoTemperatureCelsius,
      warningTemperatureCelsius: warningTemperature,
      criticalTemperatureCelsius: base.criticalTemperatureCelsius,
      infoVisibilityMeters: infoVisibility,
      warningVisibilityMeters: warningVisibility,
      criticalVisibilityMeters: criticalVisibility,
      alertsPerMinuteCapOverride: base.alertsPerMinuteCapOverride,
    );
  }

  /// Per-profile reaction-time defaults in seconds. See
  /// `lib/src/calibration/speed_dependent_visibility.dart` module
  /// header for citations and UNVERIFIED flags.
  static double _reactionTimeSecondsFor(DriverProfile profile) {
    switch (profile) {
      case DriverProfile.ageingRural:
        return 2.5;
      case DriverProfile.noviceUrban:
        return 3.58;
      case DriverProfile.snowZoneExperienced:
        return 1.8;
      case DriverProfile.professional:
        return 1.5;
      case DriverProfile.agriculturalForestry:
        return 2.0;
      case DriverProfile.foreignTouristSnowZone:
        return 3.5;
    }
  }

  /// Build a config tuned to both the trait axis ([DriverProfile]) and
  /// the state axis ([DriverState]) of a [DriverContext]. Optionally
  /// composes with a live [DrivingContext] (the v0.5.0 environmental
  /// context); when both are passed, the trait baseline is computed
  /// first, then the state delta, then the environmental delta — each
  /// step conservative-only (warns earlier, never later).
  ///
  /// State deltas at this spike (0.6.0) are intentionally small and
  /// flagged UNVERIFIED in `KNOWN_LIMITATIONS.md` (state-axis section).
  /// The shape of the API is the load-bearing piece; the magnitudes
  /// are placeholders pending state-axis literature anchoring (Regan
  /// PMC4001671 + downstream).
  ///
  /// 0.5.0 callers that pass [DriverProfile] alone to
  /// [forProfile] / [forProfileWithContext] see no behaviour change;
  /// state-axis tuning is opt-in via this factory only.
  factory NavigationSafetyConfig.forDriverContext(
    DriverContext driverContext, {
    DrivingContext? environmentalContext,
  }) {
    // Step 1: trait + (optional) environmental baseline reuses the
    // proven 0.5.0 path so any future calibration update there is
    // automatically inherited here.
    final base = NavigationSafetyConfig.forProfileWithContext(
      driverContext.profile,
      context: environmentalContext,
    );

    // Step 2: apply state-axis delta. Conservative-only; never weaker
    // than `base`. Magnitudes UNVERIFIED — see KNOWN_LIMITATIONS.md
    // (state-axis section, 0.6.0).
    final delta = _stateDeltaFor(driverContext.state);
    final reactionPenaltySeconds = delta.reactionTimePenaltySeconds;
    final tempLiftCelsius = delta.warningTempLiftCelsius;
    final visibilityScale = delta.visibilityScale;

    var warningVisibility = base.warningVisibilityMeters;
    var infoVisibility = base.infoVisibilityMeters;
    var criticalVisibility = base.criticalVisibilityMeters;
    var warningTemperature = base.warningTemperatureCelsius;

    if (reactionPenaltySeconds > 0 && environmentalContext?.speedMps != null) {
      // When we have a live speed sample, translate the reaction-time
      // penalty into additional visibility headroom on the same kinematic
      // basis used by the 0.5.0 speed-dependent visibility calibration.
      final extraMeters = environmentalContext!.speedMps! * reactionPenaltySeconds;
      final candidate =
          base.warningVisibilityMeters + extraMeters.ceil();
      if (candidate > warningVisibility) {
        warningVisibility = candidate;
      }
    }

    if (visibilityScale > 1.0) {
      // Speed-independent visibility scale-up (e.g. impairedVisibility
      // state). Applies to all three visibility tiers proportionally
      // so tier ordering is preserved.
      warningVisibility = (warningVisibility * visibilityScale).ceil();
      infoVisibility = (infoVisibility * visibilityScale).ceil();
      criticalVisibility = (criticalVisibility * visibilityScale).ceil();
    }

    if (tempLiftCelsius > 0) {
      warningTemperature = base.warningTemperatureCelsius + tempLiftCelsius;
    }

    return NavigationSafetyConfig(
      safeScoreFloor: base.safeScoreFloor,
      infoScoreFloor: base.infoScoreFloor,
      warningScoreFloor: base.warningScoreFloor,
      infoTemperatureCelsius: base.infoTemperatureCelsius,
      warningTemperatureCelsius: warningTemperature,
      criticalTemperatureCelsius: base.criticalTemperatureCelsius,
      infoVisibilityMeters: infoVisibility,
      warningVisibilityMeters: warningVisibility,
      criticalVisibilityMeters: criticalVisibility,
      alertsPerMinuteCapOverride: base.alertsPerMinuteCapOverride,
    );
  }

  /// Per-state delta. Magnitudes UNVERIFIED at 0.6.0 spike — see
  /// KNOWN_LIMITATIONS.md (state-axis section).
  static _StateDelta _stateDeltaFor(DriverState state) {
    switch (state) {
      case DriverState.alert:
        return const _StateDelta();
      case DriverState.fatigued:
        return const _StateDelta(
          reactionTimePenaltySeconds: 0.5,
          warningTempLiftCelsius: 1,
        );
      case DriverState.distracted:
        return const _StateDelta(
          reactionTimePenaltySeconds: 1.0,
        );
      case DriverState.impairedVisibility:
        return const _StateDelta(
          visibilityScale: 1.25,
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

/// Internal-only descriptor of the per-state delta applied by
/// `NavigationSafetyConfig.forDriverContext`. Magnitudes UNVERIFIED at
/// 0.6.0 spike — see `KNOWN_LIMITATIONS.md` (state-axis section).
class _StateDelta {
  final double reactionTimePenaltySeconds;
  final int warningTempLiftCelsius;
  final double visibilityScale;

  const _StateDelta({
    this.reactionTimePenaltySeconds = 0.0,
    this.warningTempLiftCelsius = 0,
    this.visibilityScale = 1.0,
  });
}
