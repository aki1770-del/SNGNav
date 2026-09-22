/// Threshold configuration for score and environmental safety posture.
library;

import 'package:equatable/equatable.dart';
import 'package:navigation_safety_calibration/navigation_safety_calibration.dart';

import 'alert_density_throttle.dart';
import 'circadian_phase.dart';
import 'confidence_provider.dart';
import 'driver_context.dart';
import 'driver_profile.dart';
import 'driver_state.dart';
import 'navigation_safety_context.dart';
import 'session_state_provider.dart';
import 'vehicle_threshold_overrides.dart';

/// Glare-ice over dry-pavement braking deceleration, `1.5 / 5.5 m/s^2`.
///
/// Both magnitudes are published in
/// `navigation_safety_calibration/lib/src/speed_dependent_visibility.dart`.
/// See [NavigationSafetyConfig.criticalGripScoreFloor] for the derivation and
/// for the honest bound on those magnitudes.
const double _glareIceGripRatio = 1.5 / 5.5;

class NavigationSafetyConfig extends Equatable {
  final double safeScoreFloor;
  final double infoScoreFloor;
  final double warningScoreFloor;

  final int infoTemperatureCelsius;

  /// A consumer warns when the ambient reading is at or below this value
  /// (`<=`). Inside the radiative-frost classification,
  /// [NavigationSafetyConfig.forProfileWithContext] raises it to at least
  /// the ambient reading rounded up, so where it equals a whole-degree
  /// ambient reading a strict `<` would not warn.
  final int warningTemperatureCelsius;
  final int criticalTemperatureCelsius;

  final int infoVisibilityMeters;
  final int warningVisibilityMeters;
  final int criticalVisibilityMeters;

  /// Grip score BELOW which grip ALONE is critical, whatever the composite
  /// score says.
  ///
  /// The comparison is STRICT (`gripScore < criticalGripScoreFloor`),
  /// matching the three score floors: a grip score exactly EQUAL to this
  /// value is not critical on grip alone.
  ///
  /// ## Why a per-axis floor exists at all
  ///
  /// **CORRECTED IN 0.11.11.** Through 0.11.10 this paragraph said
  /// "`SafetyScore.overall` is a MEAN of the axes" and that `critical`
  /// "was UNREACHABLE at any grip value". **Both were false.** `overall` is
  /// a THIRD caller-supplied input that `SafetyScore` only clamps; and on
  /// 0.11.9 an `overall` below [warningScoreFloor] (default 0.30) returned
  /// `critical` at ANY grip, including 1.0. Both statements hold only on
  /// the 50/50 slice. The true statement follows.
  ///
  /// `SafetyScore.overall` is whatever the caller passes. WHEN it is the
  /// 50/50 mean of the axes — which is what `driving_conditions` supplies,
  /// from its pure-Dart and its native engine alike — a mean answers "how
  /// good are conditions on aggregate". Severity asks a different question:
  /// "how bad is the worst thing here". Those come apart exactly when one
  /// axis is catastrophic and the other is fine — black ice under a clear
  /// sky. On that slice, with visibility at 1.0 the mean is >= 0.5, while
  /// every shipped [warningScoreFloor] is 0.30-0.40, so `critical` was
  /// unreachable at any grip value. A grip score of zero scored `info` on
  /// three of the six profile baselines and on the default config, and
  /// `warning` on the other three — an advisory grade either way. The
  /// mean was not mis-tuned; it was the wrong shape for the question.
  ///
  /// The fix is not a lower floor — lowering it to make one number cross
  /// would promote every other road with it. [overall] keeps its stated
  /// meaning and its fixed weights. The axes are read SEPARATELY and the
  /// worst verdict wins.
  ///
  /// ## Where the number comes from
  ///
  /// `1.5 / 5.5` = 0.2727..., the ratio of glare-ice to dry-pavement
  /// braking deceleration, both published in this workspace's
  /// `navigation_safety_calibration/lib/src/speed_dependent_visibility.dart`
  /// ("5.5 m/s^2, a typical passenger-car dry-pavement value ... ~3.0 m/s^2
  /// for compacted snow; ~1.5 m/s^2 for glare ice"). Read as a fraction of
  /// available dry-pavement grip — which is what a `[0,1]` grip score means
  /// — a road at or below this ratio brakes no better than glare ice.
  /// Compacted snow sits at 3.0/5.5 = 0.545 and is deliberately well clear
  /// of this floor: this is the glare-ice line, not the winter-road line.
  ///
  /// **Honest bound**: the 1.5 and 5.5 magnitudes are that package's stated
  /// typical values, not measurements this unit has taken in the field. The
  /// SHAPE of the rule does not depend on them; the exact number does.
  ///
  /// ## What this costs
  ///
  /// **It can never LOWER a severity.** Taking the worse of two verdicts is
  /// monotone, so no alert that fires today can be silenced by this rule.
  /// That holds for every `(overall, gripScore)` pair, with no condition
  /// attached; measured downward movement is ZERO on both surfaces below.
  ///
  /// **Whether it can raise SILENCE to an alert depends on the surface, and
  /// the honest answer is yes — off one particular plane.**
  ///
  /// - On the plane where `overall` is the MEAN of the axes
  ///   (`0.5*grip + 0.5*visibility`, which is what `driving_conditions`
  ///   computes): over a 101x101 grid at default floors, every promotion is
  ///   out of a band that was ALREADY alerting, and **zero** cells are
  ///   promoted out of `none`. This is what
  ///   `test/grip_axis_critical_test.dart` asserts, and it is the only
  ///   surface it asserts over.
  /// - **Off that plane, it is not zero.** [SafetyScore] takes `overall` as
  ///   a value the CALLER supplies; nothing requires it to be the mean of
  ///   the axes it is carried with. Over the independent
  ///   `(overall, gripScore)` grid at default floors — 10,201 cells —
  ///   **588 cells move from `none` to `critical`.** A caller passing
  ///   `overall: 0.9` with `gripScore: 0.0` is telling this package the
  ///   road is nearly ideal and has no grip; the rule answers the second
  ///   half, and that is the intended behaviour, not a defect. It is stated
  ///   here because "it cannot create an alert where there is silence" is
  ///   **false on that surface**, and an integrator computing `overall`
  ///   their own way is on it.
  ///
  /// A grid is a statement about the geometry of the rule, NOT a
  /// false-positive rate: this unit has no measured distribution of real
  /// road conditions, so the on-road frequency of this promotion is
  /// UNVERIFIED.
  final double criticalGripScoreFloor;

