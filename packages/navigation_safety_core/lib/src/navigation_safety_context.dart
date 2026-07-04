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
///   non-null, the warning visibility floor adjusts to ensure reaction
///   time + braking distance fits the threshold.
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
///   to the factory, the warning thresholds adjust caution-add-only
///   AFTER the per-profile baseline AND AFTER the live-context
///   adjustments. `null` (the default) means no vehicle-class signal
///   is available; thresholds fall back to the per-profile baseline.
///
/// All adjustments are additive in conservatism: context can only make
/// the thresholds warn earlier, never later, than the per-profile
/// baseline. The per-profile baseline acts as a floor.
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
  /// optional `VehicleThresholdOverrides` registry to apply
  /// caution-adding-only threshold adjustments AFTER the per-profile
  /// baseline AND AFTER the live-context adjustments.
  ///
  /// Tokens are advisory strings, NOT control inputs. They modulate
  /// threshold TIMING only; they do NOT modify alert SEVERITY (per
  /// the severity-not-profile invariant) and they do NOT close any
  /// control loop (per the driver-always-drives invariant).
  ///
  /// `null` (the default) means the integrator does not have a
  /// vehicle-class signal in this trip / session; thresholds fall
  /// back to the per-profile baseline.
  final String? vehicleClassToken;

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
  /// - `100.0 < p <= 105.0` — **saturated to `100.0`**: supersaturated RH
  ///   slightly above 100% is a documented NWP/sensor reality at peak
  ///   icing and freezing fog; saturated air = maximum caution, so the
  ///   reading is kept, not crashed on.
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
        fraction = 1.0; // supersaturation -> saturated air, maximum caution
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
    );
  }

  @override
  List<Object?> get props => [
    speedMps,
    humidityRH,
    timeSincePrecipitation,
    ambientTempCelsius,
    vehicleClassToken,
  ];

  @override
  bool get stringify => true;
}
