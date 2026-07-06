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

/// Ambient-air ceiling for the radiative-frost black-ice condition, °C.
///
/// The calibration's documented envelope is black ice forming when the
/// ambient air is "several degrees above 0 °C" (clear-sky radiative
/// cooling drops the road surface toward the dew point). The dew-point
/// test ALONE has no such bound and would fire on benign dry afternoons
/// (probe-measured: 20 °C at 25 % RH) — cry-wolf that discredits the
/// warning before the genuine near-zero morning. This ceiling keeps the
/// classification inside the physics the calibration documents.
const double radiativeFrostAmbientCeilingCelsius = 3.0;

/// Effective road-surface temperature at or below which the radiative-frost
/// window is treated as black-ice-forming, °C.
const double radiativeFrostSurfaceTempCelsius = 0.0;

/// Single source of truth for the radiative-frost black-ice classification.
///
/// Black ice can form with NO precipitation and with the ambient air a few
/// degrees ABOVE 0 °C — the clear-sky-radiative-cooling window that a naive
/// "warn below 0 °C ambient" (or "ice only when it is precipitating") check
/// silently drops. This is the exact Akita pre-dawn bridge-deck hazard: the
/// road surface radiatively cools toward the dew point and any surface
/// moisture freezes while the air still reads +1…+3 °C.
///
/// **Mechanism + honest scope.** This is a dew-point-depression model
/// (`effective` == the dew point), so it fires when the dew point is at or
/// below 0 °C — i.e. under DRY-to-MODERATE humidity, where clear-sky cooling
/// can carry the surface below freezing. It deliberately does NOT fire on
/// near-SATURATED air in the above-zero band: at, say, +2 °C / 95 % RH the dew
/// point is ~ +1.3 °C, so it returns `false` (classifies not-frost). One
/// consequence worth naming: near-zero SATURATED FREEZING FOG above ~ +1 °C
/// (dew point ≥ 0) is therefore NOT detected by this model — a genuine hazard
/// this function does not cover. What it adds is the dry-to-moderate-humidity
/// radiative-cooling case, not saturated freezing fog.
///
/// Returns `true` when [ambientCelsius] is within
/// [radiativeFrostAmbientCeilingCelsius] AND the Magnus-formula effective
/// road-surface temperature (see [computeEffectiveTemperatureCelsius], which
/// returns a CONSERVATIVE estimate — read its citations + UNVERIFIED-magnitude
/// caveat) is at or below [radiativeFrostSurfaceTempCelsius].
///
/// **Why this exists as ONE function.** The pre-trip briefing and the
/// in-drive road-surface classifier must never disagree about black ice: a
/// driver who reads a pre-trip black-ice warning and then sees the live
/// in-drive screen say "conditions normal" trusts the reassuring live screen
/// at the exact moment of danger. Two independently-maintained copies of this
/// threshold logic ARE that disagreement waiting to happen. Both surfaces call
/// this function so they cannot drift.
///
/// **Caution-add-only by construction.** The effective estimate never exceeds
/// ambient, so this can only ADD the above-zero-ambient window — it never
/// removes an existing flag and never downgrades a colder classification.
///
/// **Never throws; absence is never hazard.** [humidityRHPercent] is RELATIVE
/// HUMIDITY IN PERCENT (not the fraction [computeEffectiveTemperatureCelsius]
/// takes). This function ADAPTS the calibration's percent→fraction boundary
/// instead of mirroring it: the low-level primitive THROWS on implausible
/// input (an API argument error is the right signal for a programming bug),
/// but a classifier feeding a live safety surface must never crash on one
/// dirty feed value, so EVERY rejected input class simply returns `false`:
///
/// - `null`, `NaN`, `±inf` — missing / corrupt data: nothing;
/// - `(100, 105]` — supersaturation reads as saturated air (`1.0`);
/// - `> 105` — implausible: nothing;
/// - `< 5` — a physical-plausibility floor. Dew-point math at near-zero
///   moisture cannot indicate frost moisture, and any value in `(0, 1]` is
///   almost certainly a mis-wired FRACTION (a saturated `1.0` passed as a
///   percent would read as 1 % RH and fabricate a deep false depression).
///   Genuine sub-5 % RH near freezing is meteorologically implausible, so the
///   floor costs zero true positives: nothing.
///
/// A non-finite [ambientCelsius] also returns `false`.
bool isRadiativeFrostBlackIce({
  required double ambientCelsius,
  required double? humidityRHPercent,
}) {
  if (!ambientCelsius.isFinite) return false;
  if (ambientCelsius > radiativeFrostAmbientCeilingCelsius) return false;

  final rhPercent = humidityRHPercent;
  if (rhPercent == null || !rhPercent.isFinite) return false;
  if (rhPercent < 5.0 || rhPercent > 105.0) return false;

  final fraction = rhPercent > 100.0 ? 1.0 : rhPercent / 100.0;
  // Defensive domain belt (the guard above already ensures [0.05, 1.0]): the
  // primitive throws outside (0, 1], and this classifier must never throw.
  if (fraction <= 0.0 || fraction > 1.0) return false;

  final effective = computeEffectiveTemperatureCelsius(
    ambientCelsius: ambientCelsius,
    humidityRH: fraction,
  );
  return effective <= radiativeFrostSurfaceTempCelsius;
}
