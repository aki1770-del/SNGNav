/// Humidity-dependent effective-temperature formula.
///
/// Black ice can form on a road surface when the ambient air is
/// several degrees above 0°C: clear-sky radiative cooling at night
/// drops the road-surface temperature toward the dew point, and any
/// surface moisture that reaches the dew point freezes. A naive
/// "warn below 0°C ambient" threshold misses this window.
///
/// This helper estimates an effective road-surface temperature for
/// frost-risk reasoning by subtracting the dew-point depression from
/// the ambient temperature. The dew point is computed via the Magnus
/// formula:
///
/// ```
/// gamma = (a * T) / (b + T) + ln(RH)
/// dew_point = (b * gamma) / (a - gamma)
/// ```
///
/// with constants `a = 17.625` and `b = 243.04 °C` from the modern
/// August-Roche-Magnus parameterisation. The dew-point depression is
/// `T - dew_point`, always non-negative for `RH` in `[0, 1]`.
///
/// Effective road-surface temperature is approximated as
/// `ambient - depression`. The approximation is conservative: real
/// road-surface temperature depends on emissivity, sky cloud cover,
/// surface material, and time-of-night. UNVERIFIED for any specific
/// surface; consumers should treat the output as a frost-risk indicator
/// rather than a measured surface temperature.
///
/// Citations:
///
/// - **Magnus formula** — Magnus, G. (1844); the modern parameter
///   constants `a = 17.625`, `b = 243.04 °C` are documented in standard
///   atmospheric-science references (Alduchov & Eskridge 1996).
/// - **Black-ice formation envelope** — well-documented at road
///   surface temperatures ≤ 0 °C even when ambient air is several
///   degrees warmer ([Wikipedia black ice](https://en.wikipedia.org/wiki/Black_ice)).
/// - **Road-surface radiative cooling** — UNVERIFIED specific cite for
///   the magnitude of nighttime cooling vs. ambient under varied
///   cloud cover; this helper returns a conservative estimate.
library;

import 'dart:math' as math;

const double _magnusA = 17.625;
const double _magnusB = 243.04;

/// Compute an effective road-surface temperature in Celsius for
/// frost-risk reasoning.
///
/// Subtracts the dew-point depression (computed via the Magnus formula
/// from [ambientCelsius] and [humidityRH]) from the ambient
/// temperature. Returns a conservative estimate of the temperature a
/// road surface may reach during clear-sky nighttime radiative cooling.
///
/// [humidityRH] must lie in `(0.0, 1.0]`. A value of `0.0` is rejected
/// because `ln(0)` is undefined; pass a small positive value (e.g.
/// `1e-3`) to represent very dry air.
///
/// Throws [ArgumentError] if [humidityRH] is outside `(0.0, 1.0]`.
double computeEffectiveTemperatureCelsius({
  required double ambientCelsius,
  required double humidityRH,
}) {
  if (humidityRH <= 0.0 || humidityRH > 1.0) {
    throw ArgumentError.value(
      humidityRH,
      'humidityRH',
      'must lie in (0.0, 1.0]',
    );
  }

  final gamma =
      (_magnusA * ambientCelsius) / (_magnusB + ambientCelsius) +
          math.log(humidityRH);
  final dewPoint = (_magnusB * gamma) / (_magnusA - gamma);
  final depression = ambientCelsius - dewPoint;

  return ambientCelsius - depression;
}
