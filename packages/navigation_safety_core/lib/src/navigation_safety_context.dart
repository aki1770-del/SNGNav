/// Optional driving-context inputs for context-aware threshold tuning.
///
/// `DrivingContext` is an immutable value-object that lets a consuming
/// app pass live conditions into the threshold-config factory so the
/// returned thresholds reflect more than just the driver-class baseline.
///
/// Each field is optional. A null field means "this context is not
/// available right now"; the factory falls back to the non-context
/// baseline thresholds for that dimension. Any combination of fields
/// may be set.
///
/// Today's context-aware factory honours these fields:
///
/// - [speedMps] — current vehicle speed in metres per second; when
///   non-null, the warning visibility floor rises to the reaction plus
///   braking distance, when that is longer. The deceleration used is
///   [brakingDecelerationMps2] when supplied, otherwise 5.5 m/s², a
///   dry-pavement figure; where [ambientTempCelsius] and [humidityRH]
///   classify radiative-frost black ice, it is the lower of that and
///   0.981 m/s², an ice figure.
/// - [brakingDecelerationMps2] — the deceleration the integrator
///   expects the vehicle can reach on the current surface, in m/s².
///   It can only lengthen the floor. `NaN`, infinities, zero and
///   negative values are checked first and used as 0.4905, whatever the
///   readings; then values above 5.5 are used as 5.5, and where the
///   readings classify radiative-frost black ice, values above 0.981
///   are used as 0.981.
/// - [humidityRH] — relative humidity as a fraction in `(0.0, 1.0]`;
///   combined with [ambientTempCelsius] adjusts the warning temperature
///   for dew-point-driven black-ice risk.
/// - [timeSincePrecipitation] — duration since the last observed
///   precipitation event; surface-moisture decays exponentially from
///   that point and the wetness-class warning weight adjusts.
/// - [ambientTempCelsius] — ambient air temperature in Celsius; carried
///   here so a single context value-object describes the full coupled
///   state when humidity is also present.
/// - [vehicleClassToken] — stable string token (e.g. `'kei-car'`,
///   `'compact-sedan'`, `'4wd'`, `'commercial-light'`) sourced from
///   an integrator-supplied `VehicleClassProvider`. When a matching
///   override is registered in a `VehicleThresholdOverrides` passed
///   to the factory, it applies AFTER the per-profile baseline AND
///   AFTER the live-context adjustments. Through a registry built with
///   a `VehicleThresholdOverrides` constructor it can only move the
///   warning thresholds earlier. A registry whose class implements
///   `VehicleThresholdOverrides`, or extends it and replaces
///   `applyOverrideForToken`, is applied unchecked unless its method
///   returns what that one returns. `null` (the default) means no
///   vehicle-class signal is available; thresholds fall back to the
///   per-profile baseline.
///
/// The live-condition fields are additive in conservatism: they can only
/// make the thresholds warn earlier, never later, than the per-profile
/// baseline, which acts as their floor. A vehicle-class registry of the
/// integrator's own class, as above, can take a threshold below it.
library;

import 'package:equatable/equatable.dart';

/// Live driving-context inputs for context-aware threshold tuning.
///
/// Pass to `NavigationSafetyConfig.forProfileWithContext` alongside a
/// [DriverProfile] to receive thresholds tuned to both the driver-class
/// baseline and the live conditions. See class-level documentation for
/// field semantics and the null-as-absent convention.
class DrivingContext extends Equatable {
  /// Current vehicle speed in metres per second. `null` means the
  /// caller does not have a fresh speed sample; the visibility
  /// threshold falls back to the per-profile baseline.
  final double? speedMps;

  /// Relative humidity as a fraction in `(0.0, 1.0]` (i.e. `0.85` for
  /// 85% RH). `null` means humidity is unknown; the temperature
  /// threshold falls back to the per-profile baseline.
  ///
  /// UNIT WARNING: weather APIs and the `pretrip_*` packages carry
  /// relative humidity in PERCENT under the same field name. Percent
  /// passed here throws in the downstream calibration. For a
  /// percent-sourced reading use [DrivingContext.withPercentHumidity].
  final double? humidityRH;

