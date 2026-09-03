/// Boundary check for the values a caller claims to have measured.
///
/// Internal to the simulation lane; not exported. The [ArgumentError] it raises
/// is a core type, so a consumer catches it without importing anything.
library;

/// Rejects a non-finite simulation input.
///
/// `speed`, `gripFactor` and `visibilityMeters` are required, non-nullable
/// parameters: passing one is a claim to have measured it. `double.nan` is not
/// a measurement — it is a sensor that could not be read, arriving dressed as
/// one.
///
/// Up to 0.6.0 nothing checked. The engines fed these values straight into
/// `num.clamp(0.0, 1.0)`, and `double.nan.clamp(0.0, 1.0)` returns **`1.0`** —
/// so an unreadable grip sensor produced `gripScore == 1.0`, the value of a
/// perfectly dry road. Measured against published 0.6.0 on the `ageingRural`
/// profile: black ice at 300 m visibility scored `overall 0.3077` (`critical`),
/// and the SAME road with both sensors returning `nan` scored `overall 0.9373`
/// (`none` — all clear), which is higher than a genuinely perfect road at zero
/// speed (0.9178). **Absence outscored the best real road in the model.**
///
/// We do not substitute a value in either direction. `0.0` would be the same
/// fabrication pointed at danger, and would cry wolf until she stopped
/// believing the instrument. The honest answer to "what is the grip on a road
/// whose sensor is broken" is that this package does not know and will not say.
///
/// Throws [ArgumentError] naming [name]; returns [value] unchanged when finite.
double requireMeasured(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(
      value,
      name,
      'must be finite — an unreadable sensor is not a measurement. This '
      'package will not substitute a value for it in either direction: '
      'num.clamp() would silently make it 1.0 (a perfect road), and 0.0 would '
      'be the same fabrication pointed at danger',
    );
  }
  return value;
}