  /// Optional override for the per-profile alerts/min cap used by
  /// [AlertDensityThrottle]. When `null` (the default), the throttle
  /// uses the per-profile default (a recorded decision) from
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
        // 0.3.0 calibration corrections (recorded decisions; see
        // KNOWN_LIMITATIONS.md "Threshold magnitudes").
        // - infoTemperatureCelsius: 0.2.0 had 5°C; combined with
        //   infoVisibilityMeters 1500m this fired on most autumn
        //   evenings in Hokkaido/Tohoku (an alert-fatigue risk; arxiv
        //   2410.06388 reports alert fatigue from repeated false alarms
        //   in a simulator study). Lowered to 4°C to preserve
        //   information-tier signal without firing on routine cold
        //   autumn evenings.
        // - warningTemperatureCelsius: 0.2.0 had 1°C; black ice can
        //   form on a road surface below 0°C while the air is several
        //   degrees warmer, if the air warms suddenly after a prolonged
        //   cold spell (Wikipedia, "Black ice"). 1°C left no margin
        //   above formation envelope. Raised to 2°C.
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
        // 0.3.0 calibration correction (a recorded decision).
        // - warningVisibilityMeters: 0.2.0 had 250m (+50m over
        //   standard). Raised to 320m to give novice drivers more
        //   reaction and braking margin (a recorded decision). Mueller
        //   and Trick 2012 (PubMed 22664714) found in a driving
        //   simulator that novice drivers had higher hazard response
        //   times and were the only drivers to have collisions.
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
        // tourists at meaningful rates — this profile closes a coverage
        // gap the previous taxonomy mis-mapped to either snowZoneExperienced
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
  ///   rises to the reaction distance (a per-profile reaction-time
  ///   default times the speed) plus the braking distance, when that is
  ///   longer. The braking deceleration is
  ///   `context.brakingDecelerationMps2` when supplied (checked first:
  ///   `NaN`, infinite, zero and negative values are unreadable and are
  ///   used as 0.4905, whatever the readings; then values above
  ///   5.5 m/s² are used as 5.5), and otherwise 5.5 m/s², a
  ///   dry-pavement figure. Where
  ///   `context.ambientTempCelsius` and `context.humidityRH` classify
  ///   radiative-frost black ice (`isRadiativeFrostBlackIce`), the lower
  ///   of that value and 0.981 m/s² applies, so a supplied value never
  ///   gives a shorter floor than leaving it out. 0.981 m/s²
  ///   (0.10 × 9.81) is an ice figure: the lower edge of the ice ranges
  ///   in TRB Special Report 115 and 土木技術資料 52-5; wet or
  ///   near-melting ice can be lower, so an integrator with a lower
  ///   reading for the surface should supply it. Both figures are
  ///   recorded decisions. The per-profile baseline acts as a lower
  ///   bound: context can only warn earlier (longer visibility floor),
  ///   never later.
  /// - If both `context.humidityRH` and `context.ambientTempCelsius`
  ///   are non-null and the effective road-surface temperature
  ///   (ambient minus dew-point depression, i.e. the dew point) is at
  ///   or below the per-profile warning temperature, the warning
  ///   temperature rises by `baseline - floor(effective)`, at most
  ///   10 °C, to cover dew-point-driven black-ice risk. Where the same
  ///   readings classify radiative-frost black ice
  ///   (`isRadiativeFrostBlackIce`: ambient at or below 3.0 °C and the
  ///   effective temperature at or below 0 °C), the warning temperature
  ///   is also raised to at least the ambient reading rounded up, so an
  ///   ambient comparison (`<=`) warns. At 3.0 °C and 70% RH the
  ///   effective temperature is -1.94 °C; for a profile whose baseline
  ///   warning temperature is 0 °C the lift gives 2 °C and the
  ///   classification 3 °C; for `ageingRural` and `foreignTouristSnowZone`,
  ///   whose baseline is 2 °C, the lift alone gives 6 °C. Above 3.0 °C
  ///   ambient the comparison can still stay above the raised warning
  ///   temperature while the effective temperature is at or below the
  ///   baseline; the calibration does not classify those readings as
  ///   black ice.
  /// - If `context.timeSincePrecipitation` is non-null, the warning
  ///   visibility floor is the longer of the floor so far (the
  ///   per-profile baseline, or the speed floor above) and the
  ///   per-profile baseline plus a residual-moisture margin, the
  ///   baseline times the surface-moisture fraction rounded to a whole
  ///   metre (longer visibility floor while the road is still drying).
  ///   The margin is not added to the speed floor: for
  ///   `snowZoneExperienced` at 100 km/h on black-ice readings the floor
  ///   is 444 m with precipitation 0, 90 or 360 minutes ago, as without
  ///   it, and without a speed it is 400, 300 and 213 m. This margin
  ///   does NOT require `context.ambientTempCelsius`, and when ambient
  ///   is absent no temperature is substituted for it: the margin
  ///   applies only while the surface-moisture calibration is shown to
  ///   ignore ambient, and otherwise no margin applies.
  ///   See [_residualMoistureFractionOrNull].
  ///
  /// Context respects the per-profile baseline as a floor for every
  /// threshold: it can only add caution, not remove it. A vehicle-class
  /// registry can take a threshold below that floor only when its class
  /// replaces `applyOverrideForToken`, as the next paragraph describes.
  ///
  /// **Vehicle-class overrides (0.9.0)**: when [vehicleOverrides] is
  /// non-null AND `context.vehicleClassToken` is non-null AND the
  /// token matches a registered key, the registered transform applies
  /// AFTER the per-profile baseline AND AFTER the live-context
  /// adjustments. The transform is bound by the caution-add-only
  /// invariant — it may make warning thresholds fire EARLIER, never
  /// later, than the post-context baseline. Every other threshold field
  /// MUST be preserved: the score-floor tiers, the critical thresholds,
  /// the info thresholds and `alertsPerMinuteCapOverride`
  /// (severity-not-profile invariant). A lowered warning threshold, or
  /// any change to one of those other fields, is refused at
  /// REGISTRATION by [VehicleThresholdOverrides.validated], which throws
  /// [ArgumentError] there. On this drive path the factory calls the
  /// registry's own `applyOverrideForToken`. The one
  /// [VehicleThresholdOverrides] defines checks the same fields again
  /// and NEVER throws: each refused field goes back to its un-overridden
  /// value, every legal part of the override is kept, and each refusal
  /// is reported. So a registry built with a [VehicleThresholdOverrides]
  /// constructor cannot make this factory throw -- a caller deriving a
  /// config per vehicle-bus frame inside an `async*` body keeps its
  /// stream. A registry whose class implements
  /// [VehicleThresholdOverrides], or extends it and replaces
  /// [VehicleThresholdOverrides.applyOverrideForToken], has its own
  /// method called here, and this factory adds no check of its own.
  /// Unless that method returns what the one [VehicleThresholdOverrides]
  /// defines returns, what it returns is applied unchecked and
  /// unreported, in every build mode, even a warning threshold lowered
  /// below the per-profile baseline. What that method throws leaves this
  /// factory and ends such a stream. An integrator that supplies such a
  /// registry owns both checks.
  ///
  /// The sources cited for each formula, and which of its values are
  /// recorded decisions, are stated in the module headers
  /// under `lib/src/` in the `navigation_safety_calibration` package,
  /// which has supplied these formulas since this package's 0.11.0,
  /// and in `KNOWN_LIMITATIONS.md`.
  factory NavigationSafetyConfig.forProfileWithContext(
    DriverProfile profile, {
    DrivingContext? context,
    VehicleThresholdOverrides? vehicleOverrides,
  }) {
    final base = NavigationSafetyConfig.forProfile(profile);
    if (context == null) {
      // No live context; vehicle-class overrides may still apply if the
      // caller wired a registry but no DrivingContext. Without a
      // context there is no token, so the override is a no-op; return
      // the baseline as before.
      return base;
    }

    var infoVisibility = base.infoVisibilityMeters;
    var warningVisibility = base.warningVisibilityMeters;
    var criticalVisibility = base.criticalVisibilityMeters;
    var warningTemperature = base.warningTemperatureCelsius;

    final frostClassified = _isFrostClassified(context);

    // Speed-dependent visibility floor.
    if (context.speedMps != null) {
      final adjusted = computeSpeedAdjustedVisibilityMeters(
        profileBaseMeters: base.warningVisibilityMeters.toDouble(),
        speedMps: context.speedMps!,
        driverReactionTimeSeconds: _reactionTimeSecondsFor(profile),
        brakingDecelerationMps2: _brakingDecelerationFor(
          context.brakingDecelerationMps2,
          frostClassified: frostClassified,
        ),
      );
      warningVisibility = adjusted.ceil();
    }

    // Precipitation-history surface-moisture margin.
    if (context.timeSincePrecipitation != null) {
      final fraction = _residualMoistureFractionOrNull(
        timeSincePrecipitation: context.timeSincePrecipitation!,
        measuredAmbientCelsius: context.ambientTempCelsius,
      );
      // `null` means the fraction could not be obtained without a
      // measurement this context does not carry. The margin is an
      // add-on; withholding it leaves the floor computed above: the
      // per-profile baseline, or the speed floor when a speed is given.
      // No temperature is invented to keep the add-on alive.
      if (fraction != null) {
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
    }

    // Humidity-dependent effective temperature for black-ice risk.
    if (context.humidityRH != null && context.ambientTempCelsius != null) {
      final effective = computeEffectiveTemperatureCelsius(
        ambientCelsius: context.ambientTempCelsius!,
        humidityRH: context.humidityRH!,
      );
      // If the effective temperature is at or below the baseline
      // warning temperature, raise the warning by the whole degrees it
      // sits below the baseline, at most 10. That moves the ambient
      // comparison by the lift only. On readings classified as
      // radiative-frost black ice the step below also raises the warning
      // temperature to at least the ambient reading rounded up, so the
      // ambient comparison warns (1.5 C at 84% RH, 0 C baseline:
      // effective -0.91 C, the lift gives 1 C, the raise 2 C). Outside
      // that classification, as above 3.0 C ambient, an ambient reading
      // more than the lift above the baseline still passes (4.0 C at 70%
      // RH, 0 C baseline: effective -0.98 C, warning temperature 1 C).
      if (effective <= base.warningTemperatureCelsius.toDouble()) {
        // .toInt() portability hardening: num.clamp is declared to return
        // `num`; current SDKs special-case int.clamp(int, int) as int, but
        // the explicit conversion keeps the line valid on SDKs without that
        // special-casing. (Verified 2026-07-04: hosted 0.11.0 compiles fine
        // in a Flutter consumer — this is hardening, not a shipped-bug fix.)
        final lift = (base.warningTemperatureCelsius - effective.floor())
            .clamp(0, 10)
            .toInt();
        warningTemperature = base.warningTemperatureCelsius + lift;
      }
      // Inside the radiative-frost classification the consumer's ambient
      // comparison must warn: raise to the ambient reading rounded up.
      // The classification bounds ambient at 3.0 C, so this stays within
      // the lift's 10 C cap for every per-profile baseline.
      if (frostClassified) {
        final ambientCeil = context.ambientTempCelsius!.ceil();
        if (ambientCeil > warningTemperature) {
          warningTemperature = ambientCeil;
        }
      }
    }

    final postContext = NavigationSafetyConfig(
      safeScoreFloor: base.safeScoreFloor,
      infoScoreFloor: base.infoScoreFloor,
      warningScoreFloor: base.warningScoreFloor,
      infoTemperatureCelsius: base.infoTemperatureCelsius,
      warningTemperatureCelsius: warningTemperature,
      criticalTemperatureCelsius: base.criticalTemperatureCelsius,
      infoVisibilityMeters: infoVisibility,
      warningVisibilityMeters: warningVisibility,
      criticalVisibilityMeters: criticalVisibility,
      criticalGripScoreFloor: base.criticalGripScoreFloor,
      alertsPerMinuteCapOverride: base.alertsPerMinuteCapOverride,
    );

    // Vehicle-class override (0.9.0). Applied AFTER per-profile baseline
    // AND AFTER live-context adjustment. Caution-add-only +
    // severity-not-profile violations (a lowered warning threshold, or a
    // changed score floor, critical threshold, info threshold or cap)
    // are refused at REGISTRATION by VehicleThresholdOverrides.validated
    // (which throws there) and re-checked here by the
    // applyOverrideForToken that VehicleThresholdOverrides defines,
    // which does NOT throw: it puts each violating field back to its
    // un-overridden value, keeps the legal rest of the override, and
    // reports each rejection. This call site can be inside a per-frame
    // loop, and it adds no check and catches no throw: a
    // registry class that implements VehicleThresholdOverrides, or
    // extends it and replaces applyOverrideForToken, runs its own method
    // here, and what that method returns or throws reaches the caller.
    if (vehicleOverrides == null) return postContext;
    return vehicleOverrides.applyOverrideForToken(
      context.vehicleClassToken,
      postContext,
    );
  }

  /// Ambient temperatures spanning the range a road vehicle meets,
  /// used ONLY to ask the surface-moisture calibration whether its
  /// answer depends on ambient at all.
  ///
  /// These are probes, never stand-ins for a reading. Nothing computed
  /// from an individual entry reaches a threshold: a value is used only
  /// when every entry produces the same one.
  static const List<double> _ambientProbesCelsius = <double>[-40.0, 0.0, 40.0];

  /// The residual surface-moisture fraction behind the
  /// precipitation-history visibility margin, or `null` when it cannot
  /// be obtained without an ambient temperature nobody measured.
  ///
  /// [measuredAmbientCelsius] is `null` when ambient was not measured.
  /// Through 0.11.3 this branch answered that absence with `5.0` — a
  /// plausible mild afternoon, indistinguishable inside the calculation
  /// from a reading actually taken, and the only place in this factory
  /// where an absent field was filled in rather than skipped. The
  /// black-ice branch seventeen lines below refused to proceed at all
  /// without the same field.
  ///
  /// No temperature is substituted now. `computeSurfaceMoistureFraction`
  /// declares `ambientCelsius` required, so this package still has to
  /// pass doubles; it passes [_ambientProbesCelsius] and uses the result
  /// only if every probe agrees. Agreement means the answer does not
  /// depend on the missing measurement, so the absence costs the driver
  /// nothing. Disagreement means ambient has become load-bearing — this
  /// context cannot answer, and `null` withholds the add-on rather than
  /// invent an input for it.
  ///
  /// The calibration ignores `ambientCelsius` today (its own docs say it
  /// is accepted "for forward-compatible API shape"), so every probe
  /// agrees and the returned fraction is bit-identical to 0.11.3's. What
  /// changes is only what happens if that stops being true — which its
  /// docs say may happen "without an API break", behind the caret range
  /// this package depends through.
  ///
  /// **Limits.** Agreement across [_ambientProbesCelsius] is
  /// evidence of independence, not proof of it: a calibration that
  /// modulated the half-life while returning identical values at exactly
  /// these three temperatures would pass. And the durable fix is not
  /// here — it is a calibration signature that can express "not
  /// measured" (widening `ambientCelsius` to `double?` is
  /// source-compatible for every existing caller). That is a change in a
  /// package this one does not own.
  static double? _residualMoistureFractionOrNull({
    required Duration timeSincePrecipitation,
    required double? measuredAmbientCelsius,
  }) {
    if (measuredAmbientCelsius != null) {
      return computeSurfaceMoistureFraction(
        timeSincePrecipitation: timeSincePrecipitation,
        ambientCelsius: measuredAmbientCelsius,
      );
    }
    double? agreed;
    for (final probeCelsius in _ambientProbesCelsius) {
      final probed = computeSurfaceMoistureFraction(
        timeSincePrecipitation: timeSincePrecipitation,
        ambientCelsius: probeCelsius,
      );
      if (agreed == null) {
        agreed = probed;
      } else if (probed != agreed) {
        return null;
      }
    }
    return agreed;
  }

  /// Dry-pavement braking deceleration, m/s². A recorded decision: no
  /// source read gives 5.5. It is the ceiling for a supplied value.
  static const double _dryBrakingDecelerationMps2 = 5.5;

  /// Ice braking deceleration, m/s², used where the context classifies
  /// radiative-frost black ice: when no value is supplied, and as the
  /// ceiling for a supplied value. A recorded decision: 0.981 = 0.10 ×
  /// 9.81, an ice figure, the lower edge of the ice ranges in TRB Special
  /// Report 115 (Table 1, "Ice 0.1 to 0.2") and 土木技術資料 52-5
  /// (表-2, 氷路面 0.2～0.1); wet or near-melting ice can be lower.
  static const double _inferredIceBrakingDecelerationMps2 = 0.981;

  /// Used for an unreadable supplied value: 0.4905 (0.05 × 9.81), the
  /// lowest bounded friction figure in the sources read (VTI meddelande
  /// 911A, wet black ice 0.05–0.10). TRB Special Report 115 reports
  /// friction on completely flat ice surfaces sometimes dropping to near
  /// zero, which no finite floor represents.
  static const double _unreadableBrakingDecelerationMps2 = 0.4905;

  /// Numeric guard only, not a physical figure: keeps the braking
  /// distance finite for a vanishing positive value.
  static const double _minBrakingDecelerationMps2 = 1e-3;

  static bool _isFrostClassified(DrivingContext context) {
    final ambient = context.ambientTempCelsius;
    final rh = context.humidityRH;
    if (ambient == null || rh == null) return false;
    return isRadiativeFrostBlackIce(
      ambientCelsius: ambient,
      humidityRHPercent: rh * 100.0,
    );
  }

  static double _brakingDecelerationFor(
    double? supplied, {
    required bool frostClassified,
  }) {
    if (supplied == null) {
      return frostClassified
          ? _inferredIceBrakingDecelerationMps2
          : _dryBrakingDecelerationMps2;
    }
    if (!supplied.isFinite || supplied <= 0) {
      return _unreadableBrakingDecelerationMps2;
    }
    final readable = supplied > _dryBrakingDecelerationMps2
        ? _dryBrakingDecelerationMps2
        : (supplied < _minBrakingDecelerationMps2
              ? _minBrakingDecelerationMps2
              : supplied);
    return frostClassified && _inferredIceBrakingDecelerationMps2 < readable
        ? _inferredIceBrakingDecelerationMps2
        : readable;
  }

  /// Per-profile reaction-time defaults in seconds, recorded decisions:
  /// no source cited gives them. See the
  /// `lib/src/speed_dependent_visibility.dart` module header in the
  /// `navigation_safety_calibration` package and `KNOWN_LIMITATIONS.md`.
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
  /// first, then the environmental delta (inside
  /// [forProfileWithContext], followed there by any vehicle-class
  /// override), then the state delta. Each step warns earlier, never
  /// later, except a vehicle-class registry that
  /// [forProfileWithContext] describes as unchecked.
  ///
  /// State deltas at this spike (0.6.0) are intentionally small and
  /// flagged UNVERIFIED in `KNOWN_LIMITATIONS.md` (state-axis section).
  /// The shape of the API is the load-bearing piece; the magnitudes
  /// are placeholders pending state-axis calibration; Regan and Strayer
  /// 2014 (PMC4001671) name driver states as factors in inattention but
  /// give no magnitudes.
  ///
  /// 0.5.0 callers that pass [DriverProfile] alone to
  /// [forProfile] / [forProfileWithContext] see no behaviour change;
  /// state-axis tuning is opt-in via this factory only.
  ///
  /// **DriverState-axis scaffolding (0.10.0)**: five new optional
  /// named parameters. [vehicleOverrides] is applied inside
  /// `forProfileWithContext`, and so BEFORE the state-delta; the
  /// [circadianPhase] and [sessionState] lifts are applied AFTER it.
  /// They do not all add caution; each is described below:
  ///
  /// - [vehicleOverrides] — vehicle-class threshold-override registry
  ///   (0.9.0). When supplied, the registry composes through
  ///   `forProfileWithContext` (caution-add-only invariant refused at
  ///   registration by `VehicleThresholdOverrides.validated`, and
  ///   re-checked without throwing by the `applyOverrideForToken` that
  ///   `VehicleThresholdOverrides` defines). A registry whose class
  ///   implements `VehicleThresholdOverrides`, or extends it and
  ///   replaces that method, is checked only if its method returns what
  ///   that one returns; otherwise its result reaches this config
  ///   unchecked. A throw from its method leaves this factory.
  /// - [circadianPhase] — time-of-day circadian classification
  ///   (0.10.0). When supplied, the per-phase multiplier
  ///   ([CircadianPhaseMultiplier.multiplier], always `>= 1.0`) is
  ///   applied to the warning-tier visibility floor
  ///   (caution-add-only).
  /// - [sessionState] — driving-session-state with consecutive-day
  ///   counter + cumulative-fatigue classification (0.10.0). When
  ///   supplied, a per-class lift adjusts the warning-tier visibility
  ///   floor (caution-add-only; `rested` no-op).
  /// - [confidence] + [isHighConfidenceConfirmed] —
  ///   self-assessed-confidence signal with cap-override-with-
  ///   confirmation pattern (0.10.0). [Confidence.low] multiplies the
  ///   alerts-per-minute cap by 0.75 automatically, but never below
  ///   1.0, so `foreignTouristSnowZone`'s default cap of 1.0 does not
  ///   change. [Confidence.high]
  ///   loosens the cap ONLY when [isHighConfidenceConfirmed] is
  ///   `true`; otherwise treated as [Confidence.medium] (no-op).
  ///   [AlertDensityThrottle] admits alerts up to the cap rounded up,
  ///   so a changed cap changes how many advisory alerts it admits only
  ///   where that whole number changes. With the per-profile defaults,
  ///   it admits fewer under [Confidence.low] only for `ageingRural` (2
  ///   per window to 1) and `professional` (4 to 3), and more under a
  ///   confirmed [Confidence.high] for every profile except
  ///   `ageingRural` and `noviceUrban`.
  ///   The driver-always-drives invariant requires affirmative
  ///   driver confirmation for cap-loosening; the system never
  ///   auto-relaxes from a high-confidence reading alone.
  ///
  /// Magnitudes for the circadian-phase, session-state and confidence
  /// inputs are **design-default hypotheses** pending
  /// field-measurement validation; see `KNOWN_LIMITATIONS.md`
  /// (DriverState-scaffolding section, 0.10.0) for the per-input
  /// UNVERIFIED-magnitude flag.
  factory NavigationSafetyConfig.forDriverContext(
    DriverContext driverContext, {
    DrivingContext? environmentalContext,
    VehicleThresholdOverrides? vehicleOverrides,
    CircadianPhase? circadianPhase,
    SessionState? sessionState,
    Confidence? confidence,
    bool isHighConfidenceConfirmed = false,
  }) {
    // Step 1: trait + (optional) environmental + (optional) vehicle-
    // class override baseline reuses the proven 0.5.0 / 0.9.0 path so
    // any future calibration update there is automatically inherited
    // here. The vehicle-class override (if any) applies AFTER the
    // per-profile baseline AND AFTER the live-context adjustment in
    // `forProfileWithContext`. For a registry built with a
    // VehicleThresholdOverrides constructor, the caution-add-only +
    // severity-not-profile checks run there in EVERY build mode, on all
    // ten threshold fields. Each violating field goes back to its
    // un-overridden value and is reported, never silently applied and
    // never thrown, and the legal rest of the override is kept. Of those
    // registries, only one built with VehicleThresholdOverrides.validated
    // throws, and it does so earlier, at registration. A registry class
    // that implements VehicleThresholdOverrides, or extends it and
    // replaces applyOverrideForToken, is checked there only if its
    // method returns what VehicleThresholdOverrides' own method returns;
    // otherwise its result is applied as it comes, unreported. A throw
    // from its method leaves this factory.
    final base = NavigationSafetyConfig.forProfileWithContext(
      driverContext.profile,
      context: environmentalContext,
      vehicleOverrides: vehicleOverrides,
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
      final extraMeters =
          environmentalContext!.speedMps! * reactionPenaltySeconds;
      final candidate = base.warningVisibilityMeters + extraMeters.ceil();
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

    // Step 3 (0.10.0): circadian-phase multiplier. Applied to the
    // warning-tier visibility floor only (caution-add-only;
    // multiplier always `>= 1.0` per the
    // [CircadianPhaseMultiplier.multiplier] contract). Asserted at
    // runtime in debug builds.
    if (circadianPhase != null) {
      final m = circadianPhase.multiplier;
      assert(
        m >= 1.0,
        'CircadianPhase.${circadianPhase.name} multiplier $m violates '
        'caution-add-only floor (must be >= 1.0).',
      );
      final candidate = (warningVisibility * m).ceil();
      if (candidate > warningVisibility) {
        warningVisibility = candidate;
      }
    }

    // Step 4 (0.10.0): session-state cumulative-fatigue lift. Applied
    // to the warning-tier visibility floor only; `rested` no-op.
    // Magnitudes UNVERIFIED — design-default hypotheses pending
    // fleet-class field measurement.
    if (sessionState != null) {
      final lift = _sessionFatigueVisibilityLiftMeters(
        sessionState.cumulativeFatigue,
      );
      assert(
        lift >= 0,
        'CumulativeFatigueClass.${sessionState.cumulativeFatigue.name} '
        'visibility lift $lift violates caution-add-only floor '
        '(must be >= 0).',
      );
      if (lift > 0) {
        warningVisibility = warningVisibility + lift;
      }
    }

    // Step 5 (0.10.0): confidence cap-override-with-confirmation.
    // - `low` multiplies the alerts-per-minute cap by 0.75, never below
    //   1.0; see _confidenceAdjustedCap for what that admits.
    // - `medium` is a no-op.
    // - `high` requires `isHighConfidenceConfirmed == true` to loosen
    //   the cap; without confirmation it is treated as `medium`
    //   (no-op). Driver-always-drives invariant: the system never
    //   auto-relaxes the cap from a high-confidence reading alone.
    final newCap = _confidenceAdjustedCap(
      baseCap: base.alertsPerMinuteCapOverride,
      profile: driverContext.profile,
      confidence: confidence,
      isHighConfidenceConfirmed: isHighConfidenceConfirmed,
    );

    // Driver-always-drives runtime debug-assertion: if confidence is
    // `high` but not confirmed, the resolved cap MUST equal the
    // baseline cap (no auto-loosening path exists).
    assert(
      !(confidence == Confidence.high && !isHighConfidenceConfirmed) ||
          newCap == base.alertsPerMinuteCapOverride,
      'Confidence.high without isHighConfidenceConfirmed must NOT '
      'modify alertsPerMinuteCapOverride; driver-always-drives '
      'invariant violated.',
    );

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
      criticalGripScoreFloor: base.criticalGripScoreFloor,
      alertsPerMinuteCapOverride: newCap,
    );
  }

  /// Per-`CumulativeFatigueClass` visibility lift in meters applied
  /// to the warning-tier visibility floor by
  /// [forDriverContext]. Caution-add-only: every value `>= 0`.
  /// Magnitudes UNVERIFIED at 0.10.0 — design-default hypotheses
  /// pending fleet-class field measurement (see
  /// `KNOWN_LIMITATIONS.md` session-state section).
  static int _sessionFatigueVisibilityLiftMeters(
    CumulativeFatigueClass fatigue,
  ) {
    switch (fatigue) {
      case CumulativeFatigueClass.rested:
        return 0;
      case CumulativeFatigueClass.mild:
        return 25;
      case CumulativeFatigueClass.accumulated:
        return 50;
      case CumulativeFatigueClass.severe:
        return 100;
    }
  }

  /// Resolve the alerts-per-minute cap under the
  /// cap-override-with-confirmation pattern (0.10.0). Returns the
  /// baseline cap (carried through the layering chain) when no
  /// confidence signal is supplied, when confidence is `medium`, or
  /// when confidence is `high` without `isHighConfidenceConfirmed`.
  /// On `low` multiplies the cap by 0.75, never below 1.0; loosens it
  /// on `high`-confirmed only.
  ///
  /// Magnitudes UNVERIFIED at 0.10.0 — design-default hypotheses
  /// pending field-measurement validation (see
  /// `KNOWN_LIMITATIONS.md` confidence-provider section).
  static double? _confidenceAdjustedCap({
    required double? baseCap,
    required DriverProfile profile,
    required Confidence? confidence,
    required bool isHighConfidenceConfirmed,
  }) {
    if (confidence == null) return baseCap;
    final effectiveBase =
        baseCap ?? AlertDensityThrottle.defaultCapFor(profile);
    switch (confidence) {
      case Confidence.medium:
        return baseCap;
      case Confidence.low:
        // Scale by 0.75, aiming at fewer advisory alerts per minute for
        // the less-confident driver. Floor at 1.0 alerts/min so the cap
        // remains operational. The throttle admits alerts up to the cap
        // rounded up, so the admitted count drops only where that whole
        // number drops: of the per-profile defaults, 1.2 (2 to 1) and
        // 4.0 (4 to 3); 3.0, 2.0 and 1.5 keep theirs, and 1.0 stays 1.0.
        final tightened = effectiveBase * 0.75;
        return tightened < 1.0 ? 1.0 : tightened;
      case Confidence.high:
        if (!isHighConfidenceConfirmed) {
          // Driver-always-drives invariant: no auto-loosen.
          return baseCap;
        }
        // Loosen by 25% (only with affirmative confirmation).
        return effectiveBase * 1.25;
    }
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
        return const _StateDelta(reactionTimePenaltySeconds: 1.0);
      case DriverState.impairedVisibility:
        return const _StateDelta(visibilityScale: 1.25);
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
    this.criticalGripScoreFloor = _glareIceGripRatio,
    this.alertsPerMinuteCapOverride,
  }) {
    // Conservative-on-uncertain invariant at the config boundary
    // (sibling to SafetyScore's non-finite guard): a non-finite score floor
    // (NaN / ±Infinity) is NaN-permissive against the `< 0 || > 1`
    // range checks below — NaN compares false to both bounds, and the
    // ordering checks (`safeScoreFloor < infoScoreFloor`) are likewise
    // false against NaN — so it would pass construction silently. It
    // then poisons `SafetyScore.toAlertSeverity`, where `overall < NaN`
    // is always false: even overall == 0 (the worst-case value)
    // yields NO alert, inverting the "if uncertain, alert
    // conservatively" guarantee on the operand SafetyScore's guard
    // does not reach. Reject it loudly at construction, consistent with
    // the throw-on-invalid-floor contract — a non-finite threshold is a
    // programming error, not uncertain runtime data.
    if (!safeScoreFloor.isFinite) {
      throw ArgumentError.value(
        safeScoreFloor,
        'safeScoreFloor',
        'must be finite',
      );
    }
    if (!infoScoreFloor.isFinite) {
      throw ArgumentError.value(
        infoScoreFloor,
        'infoScoreFloor',
        'must be finite',
      );
    }
    if (!warningScoreFloor.isFinite) {
      throw ArgumentError.value(
        warningScoreFloor,
        'warningScoreFloor',
        'must be finite',
      );
    }
    if (safeScoreFloor < 0 || safeScoreFloor > 1) {
      throw RangeError.range(safeScoreFloor, 0, 1, 'safeScoreFloor');
    }
    if (infoScoreFloor < 0 || infoScoreFloor > 1) {
      throw RangeError.range(infoScoreFloor, 0, 1, 'infoScoreFloor');
    }
    if (warningScoreFloor < 0 || warningScoreFloor > 1) {
      throw RangeError.range(warningScoreFloor, 0, 1, 'warningScoreFloor');
    }
    // Same conservative-on-uncertain reasoning as the score floors above: a
    // non-finite grip floor makes `gripScore < floor` always false, silently
    // disabling the per-axis critical rule instead of failing loudly.
    if (!criticalGripScoreFloor.isFinite) {
      throw ArgumentError.value(
        criticalGripScoreFloor,
        'criticalGripScoreFloor',
        'must be finite',
      );
    }
    if (criticalGripScoreFloor < 0 || criticalGripScoreFloor > 1) {
      throw RangeError.range(
        criticalGripScoreFloor,
        0,
        1,
        'criticalGripScoreFloor',
      );
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
  /// the per-profile default (a recorded decision) otherwise.
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
    criticalGripScoreFloor,
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