  /// Duration since the last observed precipitation event. `null`
  /// means precipitation history is unknown; the surface-moisture
  /// decay does not contribute to the threshold.
  final Duration? timeSincePrecipitation;

  /// Ambient air temperature in Celsius. Used together with
  /// [humidityRH] for dew-point-driven black-ice risk estimation.
  /// `null` means ambient is unknown.
  final double? ambientTempCelsius;

  /// Stable string token identifying the vehicle-class semantic
  /// (e.g. `'kei-car'`, `'compact-sedan'`, `'4wd'`,
  /// `'commercial-light'`) sourced from an integrator-supplied
  /// `VehicleClassProvider`. Consumed by
  /// `NavigationSafetyConfig.forProfileWithContext` together with an
  /// optional `VehicleThresholdOverrides` registry, whose override
  /// applies AFTER the per-profile baseline AND AFTER the live-context
  /// adjustments.
  ///
  /// Tokens are advisory strings, NOT control inputs, and they do NOT
  /// close any control loop (per the driver-always-drives invariant).
  /// Through a registry built with a `VehicleThresholdOverrides`
  /// constructor a token can only move the two warning thresholds
  /// earlier; a score floor, critical or info threshold, or the
  /// alerts-per-minute cap comes back at its un-overridden value (per
  /// the severity-not-profile invariant). A registry whose class
  /// implements `VehicleThresholdOverrides`, or extends it and replaces
  /// `applyOverrideForToken`, gets none of that unless its method
  /// returns what that one returns: what its method returns is applied
  /// as it comes, in every build mode.
  ///
  /// `null` (the default) means the integrator does not have a
  /// vehicle-class signal in this trip / session; thresholds fall
  /// back to the per-profile baseline.
  final String? vehicleClassToken;

  /// Braking deceleration in m/s² for the current surface, used with
  /// [speedMps] to compute the warning-visibility floor. `null` means
  /// the integrator has no surface-specific value.
  ///
  /// No single figure fits a road condition. Published skid-resistance
  /// surveys report friction numbers such as 0.8–1.0 on a dry bare
  /// surface, 0.20–0.30 on packed snow and 0.05–0.10 on wet black ice
  /// (Wallman and Åström, VTI meddelande 911A, 2001); multiplying by
  /// 9.81 m/s² gives an upper bound on deceleration, not a measured
  /// stopping figure.
  ///
  /// Values above 5.5 are used as 5.5. Where [ambientTempCelsius] and
  /// [humidityRH] classify radiative-frost black ice, values above 0.981
  /// are used as 0.981 (0.10 × 9.81, the lower edge of the ice ranges in
  /// TRB Special Report 115 and 土木技術資料 52-5), the figure used there
  /// when this field is `null`. So a supplied value never gives a
  /// shorter floor than leaving it out. To check whether given readings
  /// classify it, call `isRadiativeFrostBlackIce(ambientCelsius:
  /// ambientTempCelsius, humidityRHPercent: humidityRH * 100)`, which
  /// this package re-exports; it takes humidity in percent. `NaN`,
  /// infinities, zero and negative values are checked before the 5.5
  /// and 0.981 rules: they are not readable and are used as 0.4905
  /// (0.05 × 9.81), the lowest bounded friction figure in the
  /// sources read (VTI meddelande 911A, wet black ice 0.05–0.10). TRB
  /// Special Report 115 reports friction on completely flat ice surfaces
  /// sometimes dropping to near zero, which no finite floor represents.
  /// The factory does not throw on these values, and at 120 km/h they
  /// give floors of 1,183 to 1,252 m across the six profiles: pass
  /// `null`, not a sentinel such as `0`, `-1` or `NaN`, when no value was
  /// measured.
  final double? brakingDecelerationMps2;

