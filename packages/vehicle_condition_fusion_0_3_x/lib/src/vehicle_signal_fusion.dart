import 'package:driving_weather/driving_weather.dart';

import 'vehicle_condition_signals.dart';

// ---------------------------------------------------------------------------
// Deterministic fusion thresholds (typed, named — no magic numbers inline).
// ---------------------------------------------------------------------------

/// Road-friction estimate (0.0–1.0) below which the surface is treated as
/// icy/snowy. Matches the threshold documented on
/// `kRoadFrictionMostProbable` in `kuksa_dart_sdk`.
const double kIcyFrictionThreshold = 0.3;

/// Ambient temperature (°C) at/below which a TCS/ABS traction-loss event is
/// attributed to ice rather than aquaplaning / hard braking.
const double kColdSlipCelsius = 2.0;

/// Ambient temperature (°C) formerly assumed when the vehicle does not publish
/// `Vehicle.Exterior.AirTemperature`.
///
/// **Deprecated — this constant is a fabrication, not a safe default.** An
/// absent temperature is *unknown*, not "above freezing". Assuming +5 °C let a
/// missing signal *downgrade* a hazard: a car actively losing traction
/// (TCS/ABS/ESC engaged) on a road whose temperature it did not publish was
/// classified as `iceRisk: false` — "aquaplaning, not ice" — because the code
/// invented a warm reading. A real, present traction-loss event now keeps the
/// ice concern when the temperature is unknown (absence never downgrades a
/// hazard); the friction path was always temperature-independent.
///
/// The value (5.0) is retained for source compatibility. Since **0.3.4** it no
/// longer reaches a driver at all: [vehicleSignalsToWeatherConditionOrNull]
/// abstains — returns `null` — when no hazard is asserted and the temperature
/// was not measured, instead of substituting this number and letting the
/// downstream classifier read it as a thermometer reading.
@Deprecated(
  'An absent temperature is unknown, not above-freezing. Assuming +5 °C '
  'downgraded ice hazards. A present traction-loss event keeps the ice concern '
  'when temperature is unmeasured (0.3.2), and since 0.3.4 '
  'vehicleSignalsToWeatherConditionOrNull abstains rather than substituting '
  'this value at all.',
)
const double kAssumedAboveFreezingCelsius = 5.0;

/// Internal filler for the non-nullable `WeatherCondition.temperatureCelsius`
/// field when the vehicle publishes no usable ambient temperature.
///
/// It never decides ice risk: ice is asserted from a direct friction
/// measurement, or from a present traction-loss event (which stands on its own
/// when the temperature is unmeasured — 0.3.2). Since **0.3.4** it also decides
/// nothing else that reaches a driver, because the honest entry point
/// [vehicleSignalsToWeatherConditionOrNull] abstains before this value can be
/// read. It survives only behind the deprecated
/// [vehicleSignalsToWeatherCondition].
const double _kAbsentTempPrecipFallbackCelsius = 5.0;

// ---------------------------------------------------------------------------
// Deterministic vehicle-signal → existing-pipeline mapping.
// ---------------------------------------------------------------------------

/// Precipitation severity bucket 0 (none) … 3 (heavy), derived as the more
/// severe of the wiper-level and rain-sensor readings.
int _precipitationLevel(VehicleConditionSignals s) {
  int wiperLevel = 0;
  final wi = s.wiperIntensity;
  if (wi != null) {
    if (wi <= 0) {
      wiperLevel = 0;
    } else if (wi <= 2) {
      wiperLevel = 1;
    } else if (wi <= 4) {
      wiperLevel = 2;
    } else {
      wiperLevel = 3;
    }
  }

  int rainLevel = 0;
  final ri = s.rainIntensity;
  if (ri != null) {
    if (ri <= 0) {
      rainLevel = 0;
    } else if (ri <= 33) {
      rainLevel = 1;
    } else if (ri <= 66) {
      rainLevel = 2;
    } else {
      rainLevel = 3;
    }
  }

  return wiperLevel > rainLevel ? wiperLevel : rainLevel;
}

PrecipitationIntensity _intensityForLevel(int level) => switch (level) {
  0 => PrecipitationIntensity.none,
  1 => PrecipitationIntensity.light,
  2 => PrecipitationIntensity.moderate,
  _ => PrecipitationIntensity.heavy,
};

