/// Pure Dart navigation-safety calibration primitives.
///
/// This package re-exports three calibration-class helper functions
/// that constitute the stable meteorological / kinematic
/// design-default baseline shared across navigation-safety consumers:
///
/// - [computeSurfaceMoistureFraction] — exponential surface-moisture
///   decay after a precipitation event ends (default 90-minute
///   half-life; conservative; accepts ambient temperature for
///   forward-compatible API shape).
/// - [computeEffectiveTemperatureCelsius] — Magnus-formula dew-point
///   computation and an effective road-surface temperature for
///   frost-risk reasoning (constants `a = 17.625` / `b = 243.04 °C`
///   per Alduchov & Eskridge 1996).
/// - [computeSpeedAdjustedVisibilityMeters] — speed-adjusted
///   visibility floor combining reaction-time and braking distance
///   over a per-profile baseline (caution-add-only; the per-profile
///   floor never lowers).
///
/// No Flutter dependency. No transitive dependencies. Each source
/// file is byte-identical to the corresponding file in
/// `navigation_safety_core` 0.10.0 at extraction time; future
/// releases of `navigation_safety_core` are expected to depend-on
/// and re-export from this package for ABI-compat.
library;

export 'src/humidity_dependent_temperature.dart';
export 'src/precipitation_history_decay.dart';
export 'src/speed_dependent_visibility.dart';
