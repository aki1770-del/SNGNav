/// Surface-moisture exponential-decay formula.
///
/// After precipitation ends, surface moisture evaporates over time.
/// The decay is well-modelled by an exponential with an
/// evaporation half-life that depends on ambient temperature, surface
/// material, wind, sun exposure, and shade.
///
/// This helper returns a moisture fraction in `[0.0, 1.0]` where 1.0
/// means surface fully wet (precipitation just ended) and 0.0 means
/// surface fully dry.
///
/// ```
/// moistureFraction = exp(-ln(2) * t / halfLife)
/// ```
///
/// Default half-life is 90 minutes — a deliberately conservative
/// choice biased toward "still wet" so the consuming app warns longer
/// rather than shorter on residual surface moisture. Most road
/// surfaces dry faster than 90 minutes under sun and wind; some dry
/// slower (shaded, cold, low-wind environments). Consumers with
/// telemetry that informs a more accurate half-life should override.
///
/// Citations:
///
/// - **Exponential surface-moisture decay** — UNVERIFIED specific
///   cite. The exponential-decay shape is the standard
///   first-order-evaporation model used in pavement-engineering and
///   atmospheric-science references; the 90-minute default is
///   conservative rather than population-validated.
/// - **Half-life dependence on ambient conditions** — well-documented
///   qualitative dependency on temperature, wind, and solar load; no
///   single published number captures every road context.
///
/// The [ambientCelsius] parameter is accepted for forward-compatible
/// API shape (a future revision may modulate the half-life by
/// temperature) and is currently unused. Naming it now lets the
/// signature stabilise before that calibration lands.
library;

import 'dart:math' as math;

/// Compute the fraction of surface moisture remaining after a
/// precipitation event ended [timeSincePrecipitation] ago.
///
/// Returns a value in `[0.0, 1.0]`: `1.0` immediately after
/// precipitation; decays exponentially with the supplied
/// [evaporationHalfLifeMinutes] (default 90 minutes — conservative).
///
/// [ambientCelsius] is accepted for forward-compatible API shape; it
/// is not currently used in the formula but allows a future revision
/// to modulate the half-life by temperature without an API break.
///
/// Throws [ArgumentError] if [evaporationHalfLifeMinutes] is
/// non-positive or [timeSincePrecipitation] is negative.
double computeSurfaceMoistureFraction({
  required Duration timeSincePrecipitation,
  required double ambientCelsius,
  double evaporationHalfLifeMinutes = 90.0,
}) {
  if (evaporationHalfLifeMinutes <= 0) {
    throw ArgumentError.value(
      evaporationHalfLifeMinutes,
      'evaporationHalfLifeMinutes',
      'must be positive',
    );
  }
  if (timeSincePrecipitation.isNegative) {
    throw ArgumentError.value(
      timeSincePrecipitation,
      'timeSincePrecipitation',
      'must be non-negative',
    );
  }

  final minutes = timeSincePrecipitation.inMicroseconds / Duration.microsecondsPerMinute;
  final fraction = math.exp(-math.ln2 * minutes / evaporationHalfLifeMinutes);

  if (fraction.isNaN) return 0.0;
  if (fraction > 1.0) return 1.0;
  if (fraction < 0.0) return 0.0;
  return fraction;
}