/// Explicit typed *proxy* for visibility (metres) from precipitation level.
/// A vehicle has no meteorological visibility sensor — this is a documented
/// cue, not a measurement. Only moderate+ precipitation reduces visibility
/// enough to raise the Snow Scene's fog wall.
double _visibilityMetersForLevel(int level) => switch (level) {
  0 => 10000.0, // clear
  1 => 5000.0, // light — still clear of the fog threshold
  2 => 800.0, // moderate — fog wall begins
  _ => 300.0, // heavy — short draw distance
};

/// The ambient temperature [s] actually MEASURED, or `null` when it did not.
///
/// `null` and a non-finite reading (`NaN` / `Infinity`, what a broken sensor or
/// a mis-decoded CAN frame produces) are the SAME answer: nobody read the
/// outside air. Up to 0.3.3 they were two different answers — `null` kept the
/// ice concern (0.3.2) while `NaN` silently did not, because `NaN <= 2.0` is
/// `false` and that is indistinguishable from "measured, and warm".
double? measuredAmbientCelsius(VehicleConditionSignals s) {
  final t = s.airTempC;
  if (t == null || !t.isFinite) return null;
  return t;
}

/// Why [vehicleSignalsToWeatherConditionOrNull] abstained, carried on the
/// emitted [VehicleConditionUpdate.unavailableReason] so an integrator can see
/// what to publish rather than guess.
const String kUnmeasuredTemperatureReason =
    'ambient temperature not measured (Vehicle.Exterior.AirTemperature): no '
    'hazard signal is present, and every remaining road-surface verdict would '
    'rest on a temperature nobody read';

/// Pure, deterministic mapping: decoded vehicle signals → the
/// [WeatherCondition] the `driving_conditions` pipeline consumes — **or `null`
/// when the snapshot cannot support the verdict it would otherwise produce.**
///
/// ## Why this returns `null` (added 0.3.4)
///
/// `WeatherCondition.temperatureCelsius` is a non-nullable `double` on the
/// `driving_weather` `0.4.x` line, so an *unknown* temperature has nowhere to
/// go: 0.3.3 filled it with `+5.0 °C` and every downstream branch then read
/// that number as if a thermometer had produced it.
///
/// Look at what the shared classifier actually does. `RoadSurfaceState`'s first
/// line is `if (condition.iceRisk) return blackIce` — decided WITHOUT the
/// temperature. **Every single branch after it reads the temperature**: the
/// residual-ice `temp <= -3`, the radiative-frost check, the freezing-rain
/// `temp <= 0`, the `standingWater` `temp > 3`, the snow `temp > 2` / `temp <
/// -2` splits. So when no hazard is asserted and the temperature was never
/// measured, there is no verdict left that is not a claim about an unread
/// number — including, above all, `dry` at `gripFactor: 1.0` with the advisory
/// "Conditions normal".
///
/// The rule, therefore, is the one this package already applies elsewhere:
/// **positive evidence of a hazard classifies on partial data; a benign verdict
/// must be earned.** `null` is not an alarm and cannot cry wolf — it says "not
/// measured", and the caller tells its driver so.
///
/// Returns `null` **iff** `iceRisk` is false AND
/// [measuredAmbientCelsius] is `null`. Whenever a temperature WAS measured,
/// the result and its classification are byte-for-byte what 0.3.3 produced.
///
/// The rules for the non-`null` result:
///  * **precipitation** present iff wiper/rain-sensor say so; type is `snow`
///    when temperature ≤ 0 °C else `rain` (temperature disambiguates what the
///    wiper cannot); intensity from [_intensityForLevel].
///  * **ice risk** iff a *direct* road measurement says so — friction below
///    [kIcyFrictionThreshold], OR a present traction-loss event (TCS/ABS/ESC
///    engaged) whose temperature is at/below [kColdSlipCelsius] **or not
///    measured**. Absence of temperature never *downgrades* this: a car losing
///    grip on a road whose temperature it did not publish keeps the ice concern
///    rather than being dismissed as aquaplaning (caution-add-only).
///  * **temperature** = the measured ambient air temp.
///  * **visibility** = the documented [_visibilityMetersForLevel] proxy.
///
/// The result is handed to `DrivingConditionAssessment.fromCondition` — the
/// existing classifier — so road-surface classification logic is reused, not
/// duplicated.
WeatherCondition? vehicleSignalsToWeatherConditionOrNull(
  VehicleConditionSignals s, {
  DateTime? timestamp,
}) {
  final condition = _fuse(s, timestamp: timestamp);

  // POSITIVE evidence: a friction reading or an attributable traction-loss
  // event asserts the hazard on its own. It never needed the temperature, and
  // withholding it here would be the under-warn 0.3.2 closed.
  if (condition.iceRisk) return condition;

  // No hazard asserted. Everything else the classifier could say from here
  // reads a temperature that was never measured — so we say nothing.
  if (measuredAmbientCelsius(s) == null) return null;

  return condition;
}