  /// Construct a context value. Every field is optional. Pass `null`
  /// for any input you do not have; the factory will fall back to the
  /// per-profile baseline for that dimension.
  ///
  /// NOTE the unit of [humidityRH]: a FRACTION in `(0.0, 1.0]`. Weather
  /// APIs and the `pretrip_*` packages carry relative humidity in
  /// PERCENT (`95.0`) — passing percent here throws downstream in the
  /// calibration. If your source is percent, use
  /// [DrivingContext.withPercentHumidity].
  const DrivingContext({
    this.speedMps,
    this.humidityRH,
    this.timeSincePrecipitation,
    this.ambientTempCelsius,
    this.vehicleClassToken,
    this.brakingDecelerationMps2,
  });

  /// Construct a context from a PERCENT relative-humidity reading
  /// (`95.0` for 95% RH) — the meteorological convention used by
  /// weather APIs (e.g. MET Norway `relative_humidity`) and by the
  /// `pretrip_*` forecast models. Converts to the fraction contract of
  /// [humidityRH] internally.
  ///
  /// Handles the dirty values real feeds deliver, caution-consistently:
  ///
  /// - `1.0 <= p <= 100.0` — converted to the fraction (`95.0` → `0.95`).
  /// - `100.0 < p <= 105.0` — **saturated to `100.0`**: a reading slightly
  ///   above 100% is kept as saturated air rather than rejected, so a dirty
  ///   feed does not crash the safety path (a recorded decision; no source
  ///   is cited for when feeds deliver such readings). Saturated air is not
  ///   the most cautious input here: at 100% RH the effective temperature
  ///   equals ambient, so humidity adds the least lift (see README.md,
  ///   "Humidity-dependent effective temperature").
  /// - `p <= 0.0` — treated as **unknown** (`humidityRH: null`): `0.0` is
  ///   a common missing-data sentinel; no lift, no crash.
  /// - `0.0 < p < 1.0` — **rejected** ([ArgumentError]): sub-1% RH is
  ///   almost certainly a FRACTION mis-wired into the percent door (the
  ///   exact confusion this factory exists to prevent — `0.95` here would
  ///   silently mean 0.95% RH). Pass fractions to [humidityRH] directly.
  /// - `p > 105.0`, `NaN`, `±inf` — **rejected** ([ArgumentError]): not a
  ///   plausible RH reading; surface the feed bug instead of guessing.
  factory DrivingContext.withPercentHumidity({
    double? speedMps,
    double? humidityPercent,
    Duration? timeSincePrecipitation,
    double? ambientTempCelsius,
    String? vehicleClassToken,
    double? brakingDecelerationMps2,
  }) {
    double? fraction;
    final p = humidityPercent;
    if (p != null) {
      if (!p.isFinite || p > 105.0) {
        throw ArgumentError.value(
          p,
          'humidityPercent',
          'not a plausible RH percent reading (finite, <= 105.0 expected)',
        );
      }
      if (p > 0.0 && p < 1.0) {
        throw ArgumentError.value(
          p,
          'humidityPercent',
          'sub-1% RH is almost certainly a FRACTION mis-wired into the '
              'percent door; pass fractions to DrivingContext(humidityRH: ...)',
        );
      }
      if (p <= 0.0) {
        fraction = null; // missing-data sentinel -> unknown, no lift, no crash
      } else if (p > 100.0) {
        fraction = 1.0; // supersaturation -> saturated air, kept rather than rejected
      } else {
        fraction = p / 100.0;
      }
    }
    return DrivingContext(
      speedMps: speedMps,
      humidityRH: fraction,
      timeSincePrecipitation: timeSincePrecipitation,
      ambientTempCelsius: ambientTempCelsius,
      vehicleClassToken: vehicleClassToken,
      brakingDecelerationMps2: brakingDecelerationMps2,
    );
  }

  @override
  List<Object?> get props => [
    speedMps,
    humidityRH,
    timeSincePrecipitation,
    ambientTempCelsius,
    vehicleClassToken,
    brakingDecelerationMps2,
  ];

  @override
  bool get stringify => true;
}
