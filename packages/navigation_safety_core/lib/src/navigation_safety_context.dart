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
/// - [humidityRH] — relative humidity as a fraction in `[0.0, 1.0]`;
///   combined with [ambientTempCelsius] adjusts the warning temperature
///   for dew-point-driven black-ice risk.
/// - [timeSincePrecipitation] — duration since the last observed
///   precipitation event; surface-moisture decays exponentially from
///   that point and the wetness-class warning weight adjusts.
/// - [ambientTempCelsius] — ambient air temperature in Celsius; carried
///   here so a single context value-object describes the full coupled
///   state when humidity is also present.
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

  /// Relative humidity as a fraction in `[0.0, 1.0]` (i.e. `0.85` for
  /// 85% RH). `null` means humidity is unknown; the temperature
  /// threshold falls back to the per-profile baseline.
  final double? humidityRH;

  /// Duration since the last observed precipitation event. `null`
  /// means precipitation history is unknown; the surface-moisture
  /// decay does not contribute to the threshold.
  final Duration? timeSincePrecipitation;

  /// Ambient air temperature in Celsius. Used together with
  /// [humidityRH] for dew-point-driven black-ice risk estimation.
  /// `null` means ambient is unknown.
  final double? ambientTempCelsius;

  /// Construct a context value. Every field is optional. Pass `null`
  /// for any input you do not have; the factory will fall back to the
  /// per-profile baseline for that dimension.
  const DrivingContext({
    this.speedMps,
    this.humidityRH,
    this.timeSincePrecipitation,
    this.ambientTempCelsius,
  });

  @override
  List<Object?> get props => [
        speedMps,
        humidityRH,
        timeSincePrecipitation,
        ambientTempCelsius,
      ];

  @override
  bool get stringify => true;
}