/// The 0.3.3 mapping, preserved verbatim for source compatibility.
///
/// **It fabricates.** When the vehicle publishes no usable ambient temperature
/// this substitutes `+5.0 °C` and hands it downstream as if measured, which:
///
///  * types falling precipitation `rain` (never `snow`), so a −5 °C snowfall
///    classifies `wet` (grip 0.70) instead of `slush`/`compactedSnow`, and a
///    freezing-rain road classifies `wet` instead of `blackIce`;
///  * carries a no-precipitation frame past the residual-ice `temp <= -3`
///    branch out to `dry` — gripFactor **1.0**, "Conditions normal" — which is
///    an affirmative all-clear manufactured out of absence;
///  * publishes `temperatureCelsius: 5.0` and `isFreezing: false` to any caller
///    that displays or gates on them.
///
/// Use [vehicleSignalsToWeatherConditionOrNull], which answers `null` in
/// exactly those cases. This function is retained, not removed: deleting it
/// would break every `^0.3.x` build on the next `pub get`, and a broken build
/// is not a way to tell someone their code is wrong.
@Deprecated(
  'Fabricates +5.0 °C when the vehicle publishes no ambient temperature — '
  'typing snow as rain and turning a no-precipitation frame into "Conditions '
  'normal" at full grip. Use vehicleSignalsToWeatherConditionOrNull, which '
  'returns null when no hazard is asserted and the temperature was not '
  'measured.',
)
WeatherCondition vehicleSignalsToWeatherCondition(
  VehicleConditionSignals s, {
  DateTime? timestamp,
}) => _fuse(s, timestamp: timestamp);

/// The shared body. Total; never throws.
WeatherCondition _fuse(VehicleConditionSignals s, {DateTime? timestamp}) {
  final airTemp = measuredAmbientCelsius(s);
  // Non-hazard filler for the non-nullable field. Callers reach this value only
  // through the deprecated entry point above; the honest entry point abstains
  // before it can decide anything.
  final temp = airTemp ?? _kAbsentTempPrecipFallbackCelsius;
  final level = _precipitationLevel(s);

  final precipType = level == 0
      ? PrecipitationType.none
      : (temp <= 0 ? PrecipitationType.snow : PrecipitationType.rain);

  // A present traction-loss event (TCS/ABS/ESC engaged) is a direct indicator
  // of grip loss. On a cold road it is ice; historically it was dismissed as
  // aquaplaning only when the ambient temperature read *above* freezing. But an
  // UNMEASURED temperature is unknown, not warm — assuming +5 °C once returned
  // `iceRisk: false` for a car that was actively skidding. Caution-add-only:
  // absence must never downgrade a hazard, so an unmeasured temperature keeps
  // the ice concern here (it does not clear it). Since 0.3.4 a non-finite
  // reading counts as unmeasured too — `NaN <= kColdSlipCelsius` is `false`,
  // which had made a corrupt sensor behave exactly like a warm one. The
  // friction path below is temperature-independent and unaffected.
  final tractionLoss =
      s.tcsEngaged == true || s.absEngaged == true || s.escEngaged == true;
  final coldOrUnknownTemp = airTemp == null || airTemp <= kColdSlipCelsius;

  final iceRisk =
      (s.roadFriction != null && s.roadFriction! < kIcyFrictionThreshold) ||
      (tractionLoss && coldOrUnknownTemp);

  return WeatherCondition(
    precipType: precipType,
    intensity: _intensityForLevel(level),
    temperatureCelsius: temp,
    visibilityMeters: _visibilityMetersForLevel(level),
    windSpeedKmh: 0.0, // not in the snow-safety signal set
    iceRisk: iceRisk,
    timestamp: timestamp ?? DateTime.now(),
  );
}
